# さくらクラスタのresources見直し（2026-10-19）

## 調査範囲と根拠

grafana-trap-sakura MCPのPrometheus datasource
`e2e5b6bb-7e2e-4ad0-87d2-9b0bbc47ffff`から、過去14日間のCPU、メモリ、
再起動、OOM終了理由、ノード容量を取得した。ApplicationSetの対象と照合し、
さくら専用の設定は`sakura-*`のoverlayで変更した。
共有manifestの変更は、同じアプリを利用する他環境にも影響する。

- [コンテナ別の観測値とPromQL](resources-observations-2026-10-19.json)
- [ノード容量・OOM履歴・再起動などの根拠](resources-cluster-evidence-2026-10-19.json)

メモリはコンテナごとのworking set最大値、CPUは5分rateのp99を15分間隔で評価した値を、
namespace/container単位で最大集約した。複数replica・複数リリースを含むため、Pod単位の
必要量を完全に表すものではない。短いスパイクや起動直後の負荷は取りこぼし得る。
上限到達時の使用量は制限されているため、観測最大値を実際の必要量とは見なしていない。

`last_terminated_reason=OOMKilled`は最後の終了理由であり、14日間のOOM発生件数ではない。
再起動数もOOMの件数ではない。長時間停止したPodや計測欠損もあるため、
以下の数値だけで再起動原因を断定しない。

## 変更内容

単位はメモリがMiB相当、CPUがmillicore。requestsは配置時の予約量、limitsは実行時の上限。
メモリ上限を増やす対象には、原則としてrequestsも増やし、配置判断に使用量を反映した。
CPU制限に頻繁に当たる処理にはバーストの余裕を追加した。

| 対象                           | 観測した最大メモリ | memory requests変更 | memory limits変更 | その他・判断理由                                                         |
| ------------------------------ | -----------------: | ------------------- | ----------------- | ------------------------------------------------------------------------ |
| Argo CD application controller |               1720 | 1024 → 1536         | 2048 → 3072       | OOM履歴、435再起動。CPU p99 671mに対しrequestsを100m → 750m              |
| Argo CD repo server            |                429 | 100 → 384           | 500 → 768         | 38再起動。CPU p99 315mに対しrequestsを100m → 400m                        |
| Grafana                        |                767 | 256 → 512           | 768 → 1024        | OOM履歴と上限接近                                                        |
| Loki                           |               1000 | 100 → 512           | 1000 → 1536       | OOM履歴。CPU requestsを50m → 200m                                        |
| VictoriaMetrics                |               1019 | 800 → 1024          | 1024 → 1536       | 上限接近。CPU requestsを100m → 200m                                      |
| Tempo                          |                510 | 128 → 384           | 512 → 768         | 上限接近。GOMEMLIMITを450MiB → 600MiB                                    |
| Traefik                        |                500 | 150 → 256           | 500 → 768         | OOM履歴。CPU p99 413mに対しrequestsを100m → 500m                         |
| Alloy（Deployment）            |            275以下 | 未指定 → 128        | 未指定 → 512      | namespace集約でOOM履歴。CPU requests/limitsを100m/500mに設定             |
| Alloy（DaemonSet）             |            275以下 | 未指定 → 64         | 未指定 → 512      | 小容量ノードにも常駐するため予約量を抑制。CPU requests/limitsは100m/500m |
| ns-system MariaDB              |                499 | 250 → 512           | 500 → 1024        | OOM履歴、8再起動。CPU requestsを10m → 200m                               |
| ns-controller                  |                443 | 100 → 384           | 500 → 768         | メモリ上限接近                                                           |
| ns-ssgen                       |                 48 | 30 → 64             | 50 → 128          | メモリ上限接近                                                           |
| Gitea runner（両実装）         |            253以下 | 128/64 → 256        | 256/128 → 512     | OOM履歴。act_runnerのCPU limitsを100m → 500m                             |
| Ghost Varnish                  |                256 | 64 → 256            | 256 → 512         | OOM履歴、26再起動。キャッシュ以外の使用量にも余裕を確保                  |
| Jomon                          |                 31 | 16 → 32             | 64 → 128          | OOM履歴があるため小さな余裕を追加                                        |
| MinIO                          |                512 | 320 → 384           | 512 → 1024        | 上限接近。CPU requests/limitsを100m/500mに変更                           |
| traQ Elasticsearch             |                600 | 500（維持）         | 600 → 1024        | JVM heap 256m以外の使用量にも余裕を確保                                  |
| traQ backend                   |                929 | 256 → 512           | 1024 → 1536       | 上限接近と予約不足                                                       |
| CodiMD                         |               1065 | 256 → 512           | 1536（維持）      | ノードの配置判断に使用量を反映                                           |
| Crowi MongoDB                  |                290 | 1024 → 512          | 2048（維持）      | 過大な予約を削減。観測最大値より余裕を残す                               |
| Nextcloud                      |                619 | 128 → 384           | 1024（維持）      | ノードの配置判断に使用量を反映                                           |
| Nextcloud cron                 |                195 | 64 → 128            | 256 → 384         | CPU throttle率約85%。CPU limitsを100m → 500m                             |
| Nextcloud dev cron             |                 75 | 64（維持）          | 128（維持）       | CPU throttle率約84%。CPU limitsを100m → 300m                             |
| knoQ backend                   |                279 | 96 → 256            | 512（維持）       | CPU throttle率約74%。CPU requests/limitsを100m/1000mへ                   |
| S3 exporter                    |                 33 | 20 → 48             | 50 → 96           | CPU throttle率約91%。CPU requests/limitsを100m/500mへ                    |

