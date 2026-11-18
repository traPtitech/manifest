#!/usr/bin/env python3
#MISE description="forward auth を使うホストで /_oauth/ が middleware を通るかを検査"
#MISE dir="{{cwd}}"
#USAGE arg "<file>..." help="ビルド済みマニフェストのファイル（すべてのディレクトリ分をまとめて渡す）"
"""forward auth を使うホストで、/_oauth/ の下が forward auth の middleware を通るかを検査する。

traefik-forward-auth は、auth host でログインしたユーザーを、各ホストの /_oauth/ticket で
受け取る ticket で引き継ぐ。このパスが middleware を通らずアプリに届くと、ログインが終わらないうえ、
アプリへのリクエストを読める人が ticket でそのホストにログインできてしまう。
https://github.com/traPtitech/traefik-forward-auth#routing-the-callback-path

検査では、forward auth の middleware を使うルートがあるホストごとに、/_oauth/ の下への GET を
Traefik と同じ規則でルートに振り分け、選ばれたルートが forward auth の middleware を使うことを確かめる。
"""

import re
import sys
from urllib.parse import urlparse

import yaml

CALLBACK_PATHS = ["/_oauth/ticket", "/_oauth/login", "/_oauth/logout"]
IMAGE = "ghcr.io/traptitech/traefik-forward-auth"
# ticket は https で届くので、https のエントリーポイントのルートだけを振り分けの対象にする
ENTRYPOINT = "websecure"

# 検査から外すホストと、その理由
EXCEPTIONS = {
    "q.trap.jp": "widget が trapti.tech 用の middleware を使っていて、どの middleware を使うべきかが決まっていない",
}


class Rule:
    """Traefik v3 のルールを、ヘッダーとクエリのない GET リクエストに対して評価する。"""

    TOKEN = re.compile(r"\s*(&&|\|\||!|\(|\)|,|`[^`]*`|\"(?:[^\"\\]|\\.)*\"|[A-Za-z]+)")

    def __init__(self, text):
        self.tokens = []
        pos = 0
        text = text.strip()
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                raise ValueError(f"cannot parse rule at {pos}: {text}")
            self.tokens.append(m.group(1))
            pos = m.end()
            while pos < len(text) and text[pos].isspace():
                pos += 1
        self.pos = 0
        self.tree = self._or()
        if self.pos != len(self.tokens):
            raise ValueError(f"unexpected token {self.tokens[self.pos]!r}: {text}")

    def _peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def _next(self):
        tok = self._peek()
        self.pos += 1
        return tok

    def _or(self):
        node = self._and()
        while self._peek() == "||":
            self._next()
            node = ("or", node, self._and())
        return node

    def _and(self):
        node = self._unary()
        while self._peek() == "&&":
            self._next()
            node = ("and", node, self._unary())
        return node

    def _unary(self):
        tok = self._next()
        if tok == "!":
            return ("not", self._unary())
        if tok == "(":
            node = self._or()
            if self._next() != ")":
                raise ValueError("missing )")
            return node
        name = tok
        if self._next() != "(":
            raise ValueError(f"expected ( after {name}")
        args = []
        while self._peek() != ")":
            arg = self._next()
            if arg == ",":
                continue
            args.append(arg[1:-1])
        self._next()
        return ("matcher", name, args)

    def hosts(self):
        """ルールに書かれた Host() のホスト名を返す。"""
        found = []

        def walk(node):
            if node[0] == "matcher":
                if node[1] == "Host":
                    found.extend(a.lower() for a in node[2])
            else:
                for child in node[1:]:
                    walk(child)

        walk(self.tree)
        return found

    def matches(self, host, path):
        return self._eval(self.tree, host, path)

    def _eval(self, node, host, path):
        kind = node[0]
        if kind == "or":
            return self._eval(node[1], host, path) or self._eval(node[2], host, path)
        if kind == "and":
            return self._eval(node[1], host, path) and self._eval(node[2], host, path)
        if kind == "not":
            return not self._eval(node[1], host, path)
        name, args = node[1], node[2]
        if name == "Host":
            return host in (a.lower() for a in args)
        if name == "HostRegexp":
            return re.search(args[0], host) is not None
        if name == "Path":
            return path == args[0]
        if name == "PathPrefix":
            return path.startswith(args[0])
        if name == "PathRegexp":
            return re.search(args[0], path) is not None
        if name == "Method":
            return args[0].upper() == "GET"
        # Header, Query, ClientIP など: ヘッダーとクエリのないリクエストには一致しないとみなす
        return False


