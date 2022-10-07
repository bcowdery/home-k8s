Home Kubernetes
===============


# Getting Started

Install k8s & Helm

```shell
# install k8s
curl -sfL https://get.k3s.io | sh -s - server  \
    --cluster-init \
    --disable servicelb \
    --disable traefik

sudo chmod 644 /etc/rancher/k3s/k3s.yaml

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# install helm
snap install help --classic

# install nfs provisioner
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.2 \
    --set nfs.path=/volume1/nfs-shares/

# install metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml

# node dirs
sudo mkdir -p /opt/downloads
```


## Namespaces
### Media

Home media servers, download agents and supporting software.

| Service              | Description                          | IP Address       |
|:---------------------|:-------------------------------------|:-----------------|
| Plex                 | Plex media server                    | `192.168.1.202`    |
| NzbGet               | NZB download service                 | `192.168.1.203`    |
| Sonarr               | TV Show download manager             | `192.168.1.204`    |
| Radarr               | Movie download manager               | `192.168.1.205`    |



## Ubiquity Security Gateway

### Enable BGP


# Removing

Nuke k3s
```
sudo /usr/local/bin/k3s-uninstall.sh
```