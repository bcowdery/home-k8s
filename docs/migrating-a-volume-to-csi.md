# Migrating an app's config volume from a hand-made LUN to synology-csi

Proven on Kavita (2026-10-12): 235 files, 54 MB, checksum-verified identical.

The old LUN is only ever mounted read-only, so it stays intact as the fallback.

## Before you start

- The app must be scaled to **0 in git** (`replicas: 0`). Argo CD's self-heal reverts `kubectl scale`.
- The target PVC must exist, bound and empty. Add it to the app's directory (`pvc.yaml`, listed in its `kustomization.yaml`) with `storageClassName: synology-csi-iscsi-retain`.
- Do not edit or rename any CSI LUN in the DSM UI. See the warning in the design doc.

## Steps

1. Commit `replicas: 0` and wait for the pod to go away.
2. Start the copy pod (not in git). Replace the IQN and the claim name:

   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: migrate
     namespace: media
   spec:
     restartPolicy: Never
     containers:
       - name: m
         image: alpine:3.20
         command: ["sleep", "3600"]
         volumeMounts:
           - { name: old, mountPath: /old, readOnly: true }
           - { name: new, mountPath: /new }
     volumes:
       - name: old
         iscsi:
           targetPortal: "192.168.1.2"
           iqn: "<old target iqn>"
           lun: 1
           fsType: ext4
           readOnly: true
       - name: new
         persistentVolumeClaim:
           claimName: <new pvc>
   ```

3. Look first: `df -h /old /new; du -sh /old`. The old side must show `ro`.
4. Copy: `apk add --no-cache rsync && rsync -aHAX --exclude=lost+found --stats /old/ /new/`
5. Verify. An empty list means identical: `rsync -aHAXnc --itemize-changes --exclude=lost+found /old/ /new/`
6. Delete the pod. Switch the app's volume from the inline `iscsi:` block to `persistentVolumeClaim`, set `replicas: 1`, commit and push.
7. Check the app serves, `touch /config/.rwtest` works inside the pod, and its database loaded.

## Gotchas

- **Add a `startupProbe`.** A restarted app may upgrade its database before it listens. Liveness kills a container that is still starting (exit 137), which risks interrupting the upgrade. Kavita needed about 80 s. Plex already has one.
- **`latest` image tags move.** The first restart can pull a newer version and migrate the data. That is a separate change from the volume move; pin tags if you want to do them one at a time.
- **Rollback:** scale to 0, put the inline `iscsi:` block back, scale to 1. The old LUN was never written to.
- Delete the old LUN and target in DSM only after the app has run happily for a while.
