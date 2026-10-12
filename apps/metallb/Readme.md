MetalLB
========

## Getting started

```
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb

kubectl apply -f root/metallb/bgppeer.yaml
```

## Configuration

MetalLB respects the `spec.loadBalancerIP` parameter, so if you want your service to be set up with a specific address, you can request it by setting that parameter. If MetalLB does not own the requested address, or if the address is already in use by another service, assignment will fail and MetalLB will log a warning event visible in `kubectl describe service <service name>`.

With the `Local` traffic policy, nodes will only attract traffic if they are running one or more of the service's pods locally. The
BGP router will load balance incoming traffic only across those nodes that are currently hosting the service. On each node, the
traffic is forwareded only to local pods by the `kube-proxy`, there is no "horizontal" traffic flow between nodes.

This policy provides the most efficient flow of traffic to your service. Furthermore, because kube-proxy doesn’t need to send traffic between cluster nodes, your pods can see the real source IP address of incoming connections.

Kubernetese does not allow multiprotocol LoadBalancer services. To work aroudn this limitation and have a service listen on both 
TCP and UDP, create two services (one for TCP, one for UDP), both with the same pod selector. Then, give them the same sharing key
and the `spec.loadBalancerIP` to colocate the TCP and UDP service ports on the same IP address.

```yaml
apiVersion: v1
kind: Service
metadata:
    name: example-tcp
    namespace: default
    annotations:
        metallb.universe.tf/allow-shared-ip: "example-svc"
spec:
    type: LoadBalancer
    loadBalancerIP: 192.168.1.202
    externalTrafficPolicy: Local
    ports:
        name: http
        protocol: TCP
        port: 80
        targetPort: 80
    selector:
        app: example
---
apiVersion: v1
kind: Service
metadata:
    name: example-udp
    namespace: default
    annotations:
        metallb.universe.tf/allow-shared-ip: "example-svc"
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.1.202
  externalTrafficPolicy: Local
  ports:
    - name: udp
      protocol: UDP
      port: 1900
      targetPort: 1900
  selector:
    app: example
```

**Resources:**
- https://metallb.universe.tf/usage/