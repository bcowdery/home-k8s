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
helm repo update

helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.2 \
    --set nfs.path=/volume1/nfs-shares/

# install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
```

## Intel GPU Support

For systems using intel integrated GPU's, install the [Intel Device Operator](https://github.com/intel/helm-charts/tree/main/charts/device-plugin-operator) and [Intel GPU plugin](https://github.com/intel/helm-charts/tree/main/charts/gpu-device-plugin) to enable use of Quick Sync for Plex video transcoding.

https://intel.github.io/intel-device-plugins-for-kubernetes/0.28/INSTALL.html


## Install helm repositories

```shell
helm repo add jetstack https://charts.jetstack.io # for cert-manager
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts # for NFD
helm repo add intel https://intel.github.io/helm-charts/ # for device-plugin-operator and plugins
helm repo update
```

## Install cert-manager

```
helm install --wait \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.11.0 \
  --set installCRDs=true
```

## Install NFD

```
helm install nfd nfd/node-feature-discovery \
  --namespace node-feature-discovery --create-namespace --version 0.12.1 \
  --set 'master.extraLabelNs={gpu.intel.com,sgx.intel.com}' \
  --set 'master.resourceLabels={gpu.intel.com/millicores,gpu.intel.com/memory.max,gpu.intel.com/tiles,sgx.intel.com/epc}'
```

## Install Operator & GPU Plugin

```
helm install dp-operator intel/intel-device-plugins-operator \
  --namespace inteldeviceplugins-system \
  --create-namespace

helm install gpu intel/intel-device-plugins-gpu \
  --namespace inteldeviceplugins-system \
  --create-namespace \
  --set nodeFeatureRule=true
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