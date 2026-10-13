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
| core    | `traefik`                | Ingress controller, wildcard certificate, LAN-only    | `traefik`                   |
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

# Services and addresses

Web UIs are served by one ingress ([Traefik](https://traefik.io/)) under `*.home.pointyspoon.com` with a Let's Encrypt wildcard certificate. They are reachable from the home network only. See [docs/ingress.md](docs/ingress.md) for how it works and what to do when it breaks.

| Service  | Description              | URL                                         | Notes                                   |
|:---------|:-------------------------|:--------------------------------------------|:----------------------------------------|
| Sonarr   | TV show download manager | https://sonarr.home.pointyspoon.com         |                                         |
| Radarr   | Movie download manager   | https://radarr.home.pointyspoon.com         |                                         |
| NZBGet   | NZB download service     | https://nzbget.home.pointyspoon.com         |                                         |
| Kavita   | Comics and ebook library | https://kavita.home.pointyspoon.com         |                                         |
| Mylar3   | Comic download manager   | https://mylar.home.pointyspoon.com          | parked (`replicas: 0`)                  |
| Argo CD  | GitOps controller        | https://argocd.home.pointyspoon.com         | also https://192.168.1.202 (see below)  |
| Plex     | Plex media server        | http://192.168.1.203:32400/web              | own IP, needed for discovery            |

LoadBalancer IPs (MetalLB pool `192.168.1.201-254`, outside the DHCP range):

| IP              | What                                                                                  |
|:----------------|:--------------------------------------------------------------------------------------|
| `192.168.1.201` | Traefik, the ingress for every hostname above                                         |
| `192.168.1.202` | Argo CD directly. Kept as a path that does not depend on Traefik, DNS or the certificate |
| `192.168.1.203` | Plex. Plex's discovery (GDM, DLNA, mDNS) wants its own address                        |

> **💡 Note:** Inside the cluster, apps still reach each other by Service name, for example Sonarr and Radarr use `nzbget-tcp.media.svc.cluster.local` and `plex-tcp.media.svc.cluster.local`. Those Service names must not change.

> **🧠 Pro-tip:** If Traefik or DNS is broken, `kubectl port-forward -n media svc/sonarr-tcp 8989` reaches any app using nothing but `kubectl`.

## Name resolution

Clients use the NAS (`192.168.1.2`) as their DNS server, and it forwards to the UniFi gateway. The gateway holds the names as `static-host-mapping` entries in `config.gateway.json` on the UniFi controller (a copy sits in the repo root but is git-ignored, since it describes the network). Entries to keep:

| Name                              | Address         |
|:----------------------------------|:----------------|
| `sonarr`, `radarr`, `nzbget`, `kavita`, `mylar`, `argocd` `.home.pointyspoon.com` | `192.168.1.201` |
| `argo.lan` (alias `argo`, `argocd`) | `192.168.1.202` |
| `plex.lan` (alias `plex`)         | `192.168.1.203` |

> **⚠️ Warning:** UniFi only applies changes to `config.gateway.json` when the gateway is re-provisioned, and recent versions removed the Force Provision button. Changing any trivial device setting (toggling the device LED works) triggers a provision. The gateway's DNS restarts for about a minute afterwards.

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
