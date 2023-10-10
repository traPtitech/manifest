# manifest

k8s (k3s) manifest files for ArgoCD reference

## Before you start writing

If there is no yaml validation in CI (Continuous Integration), it is a good idea to install the following extension in your own editor and rely on completion.

### VSCode

ref: [Development Tools Greedy Set 2022 for Kubernetes Engineers](https://zenn.dev/zoetro/articles/9454a6231a1273#vscode-extensions)

Install [YAML - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) and add the following to `.vscode/settings.json`

```json
{
    "yaml.schemas": {
       "kubernetes": [
          "*.yml",
          "*.yaml"
       ]
    }
}
````

I don't know how to complete CRD (Custom Resource Definition)

### IntelliJ IDEA Ultimate

[Kubernetes - IntelliJ IDEs Plugin | Marketplace](https://plugins.jetbrains.com/plugin/10485-kubernetes)

If you add the CRD definition URL from `Languages & Frameworks > Kubernetes`, CRD completion will also work.
e.g. `https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml`

## How to write

### When adding/deleting/editing resources to an existing app

1. Edit the yaml of the resource you want to edit.
2. When adding/deleting resources, do not forget to update the reference from resources in `kustomization.yaml` of each directory.

### When adding a new app itself

1. Create a new directory and write resources.
2. Appropriately reference the resources you wrote from `kustomization.yaml`.
3. Add `- path: directory name` to `spec.generators.git.directories` in `./applications/application-set.yaml`.

## How to add a secret

The Secret is encrypted with [sops](https://github.com/mozilla/sops#encrypting-using-age) and [age](https://github.com/FiloSottile/age).
The encrypted Secret is read by ArgoCD through the [ksops kustomize plugin](https://github.com/viaduct-ai/kustomize-sops#argo-cd-integration-).
Since it uses public key cryptography, anyone can add a secret.

### Preparation

Let's install the following

- age: https://github.com/FiloSottile/age#installation
- sops: https://github.com/mozilla/sops#1download
    - Ubuntu: Pull `.deb` with `wget`/`curl` etc. and install with `sudo apt install ./sops_x.x.x_amd64.deb`

### encryption

1. `./encrypt.sh filename`
    - The contents of the file will be encrypted and replaced.
2. Reference the file from the `ksops.yaml` generator as follows.

````yaml
apiVersion: viaduct.ai/v1
Kind: ksops
metadata:
    name: ksops
    annotations:
       config.kubernetes.io/function: |
          exec:
            path: ksops

# edit here
files:
    - ./secrets/secret.yaml
````

3. Add the following line to `kustomization.yaml`.

````yaml
generators:
    -ksops.yaml
````

### Decrypt/Edit

Of course, this cannot be done without the key, so only admin can do it.
To prevent accidental commits, the file is not decrypted on the file system, but edited on the editor.
It will be automatically re-encrypted when you close the editor.

`./edit.sh filename`

## How to add/delete admin key

Of course, you can't do this unless you have at least one key that can decrypt it (that is, you are not an admin).

1. Update the public key list (comma-separated) in the `age` field of `.sops.yaml`
2. Run `./updatekeys.sh filename` for all Secret files
    - Since it exists under the `secrets` directory, it is easy to use `find . -type f -path '*/secrets/*' | xargs -n 1 ./updatekeys.sh`

NOTE: If you delete a key, be aware that its contents can be retroactively decrypted.
If the key is leaked, the contents of the Secret must also be changed.

## Bootstrap

How to build from scratch in case all k8s resources are blown away

First, check your current resources: `$ kubectl get --all-namespaces all`
If you cannot see the ArgoCD text, please do the following

1. Run Ansible and build a k3s cluster
    - [SysAd/tokyotech.org: traP Infrastructure as Code - tokyotech.org - traP Git](https://git.trap.jp/SysAd/tokyotech.org)
    - Be careful to execute in the order of master(k3s-server) → worker(k3s-agent)
    - If the cluster is rebuilt after executing master(k3s-server), don't forget to rewrite the value of `k3s_token` otherwise workers will not be able to join
2. Install ArgoCD
    - `kubectl create ns argocd`
    - Temporarily rewrite the contents of `./argocd/kustomization.yaml` as below
````yaml
resources:
    - https://raw.githubusercontent.com/argoproj/argo-cd/{{ version }}/manifests/install.yaml

patches:
    - path: argocd-cm.yaml
    - path: argocd-repo-server.yaml
````
    - `kubectl apply -n argocd -k argocd`
    - Restore the contents of `./argocd/kustomization.yaml`
3. Preparation for decryption of Secret encrypted by sops
    - `age-keygen -o key.txt`
    - Set the public key in the corresponding field of `.sops.yaml`
    - `kubectl -n argocd create secret generic age-key --from-file=./key.txt`
       - Referenced from `./argocd/argocd-repo-server.yaml`
    - `rm key.txt`
4. Port forward to access ArgoCD
    - `kubectl port-forward svc/argocd-server -n argocd 8124:443`
    - If you are using ssh, local forward e.g. `ssh -L 8124:localhost:8124 remote-name`
    - Access localhost:8124
    - Admin password: `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo`
5. Register `applications` application from ArgoCD UI
    - Generate an SSH key locally and register the public key in this repository (manifest) on GitHub
    - If necessary, register known_hosts first (GitHub's known_hosts is included by default)
    - The URL is in SSH format, paste the private key in the UI and add the repository
    - Add application (path: `applications`)
    - Perform Sync
6. You should now be able to access cd.trap.jp
    - Please note that after the ArgoCD application is synced, the argocd service port will change from 443 to 80.
    - If you want to continue accessing with local forward, use `kubectl port-forward svc/argocd-server -n argocd 8124:80`
