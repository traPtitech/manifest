# さくらクラスタのresources見直し（2026-10-19）

## 調査と判断

grafana-trap-sakura MCPのPrometheus datasource
`e2e5b6bb-7e2e-4ad0-87d2-9b0bbc47ffff`で過去14日間の使用量、再起動、
OOM終了理由とノード容量を確認した。さらにRunning/PendingのPodごとに
namespace・workload・containerを照合し、変更後の予約量と更新時の追加予約を試算した。
Alloyのように従来requestsがなかったコンテナも含む。

- [コンテナ別の観測値とPromQL](resources-observations-2026-10-19.json)
- [OOM履歴・再起動・空きメモリの観測](resources-cluster-evidence-2026-10-19.json)
- [修正後のノード容量試算とPod別の変更値](resources-capacity-2026-10-19.json)

メモリ観測値は14日間のworking set最大、CPUは5分rateのp99を15分間隔で評価した値。
namespace/container集約は複数replicaやリリースを含み、短い負荷を取りこぼす可能性がある。
`last_terminated_reason=OOMKilled`は最後の終了理由であり、期間内のOOM発生件数ではない。
上限接近や過去のOOM履歴だけを理由に、すべての上限を大きく増やすことは避けた。

## ノードごとの容量

数値はMiB相当。現在の配置を維持し、Alloy Deploymentのみcsc301へ移す想定。
DaemonSetの全ノード分の予約を加算した。既存Podが自動的に分散するとは仮定していない。

| ノード | allocatable | 現在のメモリ予約 | 変更後のメモリ予約 | 変更後の予約率 | 更新中の追加予約 | 更新中の予約率 |
| ------ | ----------: | ---------------: | -----------------: | -------------: | ---------------: | -------------: |
| eee101 |        1867 |             1662 |               1694 |          90.7% |                0 |          90.7% |
| las211 |        7841 |             6328 |               6420 |          81.9% |              864 |          92.9% |
| sce312 |        3815 |             1732 |               2316 |          60.7% |               32 |          61.5% |
| csc301 |        7841 |             3588 |               4910 |          62.6% |             1332 |          79.6% |

更新中の追加予約は、変更対象DeploymentのmaxSurgeを同じノードに加算した。
TraefikはDaemonSetのmaxSurge=1を各ingressノードで別々に加算した。
GrafanaとAlloy Deploymentは更新中の追加Podを作らない。
CPUも同じ条件で計算し、全ノードで予約量がallocatable以下になることを確認した。
init containerの予約も保守的に合算しており、kube-schedulerの完全な再現ではない。
配置制約・taint・ストレージ・一時的な他Podの増加までは保証しない。

eee101は変更後も予約率が高い。Alloy Deploymentをcsc301に固定して追加予約を避け、
DaemonSetの追加を32Miに留めた。csc301が停止すると、このDeploymentは別ノードへ
自動退避せずPendingになる。クラスタイベントとOTLP転送に一時的な停止が生じ得る。
ログ収集のDaemonSetは各ノードで継続する。

## 主な設定

### 監視ノード（sce312）

| コンテナ        | memory requests | memory limits | 負荷を抑える設定                     |
| --------------- | --------------- | ------------- | ------------------------------------ |
| Grafana         | 256 → 384Mi     | 768 → 896Mi   | Recreateで更新時の二重起動を防止     |
| Loki            | 100 → 384Mi     | 1000 → 1152Mi | クエリ同時実行2、GOMEMLIMIT=800MiB   |
| VictoriaMetrics | 800Mi（維持）   | 1Gi（維持）   | memory.allowedPercentを80 → 60に変更 |
| Tempo           | 128 → 256Mi     | 512Mi（維持） | GOMEMLIMITを450 → 384MiBに変更       |
| S3 exporter     | 20 → 32Mi       | 50 → 64Mi     | CPU requests/limitsを100m/500mに設定 |

既存の有限メモリ上限の増加合計は294Mi。調査時のMemAvailableは約797Mi、
14日間の最小は約328Miだった。上限増加だけで余裕を使い切らないよう、
キャッシュとクエリ並列数も削減した。ただし、この差分は使用量の上限を保証する予測ではない。
Alloyには従来上限がなかったため、新たな384Miの上限は「既存上限の増加」に含めていない。
Grafanaは更新中に短い停止が発生する。

