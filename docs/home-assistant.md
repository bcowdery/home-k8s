# Home Assistant, Whisper, Piper and Claude

Built 2026-10-13. Phase 1 of the smart home: the voice assistant. Presence, switches and solar come later.

## What runs

| Part | Where | Notes |
|:--|:--|:--|
| Home Assistant 2026.10.1 | `apps/home/home-assistant/` | **Host network**, not privileged. `https://ha.home.pointyspoon.com` through Traefik, or `http://192.168.1.4:8123` directly. Config on a 10Gi CSI volume. |
| Whisper 3.8.1 | `apps/home/whisper/` | Speech to text on the CPU: `small.en`, int8, beam size 1. About 1.5 s per utterance. Service `whisper`, port 10300. |
| Piper 2.5.2 | `apps/home/piper/` | Text to speech, voice `en_US-lessac-medium`. Service `piper`, port 10200. |
| Claude | Home Assistant's **Anthropic** integration | Entered in the UI. The API key is stored on the Home Assistant config volume, not in git. |

Everything is in the Argo CD project `home`, namespace `home-assistant`.

## Why the host network

Device discovery (mDNS, SSDP, DHCP) is broadcast based and does not cross the pod network. Two consequences, both handled in the manifests:

- `dnsPolicy: ClusterFirstWithHostNet`, otherwise a host-network pod cannot resolve `whisper.home-assistant.svc.cluster.local`.
- `configuration.yaml` (a ConfigMap in git) trusts the pod network (`10.1.0.0/16`) as a reverse proxy. Without `use_x_forwarded_for` and `trusted_proxies`, Home Assistant answers everything that arrives through Traefik with a 400.

## First-time setup (in the Home Assistant UI)

1. Open `https://ha.home.pointyspoon.com` (or `http://192.168.1.4:8123` if DNS is not set up yet) and create the owner account.
2. **Wyoming Protocol**, added twice (Settings, Devices & services, Add integration):
   - host `whisper.home-assistant.svc.cluster.local`, port `10300`
   - host `piper.home-assistant.svc.cluster.local`, port `10200`
3. **Anthropic**: paste the API key. Start with *Recommended settings*, then try `claude-haiku-5-5`.
4. **Settings, Voice assistants, Add assistant**: conversation agent = the Anthropic one, speech-to-text = faster-whisper, text-to-speech = piper, language English. Turn on *Prefer handling commands locally* so simple commands never reach Claude.
5. **Settings, Voice assistants, Expose**: expose only the entities Claude should see or control.
6. **Settings, System, Network**: set the internal and external URL to `https://ha.home.pointyspoon.com`. The mobile app wants a trusted HTTPS address.

## Claude notes

- **Model**: Claude Haiku 5.5 is fast and cheap (about $0.10 per million input tokens), which suits voice. Sonnet 5.5 reasons better at about 20 times the price. A voice turn is a few thousand tokens, so even Sonnet is around a cent.
- **Home Assistant lags new models.** Its docs say a brand-new model can take up to two releases to be fully supported. If a model errors, fall back to *Recommended settings* and bump `home-assistant` in git.
- **Sampling**: Haiku 5.5 rejects non-default `temperature`. If it returns a 400, put temperature back to the default. Newer models use *Thinking effort* instead of a thinking budget; keep it low for voice.
- **Privacy**: audio stays local (Whisper and Piper). The *text* of what you say, plus the state of exposed entities, goes to Anthropic.
- **Set a spend limit** on the API key's workspace in the Anthropic Console.

## Operating it

- **Upgrade**: change the image tag in `apps/home/home-assistant/home-assistant.yaml` and push. Read the Home Assistant release notes first; the config volume has no automatic rollback.
- **Back up** the `home-assistant-data` volume (it holds the API key and all history). Add it to Hyper Backup. Home Assistant's own backups also land on that same volume, so they are not an off-box copy.
- **Change the Whisper model**: edit `--model` in `whisper.yaml`. The new model downloads on the next start.
- **First start is slow**: a new 10Gi CSI volume is formatted on its first mount. Three at once took about 4 minutes. During that time the kubelet logs `FailedMount ... apparently in use by the system`; that is a second `mkfs` colliding with the first, still running. It resolves itself once the first finishes.

## Troubleshooting

| Symptom | Likely cause |
|:--|:--|
| `400 Bad Request` from the hostname, fine on `:8123` | `trusted_proxies` does not include Traefik's pod address; check the ConfigMap |
| Wyoming integration cannot connect | `dnsPolicy` lost `ClusterFirstWithHostNet`; test with `kubectl exec -it deploy/home-assistant -- python3` and `socket.gethostbyname` |
| Pod stuck `ContainerCreating` on first deploy | the volume is still formatting; wait, see above |
| Voice works but is slow | check Whisper's CPU (`kubectl top pod -n home-assistant`); `base.en` is faster, less accurate |

## Still to do

| Phase | Plan |
|:--|:--|
| Presence | Home Assistant's UniFi Network integration. Phones must turn off *private Wi-Fi address* for the home network, and 802.11r fast roaming can cause stuck "home" states. |
| Switches | Inovelli (Zigbee) with ZHA over a **network (PoE) coordinator** placed centrally, so no USB stick is needed in the cluster; Shelly (Wi-Fi) added by IP. Devices on VLAN 30 are reachable by IP without discovery. |
| Solar | AP Systems. Home Assistant's built-in integration supports only the **EZ1** microinverter (local API). Other models need the cloud API through a community integration. |
