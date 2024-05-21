# manifest

Kubernetes manifestファイル群

mainブランチへの変更は、ArgoCDによって自動的に本番環境へ反映されます。

## 書き始める前に

GitHub Actionsでのyamlのバリデーションがありますが、各自のエディタに以下のような拡張機能をインストールし、補完を頼りながら書くと良いでしょう。

### VSCode

ref: [Kubernetesエンジニア向け開発ツール欲張りセット2022](https://zenn.dev/zoetro/articles/9454a6231a1273#vscode-extensions)

[YAML - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) をインストールし、以下を `.vscode/settings.json` に追加

```json
{
   "yaml.schemas": {
      "kubernetes": [
         "*.yml",
         "*.yaml"
      ]
   }
}
```

CRD(Custom Resource Definition)の補完は知らない
誰か知ってたら助けて

### IntelliJ IDEA Ultimate

[Kubernetes - IntelliJ IDEs Plugin | Marketplace](https://plugins.jetbrains.com/plugin/10485-kubernetes)

`Languages & Frameworks > Kubernetes` より、CRD定義のURLを追加すると、CRDの補完も効くようになります
e.g. `https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml`

## 書き方

各ディレクトリ（アプリ）には `kustomization.yaml` が置いてあり、ここを起点として kustomize によって読み込まれます。
また、各ディレクトリ（アプリ）は `./applications/application-set.yaml` を起点として読み込まれます。

具体的なリソースの書き方は、[Deployments | Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) のような公式ドキュメントや、既存アプリの書き方を参考にしてください。

### 既存アプリにリソースを追加・削除・編集する場合

1. 編集したいリソースのyamlを追加・削除・編集します。
2. リソースを追加・削除した場合、各ディレクトリの `kustomization.yaml` の `resources` フィールドの更新を忘れないようにすること。

### アプリ自体を新しく追加する場合

1. 新しくディレクトリを作り、リソースを書いていきます。
2. `kustomization.yaml` から書いたリソースを適切に参照します。
3. `./applications/application-set.yaml` の `spec.generators.git.directories` に `- path: ディレクトリ名` を追加します。

## Secretの追加・編集方法

公開鍵暗号方式なので、Secretの追加・値の上書きは誰でも可能です。

Secretは[sops](https://github.com/mozilla/sops#encrypting-using-age)と[age](https://github.com/FiloSottile/age)で暗号化しています。
暗号化されたSecretは[ksops kustomize plugin](https://github.com/viaduct-ai/kustomize-sops#argo-cd-integration-)を通してArgoCDによって読まれます。

### 前準備

以下が必要になるので、インストールしましょう。

- age: https://github.com/FiloSottile/age#installation
- sops: https://github.com/mozilla/sops#1download
   - Ubuntu: `wget`/`curl`などで`.deb`を引っ張ってきて`sudo apt install ./sops_x.x.x_amd64.deb` でインストール

### 新規Secretの追加

1. Secretを書く。

```yaml
apiVersion: v1
kind: Secret
metadata:
   name: my-secret
   annotations:
      # kustomizeによってSecret名にhash suffixを付けさせる設定
      # Secretの中身が変更されたとき、自動リロードが可能になる
      # kustomize設定のnameReferenceで、Secretを読む側のフィールドを参照する必要あり
      kustomize.config.k8s.io/needs-hash: "true"
stringData:
   my-secret-key: "my-super-secret-value"
```

2. Secretをsopsで暗号化する: `./encrypt-secret.sh secret.yaml`
   - ファイルの中身が暗号化されて置き換わります
3. `ksops.yaml` から以下のようにファイルを参照する。

```yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
   name: ksops
   annotations:
      config.kubernetes.io/function: |
         exec:
           path: ksops

# ここを編集
files:
   - ./secrets/secret.yaml
```

4. 次の行を `kustomization.yaml` に追加する。

```yaml
generators:
   - ksops.yaml
```

### 既存Secretの編集

既存Secretの値だけを上書きしたい場合、次のスクリプトで編集できます。

- `./set-secret.sh filename key data`
   - filenameにはファイル名
   - keyにはstringData以下のキー名
   - dataには上書きしたいデータ

Secret全体を一旦復号化して編集したい場合は、次のスクリプトで編集できますが、もちろん復号のための鍵が無いとできません。
誤ってコミットすることを防ぐため、ファイルシステム上で復号化はされず、エディター上で編集します。
エディターを閉じると自動的に再度暗号化されます。

- `./edit-secret.sh filename`

### 鍵の追加 / 削除方法

当然復号化できる鍵を1つ以上持っていないと（つまりadminでないと）できません。

1. `.sops.yaml` の `age` フィールドの公開鍵一覧(comma-separated)を更新
2. すべてのSecretファイルに対して、`./updatekeys.sh filename` を実行
   - `secrets` ディレクトリ以下に存在するので `find . -type f -path '*/secrets/*' | xargs -n 1 ./updatekeys-secret.sh` とすると楽

NOTE: 鍵を削除する場合、中身は遡って復号化できることに注意
鍵が漏れた場合はSecretの中身も変えないといけません

## Restore from Backup

万が一 master のホストが壊れたなどの理由で、k8sの状態が全部吹き飛んだ場合に、バックアップからから回復する方法です。

現在のリソースをチェック出来る場合はチェック: `$ kubectl get --all-namespaces all`
何も無ければ以下を行い、クラスタの状態をバックアップから回復してください。

このリポジトリの `./backup` 以下に、master ノードの SQLite の状態のバックアップを取るスクリプトが置かれています。
`/var/lib/rancher/k3s/server` 以下を tar.gz として保存し、Google Cloud Storage へバックアップしています。

これから回復するには、 https://docs.k3s.io/datastore/backup-restore の手順に従ってください。
tar.gz の中身から `db` ディレクトリと `token` ファイルを取り出し、元の `/var/lib/rancher/k3s/server` 以下に配置したあと、k3s (server) を起動してください。

## Bootstrap

クラスタ自体の構築記録です。
クラスタが吹き飛んだ場合、以下に沿って構築します。

1. Ansibleを実行してk3sクラスタを構築
   - [SysAd/tokyotech.org: traP Infrastructure as Code - tokyotech.org - traP Git](https://git.trap.jp/SysAd/tokyotech.org)
   - master (k3s-server) を構築
   - **バックアップが存在する場合**、この時点で k3s (server) をストップ、上の方法でリストアし、以下のステップは行わないでよい
   - Ansible 内の `k3s_token` の値を書き換える
   - worker (k3s-agent) を構築
2. ArgoCDをインストール
   - `kubectl create ns argocd`
   - `kustomize build ./argocd --enable-alpha-plugins --enable-exec | kubectl apply -n argocd -f -`
     - 心配な場合は、`kustomize build` の結果を一時ファイルに保存したり、`kubectl apply --validate=strict --dry-run=server -n argocd -f -` を代わりに使いDry-runで確かめたりすると良い
3. sopsにより暗号化されたSecretの復号化の準備
   - `age-keygen -o key.txt`
   - Public keyを `.sops.yaml` の該当フィールドに設定
   - `kubectl -n argocd create secret generic age-key --from-file=./key.txt`
      - `./argocd/argocd-repo-server.yaml` から参照されています
   - `rm key.txt`
4. Port forwardしてArgoCDにアクセス
   - `kubectl port-forward svc/argocd-server -n argocd 8124:443`
   - sshしている場合はlocal forward e.g. `ssh -L 8124:localhost:8124 remote-name`
   - localhost:8124 へアクセス
   - Admin password: `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo`
5. ArgoCDのUIから `applications` アプリケーションを登録
   - SSH鍵を手元で生成して、公開鍵をGitHubのこのリポジトリ (manifest) に登録
   - 必要な場合は先にknown_hostsを登録 (GitHubのknown_hostsはデフォルトで入っている)
   - URLはSSH形式で、秘密鍵をUIで貼り付けてリポジトリを追加
   - アプリケーションを追加 (path: `applications`)
   - Syncを行う
6. cd.trap.jp にアクセスできるようになるはず
   - ArgoCDアプリケーションがsyncされた後はargocd serviceのポートは443番から80番になるので注意
   - local forwardでのアクセスを続けたい場合は `kubectl port-forward svc/argocd-server -n argocd 8124:80`
