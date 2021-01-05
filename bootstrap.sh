#!/bin/bash

# Install k3s
curl -sfL https://get.k3s.io | sh -

# Install Helm
snap install helm --classic

# ENV
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export RANCHER_HOSTNAME=rancher.lan

# Install Cert Manager
kubectl create namespace cert-manager

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.1.0 --set installCRDs=true


# Install Rancher
kubectl create namespace cattle-system

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

helm install rancher rancher-latest/rancher --namespace cattle-system --set ingress.tls.source=rancher --set hostname=rancher.lan


# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
