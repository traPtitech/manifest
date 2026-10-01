import json
import os
import ssl
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


def main():
    service_account = Path("/var/run/secrets/kubernetes.io/serviceaccount")
    namespace = (service_account / "namespace").read_text().strip()
    token = (service_account / "token").read_text().strip()
    context = ssl.create_default_context(cafile=str(service_account / "ca.crt"))
    request = Request(
        f"https://kubernetes.default.svc/apis/apps/v1/namespaces/{namespace}"
        "/deployments/traq-backend",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urlopen(request, context=context, timeout=20) as response:
            deployment = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            print("Initial deployment: notification skipped.")
            return
        raise

    current_image = next(
        container["image"]
        for container in deployment["spec"]["template"]["spec"]["containers"]
        if container["name"] == "traq-backend"
    )
    target_image = os.environ["TARGET_IMAGE"]
    if current_image == target_image:
        print("Backend image unchanged: notification skipped.")
        return

    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "")
    if not webhook_url:
        raise ValueError("Configure traq-discord-webhook Secret (key: url) first.")
    parts = urlsplit(webhook_url)
    query = dict(parse_qsl(parts.query))
    query["wait"] = "true"
    webhook_url = urlunsplit(parts._replace(query=urlencode(query)))
    payload = {
        "content": (
            "traQ バックエンドを更新します。一時的に接続が切れます。\n"
            f"`{current_image}` → `{target_image}`"
        ),
        "allowed_mentions": {"parse": []},
    }
    request = Request(
        webhook_url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "traQ-update-notification/1.0",
        },
        method="POST",
    )
    with urlopen(request, timeout=20) as response:
        response.read()
    print("Backend update notification sent.")


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        # Webhook URL や認証情報をログに出さない。
        print(f"Notification hook failed: HTTP {error.code}", file=sys.stderr)
        sys.exit(1)
    except URLError:
        print("Notification hook failed: connection error", file=sys.stderr)
        sys.exit(1)
    except ValueError, KeyError, StopIteration, OSError:
        print("Notification hook failed: check configuration", file=sys.stderr)
        sys.exit(1)
