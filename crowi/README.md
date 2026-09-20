# Crowi 本番環境の移行

`wiki.trap.jp` をさくらクラスタで稼働させるための manifest。
Crowi は `replicas: 0`、定期バックアップは `suspend: true` で準備する。

## 切り替え手順

1. `secrets/swift-credentials.enc.yaml` の `CONOHA_PASS` は placeholder なので、
   `.scripts/secret-edit.sh crowi/secrets/swift-credentials.enc.yaml` で本番の値を設定する。
2. MongoDB・Elasticsearch の PVC はそれぞれ `10Gi`。MongoDB の現使用量は約 1.1 GB。Elasticsearch の使用量も確認し、必要に応じて増やす。
3. 切り替え時に Docker Compose 側の旧 Crowi の書き込みを停止し、MongoDB の最終バックアップを取得する。
   この manifest の変更によって、別サーバーの Docker Compose のコンテナやデータが削除されることはない。
4. さくら側の MongoDB にデータを復元する。MongoDB のデータには本番の OAuth 等のアプリ設定も含まれるため確認する。
   Elasticsearch は新規 PVC を使うので、旧データを移行するか Crowi から検索インデックスを再構築する。
5. `deployment.yaml` の `replicas` を `1` に変更し、ログイン・記事閲覧・更新・検索・添付ファイルを確認する。
   添付ファイルは既存の Swift コンテナ `crowi` を継続利用する。
6. DNS をさくら側へ切り替え、証明書と認証を確認する。
7. バックアップの手動実行を確認し、CronWorkflow の `suspend` を `false` に変更する。
   毎日 04:00（日本時間）に `gs://trap-services-backup/crowi-mongo-backup.gz` へ保存する。

## 旧 Kubernetes リソースについて

旧 manifest は `c1-203.tokyotech.org` の `hostPort: 9202` で Elasticsearch を公開していた。
ApplicationSet からの除外に伴う削除対象になり得るのは、この Kubernetes 管理のリソース。
提示された旧 `ELASTICSEARCH_URI` とホスト・ポートが一致するため、現在も利用している場合は検索への影響を切り替え時に考慮する。