CPU throttle率は調査時点の1時間rateにおける、制限されたperiodの割合。
CPU時間の損失率ではなく、低頻度処理でも高い割合になり得る。
小さなexporterやwidgetの制限は、この割合だけでは一律に変更していない。

## 配置容量と適用時の注意

11ノードを確認。稼働中またはPendingのPodに限定したメモリrequests/allocatableは、
las211で約81%、csc301で約46%、sce312で約45%、eee101で約89%だった。
終了済みPodも含めるとlas211は約94%になるため、その値で容量を判断しない。
DaemonSetの予約追加も含めて小容量ノードの余裕が小さいことに注意する。

las211では主な予約増加がCodiMD +256Mi、traQ +256Mi、Nextcloud +256Mi、
cron +64Mi、MinIO +64Mi、Varnish +192Mi、Traefik +106Mi。
MongoDBの予約を512Mi減らすことで増加を一部相殺した。
それでも、ローリング更新で旧Podと新Podが重なるとPendingになる可能性がある。
local/hostPathストレージを使うサービスを、容量だけを理由に別ノードへ移す変更はしていない。

ノードのMemAvailable最小値はict201で約6.2%、ict203で約7.2%、sce312で約8.6%。
MemoryPressure/DiskPressure/PIDPressureは観測範囲ではすべて0だったが、
コンテナの上限を同時に使える容量があるという意味ではない。
今回のlimitsは同時最大使用量の保証ではなく、個別の短時間負荷に対する余裕である。

この変更はGitにコミットする。Push・クラスタへの直接applyは行わない。
mainへの反映時はArgo CDが自動同期する。
監視系、Argo CD・DB、アプリの順に状態を確認し、Pendingが発生したら
ノードのrequestsと更新中の重複Podを確認する。個別Podの手動削除で解消させない。

## resources以外にも調査が必要な対象

- NeoShowcase管理アプリ（ns-apps）は14日で計3099再起動。
  `nsapp-9fb4e315bd52570c69e970-0`が1080回、
  `nsapp-d223c78b851a64d817bad0-0`が306回、
  `nsapp-1681f9fc3b86adaae6e35b-0`が296回。
  共通メモリ上限150Miに近いアプリとOOM履歴がある。
  PodはNeoShowcaseが生成するため、個別アプリの終了理由・ログ・設定を確認して調整する必要がある。
  全アプリの上限増加は小容量ノードの同時使用量を大きくするため、共通設定は維持した。
- Harbor coreは計1059再起動だが観測メモリは72Mi、上限500Mi。
  resources不足という根拠が弱い。jobserviceにも終了理由Errorがある。
  DB・Redisへの接続、probe失敗、ログの調査が必要。
- LonghornのCSIやengine imageにも多数の再起動がある。
  ノード・ストレージ・接続障害とresources不足の切り分けが必要。
- Ghost本体にもOOM履歴があるが観測最大613Miに対し現行上限1280Mi。
  今回はVarnishを調整し、本体の上限増加は保留した。

## 適用後の確認

適用後24時間と7日後に、OOM終了時刻の更新、再起動増加、Pending、
各ノードのMemAvailable、CPU throttleを同じPromQLで再確認する。
requests増加だけで既存Podの配置が均等になることはない。
上限拡大後も使用量が増え続ける場合は、リークやキャッシュ設定を調査する。

## ローカル検証

- 変更対象の15アプリでKustomize/Helm展開に成功。
  検証用コピーから暗号化Secretのgeneratorsだけを除外したため、復号・Secret生成は未検証。
- kubeconform：325リソース中239件有効、invalid/error 0件。
  スキーマがないCRD等86件はスキップ。
- 展開後の84コンテナ定義でrequestsがlimits以下であることを確認。
  監視系・Argo CD・Alloyはoverlay/chartの展開後の値も確認。
- Prettier整形、git diff --checkに成功。
- クラスタへの適用と、適用後の安定性確認は未実施。

設計の根拠：Kubernetes公式の
[Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)。
スケジューラはrequestsを用い、CPU limitsはthrottle、memory limitsはOOM終了につながり得る。
