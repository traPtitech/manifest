# external-ingest

クラスタ外のホスト（`Proxmox` 等）から、`room-vpn`（Headscale 製の tailnet）経由で
クラスタ内の `VictoriaMetrics` / `Loki` に push するための ingest proxy です。

## Design

`VictoriaMetrics` / `Loki` 本体を直接 tailnet に出さず、
専用の小さな proxy Pod だけを tailnet に参加させます。
proxy Pod 内の `nginx` が、cluster 内 Service へ HTTP で転送します。

```
[external host (Alloy)]
   │ HTTP
   │ over room-vpn (Headscale)
   ▼
[ingest proxy Pod]                       monitor namespace
   tailscale sidecar (room-vpn)          (tailnet 外)
   nginx sidecar     ──── Service ────▶  victoria-metrics / loki
```

これにより:

- VM / Loki 本体を tailnet に晒さなくて済む
- `Service.clusterIP` を manifest にハードコードしなくて済む
- 外部ホスト側は単に `http://victoria-metrics-ingest/api/v1/write` のような URL に
  HTTP で送るだけでよく、ローカル検証で `127.0.0.1:8428` 宛てに送るのと同じ形になる

## Files

- `victoria-metrics-proxy.yaml`
- `loki-proxy.yaml`
- `ksops.yaml`
- `secrets/`（暗号化された tailscale auth key を置く。詳細は下記）

## Tailnet endpoints

room-vpn の MagicDNS 上で次のホスト名で見える想定:

- Metrics: `http://victoria-metrics-ingest/api/v1/write`
- Logs: `http://loki-ingest/loki/api/v1/push`

`base_domain` を含む FQDN（例 `victoria-metrics-ingest.room-internal.trapti.tech`）でも到達可能。

## Headscale 側の準備

1. proxy 用の tag と user を Headscale に用意（例: `tag:monitor-ingest`、所有 user は admin）
2. proxy ごとに preauth key を 1 本ずつ発行する（reusable にしない）

   ```bash
   headscale preauthkeys create -u <admin-user> --tags tag:monitor-ingest
   headscale preauthkeys create -u <admin-user> --tags tag:monitor-ingest
   ```

3. 発行した key を、proxy ごとに次の Secret として `sops` 暗号化して
   `secrets/victoria-metrics-proxy-tailscale.enc.yaml`、
   `secrets/loki-proxy-tailscale.enc.yaml` に置く（暗号化前の例）:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: victoria-metrics-proxy-tailscale # loki 用は loki-proxy-tailscale
     annotations:
       kustomize.config.k8s.io/needs-hash: "true"
   stringData:
     TS_AUTHKEY: "<headscale-preauth-key>"
   ```

   `secrets/` は `.gitignore` で平文ファイルがブロックされており、
   `*.enc.yaml` のみ commit 可能。

ACL は最低限、外部ホスト用 tag（例 `tag:external-observer`）から
`tag:monitor-ingest` の `:80` / `:3100` への通信だけを許可する。

## 外部ホスト側

外部ホストは、`tailscale up --login-server=https://room-vpn.trap.jp --authkey=<preauth-key>` で
room-vpn に参加した上で、上の Tailnet endpoint に対して `Grafana Alloy` などから
`prometheus.remote_write` / `loki.write` で送信する。

外部ホストのセットアップ手順自体はこの manifest リポジトリの管轄外。
