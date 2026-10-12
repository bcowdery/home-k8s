# Upgrading core components (MetalLB, NFD, Intel device plugins, ...)

Worked through on 2026-10-12: NFD 0.12.1 to 0.19.0, Intel 0.28.0 to 0.37.1, MetalLB v0.13.5 to v0.16.0.
Each was its own commit, so any step is a `git revert`.

## Method

1. **Look up what is available** (`helm search repo <chart> -l`, `gh api repos/<org>/<repo>/releases`) and read the release notes for breaking changes. Do not trust values that "still render": Helm silently ignores values that no longer exist.
2. **Render the new version** with the current values and diff it against what is running.
3. **Dry-run against the live cluster, apply nothing:** `kubectl apply --server-side --force-conflicts --dry-run=server -f render.yaml`. This is what catches immutable selectors and conflicting field types.
4. **Record a baseline** of whatever the component is responsible for (node labels, `allocatable` resources, reachable LoadBalancer IPs).
5. Push, refresh the Application, **watch it converge**, and compare against the baseline.

## Gotchas we hit

- **Helm hooks become plain resources.** NFD's chart ships a `post-delete` Job that runs `nfd-master -prune`, which strips NFD's labels from the nodes. Rendered through kustomize it is just a Job, so delete it (and its RBAC) with a `$patch: delete`. Always grep a new render for `helm.sh/hook`.
- **Argo CD dry-runs every object before applying any.** A custom resource that uses a field the *old* CRD does not declare fails the whole sync, even though the CRD is in the same sync. Apply the new CRDs by hand first (`kubectl apply --server-side --force-conflicts` on just the CRDs), then push.
- **Server-side apply merges instead of replacing.** Fields written by Helm (a different field manager) survive. Two real cases:
  - NFD master changed its probes from `exec` to `httpGet`: both handlers end up in the merged object, which Kubernetes rejects. Delete the live Deployment once so it is recreated cleanly.
  - The Intel operator chart dropped its `kube-rbac-proxy` sidecar, but the live Deployment kept it, and it fought the new manager for port 8443. Remove the stale container with a JSON patch.
  Check the *merged* result of the dry-run (`-o json`), not just whether it succeeded.
- **Argo CD does not track CRDs**, so prune never deletes a CRD that a new chart version drops. Delete those by hand, after confirming they have no objects.
- **Resources can be renamed upstream.** The Intel plugin's `gpu.intel.com/i915_monitoring` became `gpu.intel.com/monitoring`. Plex uses `gpu.intel.com/i915`, which did not change.
- **LoadBalancer IPs drop for about 15 to 30 seconds per MetalLB hop** while the speaker restarts. Nothing else is affected, but in-flight Plex streams end.
- **The MetalLB speaker still holds a stale `METALLB_ML_SECRET_KEY` env var** next to the new `METALLB_ML_SECRET_KEY_PATH`. Both reference the same secret. It disappears the next time the DaemonSet is recreated.

## Still outstanding

- cert-manager is on v1.13.3. Its only job is the Intel operator's webhook certificate, which works, but v1.13 supports Kubernetes 1.25 to 1.28 and the cluster is on 1.33.
- The Plex Services still use the deprecated `metallb.universe.tf/allow-shared-ip` annotation. It works, and `metallb.io/allow-shared-ip` is the replacement.
