Bootstrap
=========

Steps for bringing up a fresh cluster. Argo CD installs everything else from `apps/`.

# Prerequisites

- microk8s running and `kubectl` / `helm` pointed at it (see the main [Readme](../Readme.md))
- The Sealed Secrets key backup, if you are rebuilding an existing cluster (see below)

# Steps

```shell
./bootstrap/bootstrap.sh
```

This installs Argo CD with `argocd/values.yaml` and registers the ApplicationSet. Argo then creates one Application per directory in `apps/` and syncs them.

> **💡 Note:** Expect some Applications to fail their first sync (a CRD that doesn't exist yet, a secret that hasn't been created). Retry with backoff is enabled, and they heal once the dependency lands.

Check progress:

```shell
kubectl -n argocd get applications
```

# Sealed Secrets key

Sealed Secrets can only decrypt secrets sealed against its own key. A new cluster generates a new key, so every committed `SealedSecret` fails to decrypt unless you restore the old one first.

Back up the key and store it somewhere outside the cluster and outside this repository:

```shell
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key.yaml
```

> **🔒 Security:** This file can decrypt every secret in the repository, and the repository is public. Never commit it. `.gitignore` does not cover it, so keep it out of this directory.

Restore on a fresh cluster, before Argo syncs `sealed-secrets`:

```shell
kubectl apply -f sealed-secrets-key.yaml
```

Then restart the controller if it was already running: `kubectl -n kube-system rollout restart deploy/sealed-secrets-controller`.

# Sealing the DSM credentials

The synology-csi driver reads its NAS login from a Secret named `synology-csi-client-info` in the `synology-csi` namespace. Seal it and commit the result as `apps/synology-csi/client-info-sealed.yaml`.

Run this in a regular terminal, not through Claude Code's `!` prefix. The password prompt needs a real TTY, and it keeps the password out of shell history and out of any chat transcript.

```shell
read -rs "P?DSM password for kube-csi: "; echo
kubectl create secret generic synology-csi-client-info -n synology-csi --dry-run=client -o yaml \
  --from-literal=client-info.yaml="clients:
  - host: 192.168.1.2
    https: true
    port: 5001
    username: kube-csi
    password: $P
    insecureSkipVerify: true" \
  | kubeseal --format yaml > apps/synology-csi/client-info-sealed.yaml
unset P
```

> **⚠️ Warning:** `insecureSkipVerify: true` is needed because DSM's default certificate has no DNS or IP name in it, so the driver can't verify it. The connection is encrypted, but the driver cannot confirm it reached the real NAS. To fix it properly, create a certificate in DSM with `192.168.1.2` as a SAN, then replace `insecureSkipVerify` with `tlsCACert`.

> **🔒 Security:** Use a dedicated DSM account for the driver, not your personal admin login, and change its password if it has ever been pasted into a chat or a file.

# Sealing a secret

```shell
kubectl create secret generic example -n media --from-literal=key=value --dry-run=client -o yaml \
  | kubeseal --format yaml > apps/<app>/example-sealed.yaml
```

Add the file to that app's `kustomization.yaml` under `resources:`.
