MetalLB
========

# Installation By Manifest
To install MetalLB, apply the manifest:

```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
# On first install only
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```

This will deploy MetalLB to your cluster, under the `metallb-system` namespace. The components in the manifest are:

The `metallb-system/controller` deployment. This is the cluster-wide controller that handles IP address assignments.
The `metallb-system/speaker` daemonset. This is the component that speaks the protocol(s) of your choice to make the services reachable.

Service accounts for the controller and speaker, along with the RBAC permissions that the components need to function.
The installation manifest does not include a configuration file. MetalLB’s components will still start, but will remain idle until you define and deploy a configmap. The `memberlist` secret contains the `secretkey` to encrypt the communication between speakers for the fast dead node detection.


## Configuration

Create a config map providing a pool of allocated IP addresses.

**Example:**
```
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.1.201-192.168.1.254
```

```
kubectl apply -f configmap.yaml
```
