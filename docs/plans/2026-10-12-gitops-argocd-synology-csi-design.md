# GitOps with Argo CD and Synology CSI

Date: 2026-10-12

## Goals

1. Manage the cluster from git with Argo CD instead of running `kubectl apply` by hand.
2. Provision iSCSI LUNs on the Synology NAS from Kubernetes using synology-csi, instead of creating them by hand in DSM.

## Starting point

- microk8s cluster. Kubelet data lives at `/var/snap/microk8s/common/var/lib/kubelet`, not the default path.
- Plain YAML in `media/` and `root/metallb/`, applied manually.
- cert-manager, NFD, Intel device plugins, MetalLB and the NFS provisioner were installed with `helm install`.
- Six apps (Plex, NZBGet, Sonarr, Radarr, Kavita, Mylar3) mount hand-made LUNs through inline `iscsi:` volumes, one IQN each, `lun: 1`.
- `shared-media-pv` is a static NFS PV for the media library. It stays.
- The NFS provisioner is no longer used and gets removed.
- `media/mylar3/` is running but not yet committed.

## Decisions

| Topic | Decision |
|:--|:--|
| Argo layout | App-of-apps. One root Application, one child per component. |
| Existing LUNs | Adopt in place as static PVs. No data movement. |
| Secrets | Sealed Secrets. Ciphertext is committed. |
| Repo | Public GitHub. Argo pulls anonymously. |
| NFS provisioner | Dropped. |
| Helm charts | Treated as platform plumbing, kept apart from workloads. |

## Repo layout

```
argocd/
  install/             # Argo CD helm values and namespace (hand-applied once)
  root-app.yaml        # app-of-apps, points at argocd/apps/
  apps/                # one Application per component
platform/
  sealed-secrets/
  synology-csi/        # manifests, StorageClass, VolumeSnapshotClass, sealed client-info
  metallb/             # moved from root/metallb: bgppeer.yaml, IP pool
media/                 # existing apps plus static PVs and PVCs for adopted LUNs
docs/plans/
```

Sync waves:

| Wave | Components |
|:--|:--|
| -3 | sealed-secrets |
| -2 | synology-csi, metallb |
| -1 | cert-manager, NFD, Intel operator and GPU plugin |
| 0 | media |

Other layout changes:

- `nzget.yaml` is renamed to `nzbget.yaml`.
- Third-party charts are pinned to specific versions (cert-manager v1.11.0, NFD 0.12.1) and bumped deliberately.
- `media` starts with automated sync and `prune: false`. Turn pruning on once the setup has proven itself.
- synology-csi has no official Helm chart. Its Application points at upstream manifests, patched for the microk8s kubelet path.

## Storage

- `StorageClass` `synology-iscsi`: `reclaimPolicy: Retain`, `allowVolumeExpansion: true`, `fsType: ext4`, location `volume1`.
- A `VolumeSnapshotClass` is provided alongside it.
- The class must create thin-provisioned LUNs. DSM does not support snapshots on thick LUNs, and snapshots also need a Btrfs volume (to be confirmed for `volume1`). The six adopted LUNs are thick, so CSI snapshots only apply to newly provisioned volumes.
- New apps request a PVC against the class. The LUN, target and mapping are created on the NAS at deploy time.
- Existing apps each get a static PV with `volumeHandle` set to the LUN's DSM UUID, plus a PVC. The pod mounts the PVC instead of the inline `iscsi:` block.

> **⚠️ Warning:** Adopting a hand-made LUN as a static PV depends on the driver finding the target the LUN is already mapped to. This is unverified. Trial it on Mylar3 first. If it fails, the other apps keep their inline `iscsi:` volumes and only new apps use the StorageClass.

Existing LUNs, from the DSM API (`SYNO.Core.ISCSI.LUN` list). The DSM UI does not show UUIDs.

| App | LUN | UUID | Size | Target IQN |
|:--|:--|:--|:--|:--|
| Plex | LUN-plex-data | `19ba39a3-11e3-4e9e-9756-4688148964a6` | 50 GiB | `iqn.2023-12.com.synology:deepthought.plex-1` |
| NZBGet | LUN-nzbget-data | `20cd546a-e47b-4452-8b43-96146ed4309f` | 2 GiB | `iqn.2023-12.com.synology:deepthought.nzbget-1` |
| Sonarr | LUN-sonarr-data | `688eba08-9dac-4691-a0b3-4c0d15e483be` | 10 GiB | `iqn.2023-12.com.synology:deepthought.sonarr-1` |
| Radarr | LUN-radarr-data | `6f35da2d-21a6-4b47-8db4-acea8489fe3f` | 10 GiB | `iqn.2023-12.com.synology:deepthought.radarr-1` |
| Kavita | LUN-kavita-data | `59cd8ffb-f290-4253-97f1-a957c96afe1b` | 10 GiB | `iqn.2025-06.com.synology:deepthought.kavita-1` |
| Mylar3 | LUN-mylar-data | `093280ae-f21c-4989-9d1c-db8be775a6d2` | 2 GiB | `iqn.2025-06.com.synology:deepthought.mylar-1` |

