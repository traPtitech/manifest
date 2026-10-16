# kmbk の監視

VictoriaMetrics が継承している `tailscale-sidecar` を使い、
`tailscale.kmbk.tokyotech.org` の exporter を scrape する。

| Job        | Port  | 対象          |
| ---------- | ----- | ------------- |
| `nodes`    | 9100  | node exporter |
| `cadvisor` | 9200  | cAdvisor      |
| `mysqld`   | 9104  | 本番 MariaDB  |
| `mysqld`   | 19104 | 開発 MariaDB  |

## kmbk 側の設定

node exporter は Tailscale IP でも待ち受ける。
cAdvisor と MySQL exporter は `192.168.0.10` のみで待ち受けるため、
kmbk 上で [Tailscale Serve の TCP 転送](https://tailscale.com/docs/reference/tailscale-cli/serve#use-a-tcp-forwarder)を設定する。
`--bg` により設定は永続化される。

```sh
sudo tailscale serve --bg --tcp=9200 tcp://192.168.0.10:9200
sudo tailscale serve --bg --tcp=9104 tcp://192.168.0.10:9104
sudo tailscale serve --bg --tcp=19104 tcp://192.168.0.10:19104
sudo tailscale serve status
```

この転送は既存の Tailscale tailnet 内から利用する。
VictoriaMetrics の Tailscale ノードから上記 4 ポートへの通信を ACL で許可する必要がある。

## 確認

VictoriaMetrics の `tailscale-sidecar` 内で各 endpoint が HTTP 200 を返すことを確認する。

```sh
kubectl -n monitor exec victoria-metrics-0 -c tailscale-sidecar -- sh -c '
  for port in 9100 9200 9104 19104; do
    wget -q -O /dev/null "http://tailscale.kmbk.tokyotech.org:$port/metrics" || exit 1
  done
'
```

反映後、Grafana で次のクエリが 4 系列すべて `1` を返すことを確認する。
MySQL exporter については `mysql_up{job="mysqld"}` も確認する。

```promql
up{job=~"nodes|cadvisor|mysqld", instance=~".*kmbk.*"}
```

## 転送の解除

```sh
sudo tailscale serve --tcp=9200 off
sudo tailscale serve --tcp=9104 off
sudo tailscale serve --tcp=19104 off
```