def load(files):
    docs = []
    for f in files:
        with open(f) as fp:
            docs.extend(d for d in yaml.safe_load_all(fp) if isinstance(d, dict))
    return docs


def forward_auth_services(docs):
    """traefik-forward-auth の Pod に向く Service を (namespace, name) の集合で返す。"""
    pod_labels = []
    for d in docs:
        if d.get("kind") not in ("Deployment", "StatefulSet", "DaemonSet"):
            continue
        template = (d.get("spec") or {}).get("template") or {}
        containers = (template.get("spec") or {}).get("containers") or []
        if any(str(c.get("image", "")).startswith(IMAGE) for c in containers):
            labels = (template.get("metadata") or {}).get("labels") or {}
            pod_labels.append((d["metadata"].get("namespace"), labels))

    services = set()
    for d in docs:
        if d.get("kind") != "Service":
            continue
        meta = d.get("metadata", {})
        selector = (d.get("spec") or {}).get("selector") or {}
        for namespace, labels in pod_labels:
            if selector and meta.get("namespace") == namespace and selector.items() <= labels.items():
                services.add((namespace, meta.get("name")))
    return services


def forward_auth_middlewares(docs):
    """traefik-forward-auth に問い合わせる middleware を (namespace, name) の集合で返す。chain は中身をたどる。"""
    services = forward_auth_services(docs)
    middlewares = {}
    for d in docs:
        if d.get("kind") == "Middleware":
            meta = d.get("metadata", {})
            middlewares[(meta.get("namespace"), meta.get("name"))] = d.get("spec") or {}

    def targets_service(namespace, address):
        # Service の宛先は "<name>", "<name>.<namespace>", "<name>.<namespace>.svc(.cluster.local)" のいずれか
        parts = (urlparse(address).hostname or "").split(".")
        return (parts[1] if len(parts) > 1 else namespace, parts[0]) in services

    def is_forward_auth(key, seen=()):
        spec = middlewares.get(key)
        if spec is None or key in seen:
            return False
        if "forwardAuth" in spec:
            return targets_service(key[0], spec["forwardAuth"].get("address", ""))
        for ref in (spec.get("chain") or {}).get("middlewares") or []:
            if is_forward_auth((ref.get("namespace", key[0]), ref.get("name")), seen + (key,)):
                return True
        return False

    return {key for key in middlewares if is_forward_auth(key)}


def routes(docs, fa_middlewares):
    """IngressRoute のルートを (名前, Rule, 優先度, forward auth を使うか) で返す。"""
    result = []
    for d in docs:
        if d.get("kind") != "IngressRoute":
            continue
        meta = d.get("metadata", {})
        namespace = meta.get("namespace")
        spec = d.get("spec") or {}
        if spec.get("entryPoints") and ENTRYPOINT not in spec["entryPoints"]:
            continue
        for i, r in enumerate(spec.get("routes") or []):
            match = r.get("match")
            if not match:
                continue
            rule = Rule(match)
            priority = r.get("priority") or len(match)
            uses_fa = any(
                (m.get("namespace", namespace), m.get("name")) in fa_middlewares
                for m in r.get("middlewares") or []
            )
            result.append((f"{namespace}/{meta.get('name')} routes[{i}]", rule, priority, uses_fa))
    return result


def main(files):
    docs = load(files)
    all_routes = routes(docs, forward_auth_middlewares(docs))

    hosts = sorted({h for _, rule, _, uses_fa in all_routes if uses_fa for h in rule.hosts()})
    errors = []
    for host in hosts:
        if host in EXCEPTIONS:
            print(f"skip {host}: {EXCEPTIONS[host]}", file=sys.stderr)
            continue
        for path in CALLBACK_PATHS:
            matched = [r for r in all_routes if r[1].matches(host, path)]
            if not matched:
                errors.append(f"{host}{path}: どのルートにも一致しない")
                continue
            name, _, _, uses_fa = max(matched, key=lambda r: r[2])
            if not uses_fa:
                errors.append(f"{host}{path}: forward auth の middleware のない {name} に振り分けられる")

    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(
            "\nforward auth を使うホストでは、/_oauth/ の下を forward auth の middleware に通すルートを足してください。\n"
            "例: Host(`<host>`) && PathPrefix(`/_oauth/`) に、そのホストで使っている forward auth の middleware を付ける。\n"
            "https://github.com/traPtitech/traefik-forward-auth#routing-the-callback-path",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"checked {len(hosts)} hosts", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
