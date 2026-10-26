# Ingress, certificates and name resolution

Written 2026-10-12.

## How a request flows

```
browser -> AdGuard on the NAS (192.168.1.2) answers sonarr.home.pointyspoon.com = 192.168.1.201 (a DNS rewrite)
        -> MetalLB (BGP to the gateway) delivers 192.168.1.201 to the Traefik pod on kube1
        -> Traefik: LAN allowlist, wildcard certificate, route by Host header -> the app's Service
```

Public hostnames (only `books.pointyspoon.com` today) take a different path, see [Public hostnames](#public-hostnames).

Plex (`192.168.1.203`) and Argo CD (`192.168.1.202`) also have their own addresses and bypass Traefik.

## The parts

| Part | Where | Notes |
|:--|:--|:--|
| Traefik | `apps/core/traefik/` | One pod. CRDs come from the separate `traefik-crds` chart, because the main chart also installs 15 Traefik Hub CRDs. `externalTrafficPolicy: Local` keeps client source addresses so the allowlist works. |
| LAN-only | `apps/core/traefik/middleware.yaml` | `ipAllowList` for `192.168.0.0/16` on the websecure entrypoint. The gateway forwards WAN 443 only to the `public` entrypoint, never to websecure, so this is the second lock. |
| Public entrypoint | `apps/core/traefik/kustomization.yaml` | `public` on `192.168.1.201:9443`, no allowlist. Only routes that name it are attached; `web` and `websecure` are `asDefault`, so a route that names no entrypoint never lands on it. |
| Certificate | `apps/core/traefik/certificate.yaml` | `*.home.pointyspoon.com`, issued by `letsencrypt-prod`, set as Traefik's default certificate (`tlsStore`). A wildcard keeps individual hostnames out of the public certificate-transparency logs. |
| Issuers | `apps/core/cert-manager/clusterissuers.yaml` | `letsencrypt-staging` and `letsencrypt-prod`. Use staging while experimenting: production has strict rate limits. |
| Ingresses | `apps/media/<app>/ingress.yaml` | One per app, `ingressClassName: traefik`, websecure only. |
| Argo CD | `argocd/config/ingress.yaml` | An `IngressRoute`, not an `Ingress`: Traefik reads the backend scheme and `ServersTransport` from the Service, and Argo CD's Service is Helm-managed. |

## Why DNS-01 through acme-dns

The names are internal-only, so Let's Encrypt cannot reach them over HTTP, and DNS is hosted at Hover, which has no API and no cert-manager solver. Instead one CNAME at Hover points the challenge name into an [acme-dns](https://github.com/joohoi/acme-dns) account on the public `auth.acme-dns.io` instance:

```
_acme-challenge.home.pointyspoon.com  CNAME  <uuid>.auth.acme-dns.io
```

cert-manager writes the challenge TXT record to acme-dns through the account credential in the sealed Secret `acme-dns` (`apps/core/cert-manager/acme-dns-sealed.yaml`), and Let's Encrypt follows the CNAME to read it. Hover is never touched after that one record.

> **🔒 Security:** The acme-dns account can only change TXT records for its own challenge name, but a third party holds that credential's other half. If you ever lose the Sealed Secrets key, register a new account (`POST https://auth.acme-dns.io/register`), seal the new credential, and change the CNAME target at Hover.

## Renewal

cert-manager starts renewing about 30 days before expiry. The first expiry is 2027-01-10, so renewal begins around 2026-12-11. Renewal is the only thing that needs the internet; serving the certificate does not. Check it with:

```shell
kubectl get certificate -n traefik
kubectl describe certificate wildcard-home -n traefik
```

## Public hostnames

```
internet -> books.pointyspoon.com (A record at Hover) = WAN address
         -> UniFi port forward WAN 443 -> 192.168.1.201:9443
         -> Traefik public entrypoint (no allowlist), certificate books-tls by SNI -> Kavita
```

| Part | Where | Notes |
|:--|:--|:--|
| Ingress | `apps/media/kavita/ingress-public.yaml` | Entrypoints `websecure,public`. A separate Ingress so `kavita.home.pointyspoon.com` stays off the public entrypoint. |
| Certificate | `apps/core/traefik/certificate-books.yaml` | Lives in `traefik` and is listed in the `TLSStore`, so Traefik serves it by SNI. |
| Challenge | Hover, plus `clusterissuers.yaml` and the `acme-dns` Secret | `_acme-challenge.books.pointyspoon.com` CNAMEs to the same acme-dns account as `home`. The Secret's `acmedns.json` has a `books.pointyspoon.com` key with a copy of that account. |
| Port forward | UniFi controller | WAN TCP 443 to `192.168.1.201:9443`. Port 80 stays closed. |
| LAN DNS | AdGuard | Rewrite `books.pointyspoon.com` to `192.168.1.201`, so LAN clients go through websecure and do not depend on hairpin NAT. |

> **🔒 Security:** Anything on the public entrypoint is on the internet, guarded only by the app's own login. Keep Kavita updated, give every account a strong password, and do not attach admin tools (the *arr apps, NZBGet, Argo CD) to `public`.

> **⚠️ Warning:** The A record at Hover is static. If the ISP changes the WAN address, `books.pointyspoon.com` breaks until the record is updated.

To publish another app, repeat the same steps: a CNAME and a key in `acmedns.json` for its challenge, a `dnsNames` selector in both ClusterIssuers, a Certificate in `traefik` added to `tlsStore.default.certificates`, an Ingress with `router.entrypoints: websecure,public`, an A record and an AdGuard rewrite.

## Adding an app

1. Give its `Service` the type `ClusterIP`.
2. Add an `ingress.yaml` (copy one from `apps/media/sonarr/`), changing the host, Service name and port, and list it under `resources:`.
3. Nothing for DNS: the AdGuard rewrite `*.home.pointyspoon.com` already covers it.

No certificate work is needed: the wildcard covers it.

## When it breaks

| Symptom | Likely cause | Fix or workaround |
|:--|:--|:--|
| A hostname does not resolve (`NXDOMAIN`) | the AdGuard rewrite for `*.home.pointyspoon.com` is missing, or AdGuard cached a failure | `dig @192.168.1.2 <host>`; check Filters, DNS rewrites on the NAS; clear AdGuard's cache. `.lan` names come from the gateway instead (see the README). |
| Browser certificate warning | certificate expired or renewal failed | `kubectl describe certificate wildcard-home -n traefik`; check the CNAME still resolves with `dig CNAME _acme-challenge.home.pointyspoon.com` |
| `404` from Traefik | no route for that Host header | the Ingress is missing, or you used the bare IP |
| `403` from Traefik | client outside `192.168.0.0/16` | expected; this is the LAN-only middleware |
| `books.pointyspoon.com` times out from outside | port forward missing, or the WAN address changed | check the UniFi port forward and `dig +short books.pointyspoon.com` against the WAN address |
| `503` from Traefik | the Service has no ready pods | for example Mylar3 is parked |
| Argo CD UI via hostname gives `500` | Traefik is verifying Argo CD's internal certificate | the `ServersTransport` in `argocd/config/ingress.yaml` must say `insecureSkipVerify` |
| Everything by name is down | Traefik pod or the gateway/NAS DNS | use `https://192.168.1.202` for Argo CD, `http://192.168.1.203:32400/web` for Plex, or `kubectl port-forward` for anything |

## Behaviour to know about

- Sonarr and Radarr show their **login page** through the hostname, where the bare IP used to let you in. Their "disabled for local addresses" bypass does not apply behind a proxy.
- Sonarr and Radarr build redirects with `http://`; Traefik upgrades them to HTTPS with a 301, so it works, with one extra hop.
- Phone apps and bookmarks that used the old per-app IPs (`192.168.1.203` to `.207`) need the new hostnames.
