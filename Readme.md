Home Kubernetes
===============

Single-node microk8s cluster, managed with GitOps. [Argo CD](https://argo-cd.readthedocs.io/) watches this repository and applies everything under `apps/`. To change the cluster, change the repo.

> **📌 Important:** Don't `kubectl apply` or `kubectl edit` things Argo manages. Self-heal reverts manual changes, and anything that drifts shows up as `OutOfSync` in the Argo CD UI.

# Layout

```
bootstrap/    one-time setup for a fresh cluster (see bootstrap/Readme.md)
argocd/       Argo CD install values and the ApplicationSet that registers apps/
apps/         one directory per component, each with a kustomization.yaml
docs/plans/   design documents
```

Every directory under `apps/` becomes an Argo CD Application of the same name. To add a component, add a directory with a `kustomization.yaml`. Plain manifests list themselves under `resources:`. Helm charts use `helmCharts:` with the chart version pinned (see `apps/cert-manager/` for an example).

| Directory                | What it is                                           | Namespace                   |
|:-------------------------|:-----------------------------------------------------|:----------------------------|
| `sealed-secrets`         | Encrypted secrets that are safe to commit            | `kube-system`               |
| `snapshot-controller`    | CSI volume snapshot CRDs and controller              | `kube-system`               |
| `metallb`                | LoadBalancer IPs over BGP, pool and peer config      | `metallb-system`            |
| `cert-manager`           | Issues the Intel operator's webhook certificate      | `cert-manager`              |
| `nfd`                    | Node Feature Discovery, labels the Intel GPU         | `node-feature-discovery`    |
| `intel-device-plugins`   | Operator and GPU plugin for Plex hardware transcoding | `inteldeviceplugins-system` |
| `media-shared`           | `media` namespace, shared NFS media volume           | `media`                     |
| `plex`, `sonarr`, `radarr`, `nzbget`, `kavita`, `mylar3` | Media applications | `media`                     |

> **💡 Note:** Pruning is off. Deleting a directory from `apps/` removes the Application but leaves its resources running until you delete them by hand. Turn on `prune` in `argocd/applicationset.yaml` once you trust the setup.

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
| Plex     | Plex media server            | `plex-tcp`, `plex-udp`  | http://192.168.1.202:32400/web  |
| NZBGet   | NZB download service         | `nzbget-tcp`            | http://192.168.1.203:6789       |
| Sonarr   | TV show download manager     | `sonarr-tcp`            | http://192.168.1.204:8989       |
| Radarr   | Movie download manager       | `radarr-tcp`            | http://192.168.1.205:7878       |
| Kavita   | Comics and ebook library     | `kavita-tcp`            | http://192.168.1.206:5000       |
| Mylar3   | Comic download manager       | `mylar-tcp`             | http://192.168.1.207:8090       |
| Argo CD  | GitOps controller (`argocd`) | `argocd-server`         | https://192.168.1.208           |

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
