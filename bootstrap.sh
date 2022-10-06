#!/bin/bash

# Install k3s
curl -sfL https://get.k3s.io | sh -s - server  \
    --cluster-init \
    --disable servicelb \
    --disable traefik

sudo chmod 644 /etc/rancher/k3s/k3s.yaml

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install Helm
snap install helm --classic

# Install NFS provisioner
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server=192.168.1.2 \
    --set nfs.path=/volume1/nfs-storage/

# Install MetalLB
# TODO: Helm or manifest? Helm appeared buggy... didn't use the metallb-system namespace
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.5/config/manifests/metallb-native.yaml
kubectl apply -f root/metallb/bgppeer.yaml

# Media
kubectl apply -f media/namespace.yaml
kubectl apply -f media/volumes.yaml

kubectl apply -f media/nzbget/nzbget.yaml

kubectl apply -f media/plex/plex-claim-token.yaml
kubectl apply -f media/plex/plex.yaml

# Unifi
kubectl apply -f unifi/namespace.yaml
kubectl apply -f unifi/unifi-controller/unifi-controller.yaml