Mylar3 trial procedure:

1. Scale the deployment to 0.
2. Apply the static PV and PVC.
3. Switch the pod's volume to the PVC.
4. Scale to 1 and confirm the config and database are intact.

The remaining five apps follow only if the trial succeeds.

## Secrets

- Sealed Secrets controller runs in `kube-system` (or its own namespace), wave -3.
- Secret to seal: synology-csi `client-info` (DSM host, port, user, password).
- `plex-claim-token` is not sealed. The claim token is only used for first-time Plex setup or a re-claim. `PLEX_CLAIM` stays in `plex.yaml` with `optional: true` on the `secretKeyRef`, so Plex starts without the Secret. The Secret manifest is removed from the repo, because Argo would otherwise apply and revert it. Create it by hand when needed: `kubectl create secret generic plex-claim-token -n media --from-literal=token=claim-XXXX`. Argo ignores it because it is not in git.
- Seal with `kubeseal` and commit the resulting `SealedSecret` YAML. Plaintext never enters the repo.

> **🔒 Security:** The repo is public. The sealed ciphertext is only safe while the controller's private key stays private. Back the key up outside the cluster. Losing it means re-sealing every secret.

> **💡 Note:** LAN addresses and LUN IQNs are visible in a public repo. They are not credentials, but be aware of it.

Use a dedicated DSM account for the CSI driver rather than the admin account, with only the permissions it needs.

## Bootstrap

Two manual steps, then git is the source of truth:

1. `helm install argocd` into the `argocd` namespace using `argocd/install/` values.
2. `kubectl apply -f argocd/root-app.yaml`.

`bootstrap.sh` shrinks to those two commands. The README's per-component install sections are replaced with a description of the Application layout.

## Migrating the existing helm releases

Argo renders the charts itself and adopts the live resources. The old Helm release Secrets are left stale.

> **💥 DANGER:** Do not `helm uninstall` the old releases. That deletes the resources Argo just adopted. Remove only the release records, per namespace: `kubectl delete secret -l owner=helm,name=<release> -n <namespace>`.

The NFS provisioner is the exception. It is removed for real, after checking nothing uses its StorageClass:

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

0. Upgrade microk8s to a version Argo CD supports (see above).
1. Commit `media/mylar3/`. Fix the `nzbget.yaml` name. Move `root/metallb/` to `platform/metallb/`.
2. Install Argo CD and the root app with only Sealed Secrets enabled.
3. Add platform Applications one at a time, adopting each existing release.
4. Add synology-csi, the StorageClass and the sealed client-info.
5. Add the `media` Application with `prune: false`.
6. Run the Mylar3 static PV trial. Roll out to the other apps or stop, per the result.
7. Remove the NFS provisioner. Update the README and `bootstrap.sh`.

## Findings from the live cluster (2026-10-12)

- Helm releases: cert-manager v1.13.3, NFD 0.12.1, Intel operator and GPU plugin 0.28.0, nfs-subdir-external-provisioner 4.0.17. Pin to these, not the versions in the old README.
- MetalLB is not a Helm release. It was applied from the v0.13.5 manifest. The Application uses that manifest, with the existing `IPAddressPool` `local-usg` and the BGP advertisement and peer kept in `platform/metallb/`.
- The only PVC is `shared-media-pvc` (static NFS). Nothing uses the `nfs-client` StorageClass, so the provisioner is safe to remove.
- No VolumeSnapshot CRDs exist. The snapshot class needs the external-snapshotter CRDs and snapshot-controller, added as a platform component at wave -2.
- LoadBalancer addresses in use: .201 dashboard, .202 Plex, .203 NZBGet, .204 Sonarr, .205 Radarr, .206 Kavita, .207 Mylar3. The Argo CD UI, if exposed, takes .208.
- `media/plex/plex-claim-token.yaml` is a plaintext Secret in git history. The token was only used for first-time setup and is expired, so no history rewrite is needed. As part of the Plex migration, remove the manifest (and its line in `bootstrap.sh`) and mark the `secretKeyRef` in `plex.yaml` `optional: true`.

## Open items

- Whether to expose the Argo CD UI on a MetalLB address (for example 192.168.1.207) or keep it on port-forward.
- Dedicated DSM user for the CSI driver.
