# GitOps with Argo CD and Synology CSI

Date: 2026-10-12

## Goals

1. Manage the cluster from git with Argo CD instead of running `kubectl apply` by hand.
2. Provision iSCSI LUNs on the Synology NAS from Kubernetes using synology-csi, instead of creating them by hand in DSM.

## Starting point

- microk8s cluster. Kubelet data lives at `/var/snap/microk8s/common/var/lib/kubelet`, not the default path.
- Plain YAML in `media/` and `root/metallb/`, applied manually.
- cert-manager, NFD and the Intel device plugins were installed with `helm install`. MetalLB was applied from the raw v0.13.5 manifest.
- Six apps (Plex, NZBGet, Sonarr, Radarr, Kavita, Mylar3) mount hand-made LUNs through inline `iscsi:` volumes, one IQN each, `lun: 1`.
- `shared-media-pv` is a static NFS PV for the media library. It stays.

## Decisions

| Topic | Decision |
|:--|:--|
| Argo layout | One ApplicationSet creates an Application per directory under `apps/`. No per-app Application files. |
| Directory layout | `bootstrap/`, `argocd/`, `apps/`. Organised by component, not namespace. Platform components and workloads live side by side in `apps/`. |
| App format | Every `apps/<name>/` is a kustomize directory. Helm charts use `helmCharts:` with the version pinned. Argo runs kustomize with `--enable-helm`. |
| Secrets | Sealed Secrets. Ciphertext is committed. |
| Repo | Public GitHub. Argo pulls anonymously. |
| NFS provisioner | Removed (2026-10-12). Nothing used its StorageClass. |
| Existing six LUNs | Stay on inline `iscsi:` volumes, managed declaratively. Not adopted into the CSI driver. |
| synology-csi scope | New volumes only. Kavita and Mylar3 (parked, little data) are recreated on CSI-provisioned PVCs as the first users. |
| Sync ordering | No sync waves (an ApplicationSet cannot order its Applications). Retry with backoff covers CRDs and secrets that land late. |
| Pruning | Off at first (`prune: false`). Turn on once the setup has proven itself. |

## Repo layout

```
bootstrap/             # bootstrap.sh and notes for bringing up a fresh cluster
argocd/
  values.yaml          # Argo CD helm values, installed once by bootstrap.sh
  applicationset.yaml  # one Application per apps/* directory
apps/
  sealed-secrets/  snapshot-controller/  synology-csi/
  metallb/  cert-manager/  nfd/  intel-device-plugins/
  media-shared/        # media namespace, shared NFS media PV/PVC
  plex/  sonarr/  radarr/  nzbget/  kavita/  mylar3/
docs/plans/
```

Pinned versions (verified against the chart repositories, 2026-10-12):

| Component | Source | Version |
|:--|:--|:--|
| Argo CD | `argo/argo-cd` chart | 10.10.3 (Argo CD v3.5.5) |
| Sealed Secrets | `https://bitnami.github.io/sealed-secrets` | 2.20.0 (controller 0.40.0) |
| synology-csi | community chart, `christian-schlichtherle/synology-csi-chart` | 0.11.3 (driver v1.3.1). 0.11.4 targets v1.4.0, which is not on Docker Hub yet |
| external-snapshotter | `kubernetes-csi/external-snapshotter` | v8.6.0 |
| MetalLB | raw manifest | v0.13.5 (unchanged) |
| cert-manager | `jetstack/cert-manager` | v1.13.3 (unchanged) |
| NFD | `node-feature-discovery` | 0.12.1 (unchanged) |
| Intel operator and GPU plugin | `intel-device-plugins-*` | 0.28.0 (unchanged) |

Adoption notes, from comparing each rendered app to the live cluster with a server-side `kubectl diff`:

- cert-manager, NFD and the Intel plugins render to zero diff. MetalLB differs only by the injected CRD `caBundle`, which the ApplicationSet ignores.
- NFD: the chart leaves the worker Role and RoleBinding without a namespace, so `apps/nfd/` patches them. The live NFD CRDs are newer than chart 0.12.1's, left by an earlier install, so `includeCRDs: false` stops Argo downgrading them.
- cert-manager: the `startupapicheck` post-install hook is disabled, because Helm already ran and deleted it.
- All Applications use `ServerSideApply=true`, since several CRDs exceed the client-side annotation size limit.
- Plex gets one deliberate change on first sync: the claim-token `secretKeyRef` becomes `optional: true`, which restarts the pod once.
- NZBGet has drift: the live ConfigMap says `TZ: America/Halifax`, the repo said `America/Edmonton`. Decide which is correct before the first sync, or Argo reverts the live value.

## Storage

