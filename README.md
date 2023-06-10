# manifest

ArgoCD参照用 k8s (k3s) manifestファイル群

## 書き始める前に

CI(Continuous Integration)でのyamlのバリデーションが無い場合、各自のエディタに以下のような拡張機能をインストールし、補完を頼ると良いでしょう

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

### IntelliJ IDEA Ultimate

[Kubernetes - IntelliJ IDEs Plugin | Marketplace](https://plugins.jetbrains.com/plugin/10485-kubernetes)

`Languages & Frameworks > Kubernetes` より、CRD定義のURLを追加すると、CRDの補完も効くようになります
e.g. `https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml`

## 書き方

### 既存アプリにリソースを追加/削除/編集する場合

1. 編集したいリソースのyamlを編集します。
2. リソースを追加/削除した場合、各ディレクトリの `kustomization.yaml` の resources からの参照の更新を忘れないようにすること。

### アプリ自体を新しく追加する場合

1. 新しくディレクトリを作り、リソースを書いていきます。
2. `kustomization.yaml` から書いたリソースを適切に参照します。
3. `./applications/application-set.yaml` の `spec.generators.git.directories` に `- path: ディレクトリ名` を追加します。

## Secretの追加方法

Secretは[sops](https://github.com/mozilla/sops#encrypting-using-age)と[age](https://github.com/FiloSottile/age)で暗号化しています。
暗号化されたSecretは[ksops kustomize plugin](https://github.com/viaduct-ai/kustomize-sops#argo-cd-integration-)を通してArgoCDによって読まれます。
公開鍵暗号方式なのでSecretの追加自体は誰でも可能です。

### 前準備

以下をインストールしましょう

- age: https://github.com/FiloSottile/age#installation
- sops: https://github.com/mozilla/sops#1download
   - Ubuntu: `wget`/`curl`などで`.deb`を引っ張ってきて`sudo apt install ./sops_x.x.x_amd64.deb` でインストール

### 暗号化

1. `./encrypt.sh filename`
   - ファイルの中身が暗号化されて置き換わります
2.  `ksops.yaml` generator から以下のようにファイルを参照します。

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

3. 次の行を `kustomization.yaml` に追加します。

```yaml
generators:
   - ksops.yaml
```

### 復号化

もちろん鍵が無いとできないのでadminしかできません。

`./decrypt.sh filename`

## admin鍵の追加/削除方法

当然復号化できる鍵を1つ以上持っていないと（つまりadminでないと）できません。

1. `.sops.yaml` の `age` フィールドの公開鍵一覧(comma-separated)を更新
2. すべてのSecretファイルに対して、`./updatekeys.sh filename` を実行
   - `secrets` ディレクトリ以下に存在するので `find . -type f -path '*/secrets/*' | xargs -n 1 ./updatekeys.sh` とすると楽

NOTE: 鍵を削除する場合、中身は遡って復号化できることに注意
鍵が漏れた場合はSecretの中身も変えないといけません

## Bootstrap

万が一k8sのリソースが全部吹き飛んだ場合に1から構築する方法

まずは現在のリソースをチェック: `$ kubectl get --all-namespaces all`
ArgoCDの文字が見えなければ以下を行ってください

1. Ansibleを実行してk3sクラスタを構築
   - [SysAd/tokyotech.org: traP Infrastructure as Code - tokyotech.org - traP Git](https://git.trap.jp/SysAd/tokyotech.org)
   - master(k3s-server) → worker(k3s-agent) の順で実行することに注意
   - master(k3s-server) 実行後クラスタが再構築された場合、 `k3s_token` の値を書き換えるのを忘れないこと そうしないとworkerがjoinできません
2. ArgoCDをインストール
   - `kubectl create ns argocd`
   - `./argocd/kustomization.yaml` の中身を一旦下記に書き換える
```yaml
resources:
   - https://raw.githubusercontent.com/argoproj/argo-cd/v2.7.4/manifests/install.yaml

patches:
   - path: argocd-cm.yaml
   - path: argocd-repo-server.yaml
```
   - `kubectl apply -n argocd -k argocd`
   - `./argocd/kustomization.yaml` の中身を戻す
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
