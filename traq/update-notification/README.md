# traQ バックエンド更新通知

本番の `traq` Application の PreSync Job で、現在の Deployment と更新先のバックエンドイメージを比較します。更新先は Kustomize の replacement で Deployment からコピーするため、更新時に通知用のイメージを書き換える必要はありません。

- イメージが同じ場合（フロントのみの更新など）と初回デプロイでは通知しません。
- イメージが変わる場合は Discord に更新開始を通知してから Sync を進めます。
- Webhook 未設定、API 読み取り失敗、通知失敗では Job が失敗し、更新を止めます。
- `traq-dev` には追加していません。設定変更や同一タグのイメージ差し替えによる再起動は検出しません。

## Webhook の設定

`secrets/discord-webhook.enc.yaml` に、SOPS で暗号化した placeholder `REPLACE_WITH_DISCORD_WEBHOOK_URL` を入れています。初回利用前に `stringData.url` を実際の Discord Webhook URL に差し替えてください。placeholder のままではバックエンド更新を止めます。

```sh
sops --set '["stringData"]["url"] "https://discord.com/api/webhooks/実際のID/実際のトークン"' traq/update-notification/secrets/discord-webhook.enc.yaml
```

Secret は PreSync の wave `-2` で作成し、wave `-1` の通知 Job より先に設定します。Webhook URL は Git に平文で保存しないでください。

## 運用上の注意

Application 全体を Sync してください。Selective Sync では Hook が実行されません。
通知後に更新が失敗して再 Sync した場合は、現在のイメージが変わっていなければ再通知します。
この Job は更新開始だけを通知し、復旧完了・更新失敗の Discord 通知は行いません。

```sh
python -B -m unittest discover -s traq/update-notification -p 'test_*.py'
```
