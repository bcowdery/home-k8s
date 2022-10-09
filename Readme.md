Home Kubernetes
===============


# Getting Started

```shell
sudo apt install nfs-common
sudo apt install iptables-persistent

sudo iptables -P FORWARD ACCEPT
sudo ufw default allow routed

sudo snap install microk8s
sudo snap install kubectl --classic
sudo snap install helm --classic
```

# Configuration

```shell
mkdir ~/.kube

sudo usermod -a -G microk8s brian
sudo chown -f -R brian ~/.kube

kubectl config > ~/.kube/config

# install nfs provisioner
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.2 \
    --set nfs.path=/volume1/nfs-shares/

# install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
```

## Namespaces
### Media

Home media servers, download agents and supporting software.

| Service              | Description                         |Service               | Address                         |
|:---------------------|:------------------------------------|:---------------------|:--------------------------------|
| Plex                 | Plex media server                   | `plex-tcp,plex-udp`    | http://192.168.1.202:32400/web  |
| NzbGet               | NZB download service                | `nzbget-tcp`           | http://192.168.1.203:6789       |
| Sonarr               | TV Show download manager            | `sonarr-tcp`           | http://192.168.1.204:8989       |
| Radarr               | Movie download manager              | `radarr-tcp`           | http://192.168.1.205:7878       |

> 🔀 Internal DNS for media services `<service_name>.media.svc.cluster.local`

## Ubiquity Security Gateway

### Enable BGP

USG gateway connfig to enable BBP

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

Nuke k3s
```
sudo /usr/local/bin/k3s-uninstall.sh
```