VictoriaMetricsのmemory.allowedPercentはキャッシュ等の予算で、プロセス全体のハード上限ではない。
GOMEMLIMITもGoランタイムのソフト上限であり、コンテナのmemory limitを置き換えない。
キャッシュ削減・クエリ並列数削減・GC増加により、クエリ待ち時間が増える可能性がある。

### las211と小容量ノード

- traQ backendとNextcloud本体のメモリ予約・上限は従来値を維持。
- GiteaのKubernetes runnerは64Mi/128Miを維持。
  Docker runnerのみ、従来の128Mi予約を維持して上限を256 → 320Miへ調整。
- Crowi MongoDBの予約を1024 → 512Miに削減。観測最大約290Miより余裕を残す。
- CodiMDの予約を256 → 512Mi、Varnishを64 → 192Miへ調整。
- MinIOの上限は512 → 640Mi、traQ Elasticsearchは600 → 768Miとし、予約は維持。
- Traefikの予約を150 → 192Mi、上限を500 → 640Miへ調整。
- Alloy DaemonSetは32Mi予約・384Mi上限。
  Pod別の観測最大は約86〜275Miであり、32Miで使用量を表せるという意味ではない。
  今回は小容量ノードの配置余裕を優先したため、メモリ圧迫時のevictionリスクは残る。
- Alloy Deploymentは観測最大約234Miに対し256Mi予約・384Mi上限。
  csc301に配置し、maxSurge=0/maxUnavailable=1で更新する。

las211の既存有限メモリ上限は合計674Mi増加するが、ノードの全コンテナが同時に
上限まで使用できる容量はない。既存サービスを含めたメモリの過剰割当は残っている。
上限変更でノードOOMが起きなくなると断定するものではない。

### csc301の主要コンポーネント

- Argo CD controller：メモリ上限2Giを維持し、予約を1Gi → 1536Miへ変更。
- repo server：256Mi予約・640Mi上限。
- MariaDB：384Mi予約・704Mi上限。
- ns-controller：256Mi予約・従来上限500Miを維持。
- ns-ssgen：64Mi予約・96Mi上限。

既存有限メモリ上限の増加は594Mi。移動するAlloyは観測最大約234Miを別途考慮する必要がある。
csc301への固定配置は、このノードの障害時の復旧性との交換条件である。

## 残る問題と適用後の確認

NeoShowcase管理アプリは14日で計3099再起動、Harbor coreは1059再起動を観測した。
これらは個別アプリのログ・probe・DB接続などの調査が必要。
Longhornにも多数の再起動があり、ノードやストレージの障害との切り分けが必要。
今回のresources変更だけで全再起動が解消するとは判断していない。

mainへのマージ後はArgo CDが自動同期する。直接applyは行っていない。
適用直後にPending、eviction、各ノードのMemAvailableと監視クエリの待ち時間を確認し、
24時間後・7日後にも再起動数とOOM終了時刻を確認する。
特にeee101は余裕が小さいため、新しいワークロードを追加する前に容量を再確認する。
共有manifestの変更は、同じアプリを利用する他環境にも影響する。

## 検証

- Secretのgeneratorsを除外した検証用コピーで、15アプリのKustomize/Helm展開に成功。
  Secretの復号・生成は未検証。
- kubeconform：325リソース中239件有効、invalid/error 0件。スキーマのない86件はスキップ。
- 現在のPod配置と更新中の追加Podを加算し、CPU・メモリ予約が全ノードの容量内であることを確認。
- 実クラスタへの適用、Loki/VictoriaMetricsの起動と負荷試験は未実施。

設計の根拠：
[Kubernetesのresources](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)、
[VictoriaMetricsのメモリ制御](https://docs.victoriametrics.com/victoriametrics/faq/#how-to-set-a-memory-limit-for-victoriametrics-components)、
[Lokiのクエリ並列数とOOM](https://grafana.com/blog/the-concise-guide-to-loki-how-to-get-the-most-out-of-your-query-performance/)。
