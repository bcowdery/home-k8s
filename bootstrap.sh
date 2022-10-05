#!/bin/bash

# Install k3s
curl -sfL https://get.k3s.io | sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export RANCHER_HOSTNAME=rancher.lan

# Install Helm
snap install helm --classic

# Install NFS provisioner
# https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/blob/master/charts/nfs-subdir-external-provisioner/README.md

helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.2 \
    --set nfs.path=/volume1/nfs-storage/

# Install Rancher
#kubectl create namespace cattle-system

#helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
#helm repo update

#helm install rancher rancher-latest/rancher --namespace cattle-system --set ingress.tls.source=rancher --set hostname=rancher.lan

# Install MetalLB
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb

kubectl apply -f root/metallb/bgppeer.yaml

# Unifi
kubectl apply -f unifi/namespace.yaml
kubectl apply -f unifi/unifi-controller.yaml