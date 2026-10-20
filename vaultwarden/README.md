# Vaultwarden

The `vaultwarden` Application is managed by `sakura-applications` and deployed only to the Sakura cluster.

## Before merging

Do not merge or sync this application until the following prerequisites are complete:

1. Register a traQ OIDC client with the callback URL `https://vault.trap.jp/identity/connect/oidc-signin`.
2. Create the `service_vaultwarden` database and a dedicated user on `tailscale.kmbk.tokyotech.org:3306`. Use `utf8mb4` with `utf8mb4_unicode_ci` and grant access only to this database. The user needs `ALTER`, `CREATE`, `DELETE`, `DROP`, `INDEX`, `INSERT`, `REFERENCES`, `SELECT`, and `UPDATE` privileges for Vaultwarden schema migrations.
3. Create `vaultwarden/secrets/secrets.yaml` with the generated credentials, then encrypt it using the repository SOPS script:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: vaultwarden-secrets
     annotations:
       kustomize.config.k8s.io/needs-hash: "true"
   stringData:
     database-url: mysql://service_vaultwarden:<url-encoded-password>@tailscale.kmbk.tokyotech.org:3306/service_vaultwarden
     oidc-client-id: <traq-client-id>
     oidc-client-secret: <traq-client-secret>
   ```

   ```shell
   .scripts/secret-encrypt.sh vaultwarden/secrets/secrets.yaml
   ```

4. Create `vaultwarden/ksops.yaml` with `./secrets/secrets.enc.yaml` in its `files` list, then add `ksops.yaml` to the `generators` list in `vaultwarden/kustomization.yaml`.

The generated MySQL password must be percent encoded when it contains URI-reserved characters. Vaultwarden's MySQL backend requires the database charset and collation above.