- The six existing LUNs stay on inline `iscsi:` volumes. They work, Argo manages them fine as declared, and adopting hand-made LUNs into the CSI driver is unverified and only buys easier resizing.
- The CSI driver is for new volumes. Every iSCSI LUN it creates is thin-provisioned, which is what makes snapshots possible. Snapshots also need a Btrfs volume, which is unconfirmed for `volume1`.
- `StorageClass` `synology-iscsi`: `reclaimPolicy: Retain`, `allowVolumeExpansion: true`, `fsType: ext4`, location `/volume1`. Resizing then becomes a PVC edit in git instead of a DSM resize plus `resize2fs`.
- The node plugin needs `node.kubeletPath: /var/snap/microk8s/common/var/lib/kubelet`.
- The DSM credentials go in a SealedSecret named `synology-csi-client-info`, referenced from the chart with `clientInfoSecret.create: false`.
- Kavita and Mylar3 move to CSI-provisioned PVCs as the first users. Both are parked with little data, so they are recreated, not migrated. This also proves the driver works with the NAS.
- The CSI driver does not prevent the stale-device failure described below. Its node plugin uses the same iSCSI login and mount path.

> **💥 DANGER:** Never edit or rename a CSI-provisioned LUN in the DSM UI. Verified on Mylar3 (2026-10-12). The driver finds LUNs by name (`k8s-csi-<pv name>`), not by the UUID in `volumeHandle`, so a rename makes mounts and resizes fail with `Volume[<uuid>] is not found`. Saving an edit in the UI also makes DSM enforce its 10 GB minimum LUN size and silently grow the LUN, after which the driver refuses to resize below the real size (`expand size smaller than before`) and the resizer marks the request `ControllerResizeInfeasible`. Recovery: restore the exact original name, then set the PVC size to the LUN's real size.

> **📌 Important:** There is no way to name CSI LUNs. They are always `k8s-csi-pvc-<uuid>`. To find the LUN behind a PVC: `kubectl get pv -o custom-columns=PVC:.spec.claimRef.name,LUN:.metadata.name`. The DSM LUN UUID is the PV's `spec.csi.volumeHandle`.

> **🧠 Pro-tip:** Resizing works online and from git. Edit `spec.resources.requests.storage` in the PVC and Argo applies it. The LUN and the mounted ext4 filesystem grow in about a minute (tested 2Gi to 3Gi). A failed ("infeasible") request is not retried at the same size; request a different one.

Verified on 2026-10-12 with Kavita and Mylar3: provisioning (PVC `Bound` in about 3 seconds), mount (ext4, read-write) and online expansion all work.

