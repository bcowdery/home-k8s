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

# Sealing a secret

```shell
kubectl create secret generic example -n media --from-literal=key=value --dry-run=client -o yaml \
  | kubeseal --format yaml > apps/<app>/example-sealed.yaml
```

Add the file to that app's `kustomization.yaml` under `resources:`.
