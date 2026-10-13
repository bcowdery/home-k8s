Home Kubernetes
===============

Single-node microk8s cluster, managed with GitOps. [Argo CD](https://argo-cd.readthedocs.io/) watches this repository and applies everything under `apps/`. To change the cluster, change the repo.

> **📌 Important:** Don't `kubectl apply` or `kubectl edit` things Argo manages. Self-heal reverts manual changes, and anything that drifts shows up as `OutOfSync` in the Argo CD UI.

# Layout

```
bootstrap/    one-time setup for a fresh cluster (see bootstrap/Readme.md)
argocd/       Argo CD install values, and config/ with the projects and the ApplicationSet
apps/
  core/       cluster plumbing, Argo CD project "core"
  media/      media apps and their storage, Argo CD project "media"
docs/         design documents and runbooks
```

Every directory under `apps/core/` and `apps/media/` becomes an Argo CD Application of the same name, in the project named by its parent folder. To add a component, add a directory with a `kustomization.yaml`. Plain manifests list themselves under `resources:`. Helm charts use `helmCharts:` with the chart version pinned (see `apps/core/cert-manager/` for an example).

| Project | Directory                | What it is                                            | Namespace                   |
|:--------|:-------------------------|:------------------------------------------------------|:----------------------------|
| core    | `sealed-secrets`         | Encrypted secrets that are safe to commit             | `kube-system`               |
| core    | `snapshot-controller`    | CSI volume snapshot CRDs and controller               | `kube-system`               |
| core    | `metallb`                | LoadBalancer IPs over BGP, pool and peer config       | `metallb-system`            |
| core    | `cert-manager`           | Issues the Intel operator's webhook certificate       | `cert-manager`              |
| core    | `nfd`                    | Node Feature Discovery, labels the Intel GPU          | `node-feature-discovery`    |
| core    | `intel-device-plugins`   | Operator and GPU plugin for Plex hardware transcoding | `inteldeviceplugins-system` |
| core    | `synology-csi`           | Provisions iSCSI volumes on the Synology NAS          | `synology-csi`              |
| media   | `media-shared`           | `media` namespace, shared NFS media volume            | `media`                     |
| media   | `plex`, `sonarr`, `radarr`, `nzbget`, `kavita`, `mylar3` | Media applications        | `media`                     |

## Conventions

- **Projects:** `core` is unrestricted. `media` may only deploy into the `media` namespace and may only create Namespaces and PersistentVolumes at cluster scope. Both are defined in `argocd/config/projects.yaml`.
- **Labels:** apps written here carry `app.kubernetes.io/name` and `app.kubernetes.io/part-of` (the project name), added in each `kustomization.yaml`. They go on object metadata only, never on selectors or pod templates, so adding them restarts nothing. The older `app: <name>` label stays because Services and Deployment selectors depend on it. Helm charts keep their own labels.
- **Annotations:** each media Service has `link.argocd.argoproj.io/external-link`, which shows up as a link in the Argo CD UI. Namespaces carry `kubernetes.io/description`.
- **Prune:** on. Removing a manifest from git deletes it from the cluster. Namespaces and volume claims are exempt (`argocd.argoproj.io/sync-options: Prune=false`) so a mistaken delete can't take data with it, and the Applications leave their resources running if an Application itself is ever deleted.
- **Namespaces:** one per component under `core`, plus `media`. Sealed Secrets and the snapshot controller stay in `kube-system` because `kubeseal` and the upstream manifests expect them there.

> **📌 Important:** Everything under `argocd/config/` is itself managed by Argo CD (the `argocd-config` Application), so changes to projects or the ApplicationSet go live on push.

# Getting started

Node prerequisites (Ubuntu):

```shell
sudo apt install nfs-common open-iscsi
sudo apt install iptables-persistent

sudo iptables -P FORWARD ACCEPT
sudo ufw default allow routed

sudo snap install microk8s --classic --channel=1.33/stable
sudo snap install kubectl --classic
sudo snap install helm --classic

mkdir ~/.kube
sudo usermod -a -G microk8s brian
sudo chown -f -R brian ~/.kube
microk8s config > ~/.kube/config
```

Then follow [bootstrap/Readme.md](bootstrap/Readme.md).

# Storage

| Kind                       | Used by                                        | Notes                                              |
|:---------------------------|:-----------------------------------------------|:---------------------------------------------------|
| iSCSI LUN, inline `iscsi:` | Plex, Sonarr, Radarr, NZBGet, Kavita, Mylar3   | LUNs created by hand in DSM, one target each       |
| NFS, static PV             | `shared-media-pv` (media library, 6Ti)         | `apps/media-shared/volumes.yaml`                   |

> **⚠️ Warning:** Growing a LUN in DSM does not grow the filesystem inside it. After resizing a LUN, run `resize2fs` on the node against the device mounted under `/var/snap/microk8s/common/var/lib/kubelet/pods/*/volumes/kubernetes.io~iscsi/<name>`. It works online.

> **💥 DANGER:** Restarting containerd or the node can drop the iSCSI sessions. The LUNs then return under new `/dev/sdX` names while running containers keep mounts bound to the dead ones. Pods stay `Running`, but `/config` returns `Input/output error` or goes read-only. Before node maintenance, scale the iSCSI-backed apps to 0, wait for `sudo iscsiadm -m session` to show no sessions for them, then scale back up and test `touch /config/.rwtest` in each pod.

# Services

Home media servers, download agents and supporting software, in the `media` namespace.

| Service  | Description                  | Kubernetes service      | Address                         |
|:---------|:-----------------------------|:------------------------|:--------------------------------|
| Plex     | Plex media server            | `plex-tcp`, `plex-udp`  | http://192.168.1.203:32400/web  |
| NZBGet   | NZB download service         | `nzbget-tcp`            | http://192.168.1.203:6789       |
| Sonarr   | TV show download manager     | `sonarr-tcp`            | http://192.168.1.204:8989       |
| Radarr   | Movie download manager       | `radarr-tcp`            | http://192.168.1.205:7878       |
| Kavita   | Comics and ebook library     | `kavita-tcp`            | http://192.168.1.206:5000       |
| Mylar3   | Comic download manager       | `mylar-tcp`             | http://192.168.1.207:8090       |
| Argo CD  | GitOps controller (`argocd`) | `argocd-server`         | https://192.168.1.202           |

Kavita and Mylar3 are parked (`replicas: 0`). Set `replicas: 1` in their manifests to run them.

> **💡 Note:** Internal DNS for media services is `<service_name>.media.svc.cluster.local`.

# Ubiquiti Security Gateway

## Enable BGP

USG gateway config to enable BGP:

**data/sites/default/config.gateway.json**
```json
{
	"protocols": {
        "bgp": {
            "64501": {
                "neighbor": {
                    "192.168.1.4": {
                        "remote-as": "64500"
                    }
                },
                "parameters": {
                    "router-id": "192.168.1.1"
                }
            }
        }
    }
}
```

# Removing

Remove microk8s and everything in it:

```shell
sudo snap remove microk8s --purge
```