> **📌 Important:** CSI volumes are never smaller than 10Gi (thin LUNs make this free, and it avoids the DSM UI's 10 GB minimum). Kavita, Mylar3, NZBGet, Sonarr and Radarr now run on CSI volumes, migrated with `docs/migrating-a-volume-to-csi.md`. Plex is the one remaining app on a hand-made LUN: a 50 GiB CSI volume never finished its first format inside the kubelet's mount timeout (see the gotchas in the runbook), so Plex was rolled back and its CSI volume removed. Revisit later; it is not a blocker.

> **💡 Note:** Migrating Plex to a CSI-provisioned volume is optional and was attempted once (see above): scale down, `rsync` the config into a new PVC, switch the volume. It would give thin LUNs, snapshots and git-driven resizing.

Existing LUNs, from the DSM API (`SYNO.Core.ISCSI.LUN` list). The DSM UI does not show UUIDs.

| App | LUN | UUID | Size | Target IQN |
|:--|:--|:--|:--|:--|
| Plex | LUN-plex-data | `19ba39a3-11e3-4e9e-9756-4688148964a6` | 50 GiB | `iqn.2023-12.com.synology:deepthought.plex-1` |
| NZBGet | LUN-nzbget-data | `20cd546a-e47b-4452-8b43-96146ed4309f` | 2 GiB | `iqn.2023-12.com.synology:deepthought.nzbget-1` |
| Sonarr | LUN-sonarr-data | `688eba08-9dac-4691-a0b3-4c0d15e483be` | 10 GiB | `iqn.2023-12.com.synology:deepthought.sonarr-1` |
| Radarr | LUN-radarr-data | `6f35da2d-21a6-4b47-8db4-acea8489fe3f` | 10 GiB | `iqn.2023-12.com.synology:deepthought.radarr-1` |
| Kavita | LUN-kavita-data | `59cd8ffb-f290-4253-97f1-a957c96afe1b` | 10 GiB | `iqn.2025-06.com.synology:deepthought.kavita-1` |
| Mylar3 | LUN-mylar-data | `093280ae-f21c-4989-9d1c-db8be775a6d2` | 2 GiB | `iqn.2025-06.com.synology:deepthought.mylar-1` |


## Secrets

- The Sealed Secrets controller runs in `kube-system` as `sealed-secrets-controller`, the name `kubeseal` looks for by default.
- Secret to seal: synology-csi `client-info` (DSM host, port, user, password).
- `plex-claim-token` is not sealed. The claim token is only used for first-time Plex setup or a re-claim. `PLEX_CLAIM` stays in `plex.yaml` with `optional: true` on the `secretKeyRef`, so Plex starts without the Secret. The Secret manifest is removed from the repo, because Argo would otherwise apply and revert it. Create it by hand when needed: `kubectl create secret generic plex-claim-token -n media --from-literal=token=claim-XXXX`. Argo ignores it because it is not in git.
- Seal with `kubeseal` and commit the resulting `SealedSecret` YAML. Plaintext never enters the repo.

> **🔒 Security:** The repo is public. The sealed ciphertext is only safe while the controller's private key stays private. Back the key up outside the cluster. Losing it means re-sealing every secret.

> **💡 Note:** LAN addresses and LUN IQNs are visible in a public repo. They are not credentials, but be aware of it.

Use a dedicated DSM account for the CSI driver rather than the admin account, with only the permissions it needs.

## Bootstrap

`bootstrap/bootstrap.sh` does two things, then git is the source of truth:

1. `helm upgrade --install argocd` into the `argocd` namespace with `argocd/values.yaml` (the UI is a LoadBalancer on 192.168.1.208).
2. `kubectl apply -f argocd/applicationset.yaml`.

`bootstrap/Readme.md` covers a fresh-cluster rebuild, including backing up and restoring the Sealed Secrets key before the first sync.

## Migrating the existing helm releases

Argo renders the charts itself and adopts the live resources. The old Helm release Secrets are left stale.

> **💥 DANGER:** Do not `helm uninstall` the old releases. That deletes the resources Argo just adopted. Remove only the release records, per namespace: `kubectl delete secret -l owner=helm,name=<release> -n <namespace>`.

The NFS provisioner was the exception. It was removed for real on 2026-10-12 (`helm uninstall`), after checking nothing used its StorageClass:

```shell
kubectl get pvc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SC:.spec.storageClassName
kubectl get sc
```

`shared-media-pv` and its PVC are unaffected. Their `storageClassName: nfs` is only a static-binding label and needs no provisioner.

## Prerequisite: upgrade microk8s

The cluster is a single node (`kube1`, Ubuntu 22.04, containerd 1.6.28) on Kubernetes v1.25.16. Argo CD 3.5 is tested on v1.33 to v1.36, so the cluster is upgraded first. Decided 2026-10-12.

> **⚠️ Warning:** One node means every hop restarts the API server and kubelet on the machine running all workloads. In practice (hop 1, 1.25 to 1.26) running pods kept running and restart counts stayed at 0; only the API was unavailable for a minute or two. A hop that changes the kubelet or containerd in a bigger way could still restart containers, so watch restart counts and do it when nobody is watching anything.

> **📌 Important:** Completed 2026-10-12. Cluster went 1.25.16 to 1.33.13 in eight single-minor hops with no data loss. Lessons: the 1.28 hop swaps Calico and the node sits `NotReady` for several minutes, which is normal. The 1.28 hop also left an orphaned `speaker` process holding port 7946 (the MetalLB pod crash-looped with `address already in use`). Fix: find it with `sudo ss -ltnp | grep 7946`, `sudo kill <pid>`, then `kubectl delete pod -n metallb-system <speaker pod>` to reset the backoff.

> **💥 DANGER:** The upgrade broke the iSCSI mounts for Plex, Sonarr, Radarr and NZBGet, and the damage was invisible from Kubernetes. Pods stayed `Running` and the NAS showed every target `connected`, but the iSCSI sessions had dropped and re-logged-in, the LUNs came back as new `sdX` devices, and the containers kept mounts bound to the dead ones. Symptoms: `Input/output error` or `Read-only file system` under `/config`, kernel `EXT4-fs error (device sdX)` for devices missing from `lsblk`, and Plex returning HTTP 500 while `/identity` still answered 200. Fix: scale the affected deployments to 0, confirm on the node that `iscsiadm -m session` is empty and no `kubernetes.io~iscsi` mounts remain, then scale back up (no data was lost). Prevention: scale iSCSI-backed apps to 0 before each hop, or at minimum before any hop that restarts containerd, and test `touch /config/.rwtest` in each pod after every hop. A pod being `Ready` does not prove its volume is writable.

> **📌 Important:** Ubuntu was patched afterwards (22.04.3 to 22.04.5, kernel 5.15.0-86 to 5.15.0-198) in a window with the iSCSI apps scaled to 0, followed by a reboot. The reboot cleared the orphaned MetalLB and Intel GPU plugin processes and showed the cluster survives a cold boot.

> **💡 Note:** Kavita and Mylar3 are parked (`replicas: 0`) on the cluster and in git. Set `replicas: 1` in the manifest to bring them back, so Argo's self-heal does not fight it.

Pre-flight:

1. Back up the app configs. DSM refuses snapshots on thick-provisioned LUNs, and all six existing LUNs are thick, so use Hyper Backup (LUN backup) or tar the config directories from inside the pods. For Plex, take the `Databases` directory and skip `Cache/` and `Metadata/`, which regenerate. This is insurance only: a microk8s upgrade does not touch the LUNs, which live on the NAS.
2. Back up the dqlite datastore: stop nothing, copy `/var/snap/microk8s/current/var/kubernetes/backend/` somewhere off the node.
3. Export the live state for reference: `kubectl get all,cm,secret,pvc,pv,ingress -A -o yaml > pre-upgrade.yaml`. Keep it out of git, because it contains secrets.
4. Confirm the target channels exist on the node with `snap info microk8s`.
5. Check deprecated API use before each hop. Today only `metallb.io/v1beta1 addresspools` shows up, which belongs to the old MetalLB 0.13.5 install.

Hop, one minor version at a time, on the node:

```shell
sudo snap refresh microk8s --channel=1.26/stable
microk8s status --wait-ready
kubectl get nodes; kubectl get pods -A
# repeat for 1.27, 1.28, ... up to 1.33 or later
```

Verify after each hop: node `Ready`, `kube-system` pods up, Plex `/identity` answers, MetalLB still announces its addresses, and the six iSCSI sessions are back (`sudo iscsiadm -m session`). Do not start the next hop until all of these pass.

> **🧠 Pro-tip:** Upgrading MetalLB itself (0.13.5 is old) can wait. Bringing it under Argo at its current version first keeps the change count down.

## Implementation order

Done:

1. Upgrade microk8s 1.25 to 1.33 and patch Ubuntu.
2. Resize the Sonarr and Radarr filesystems to match their LUNs.
3. Remove the NFS provisioner.
4. Clean up the repo (renames, `.gitignore`, track Mylar3, park Kavita and Mylar3).
5. Restructure into `bootstrap/`, `argocd/`, `apps/`; write the Argo CD values, ApplicationSet, and the platform apps; verify each against the live cluster with `kubectl diff`.

Next:

6. Settle the NZBGet `TZ` drift.
7. Push to GitHub, run `bootstrap/bootstrap.sh`, and watch the Applications adopt the running components. Plex restarts once.
8. Seal the DSM credentials and add `apps/synology-csi/` (chart, `StorageClass`, `VolumeSnapshotClass`).
9. Recreate Kavita and Mylar3 on CSI-provisioned PVCs.
10. Remove the stale Helm release records for cert-manager, NFD, dp-operator and gpu (never `helm uninstall` them).
11. Later, one at a time through git: bump NFD, then the Intel plugins and cert-manager, then MetalLB. Ubuntu 24.04 is a separate project.

## Findings from the live cluster (2026-10-12)

- Helm releases: cert-manager v1.13.3, NFD 0.12.1, Intel operator and GPU plugin 0.28.0, Pinned to these, not the versions in the old README.
- MetalLB is not a Helm release. It was applied from the v0.13.5 manifest. `apps/metallb/` uses that manifest plus `config.yaml` with the existing `IPAddressPool` `local-usg`, the BGP advertisement and the BGP peer (192.168.1.1, ASN 64500 to 64501).
- The only PVC is `shared-media-pvc` (static NFS). Nothing uses the `nfs-client` StorageClass, so the provisioner is safe to remove.
- No VolumeSnapshot CRDs exist. The snapshot class needs the external-snapshotter CRDs and snapshot-controller, added as `apps/snapshot-controller/`.
- LoadBalancer addresses in use: .201 dashboard, .202 Plex, .203 NZBGet, .204 Sonarr, .205 Radarr, .206 Kavita, .207 Mylar3. The Argo CD UI takes .208.
- `media/plex/plex-claim-token.yaml` is a plaintext Secret in git history. The token was only used for first-time setup and is expired, so no history rewrite is needed. The manifest is removed and the `secretKeyRef` in `plex.yaml` is `optional: true`.

## Open items

- NZBGet `TZ`: `America/Halifax` (live) or `America/Edmonton` (repo)?
- Dedicated, least-privilege DSM user for the CSI driver (`kube-csi` currently has admin rights). Rotate its password, which was shared in a chat transcript.
- Confirm `volume1` is Btrfs. CSI snapshots need it, and no snapshot has been tried yet.
- Clean up the leftover dead pods (`Completed`, `ContainerStatusUnknown`, `Error`) in `media`.
