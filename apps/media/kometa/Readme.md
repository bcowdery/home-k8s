Kometa
======

[Kometa](https://kometa.wiki) runs nightly at 03:00 against the Plex **Movies** and **TV Shows** libraries. It:

- sets US content ratings from OMDb, genres from TMDb, and IMDb Parental Guide labels such as `Frightening:Moderate` (Moderate and Severe only),
- builds the `universe` and `franchise` default collections,
- applies the `kids` label that the kids managed account is restricted to (`config/kids.yml`).

It has no web UI. The design is in [docs/plans/2026-10-27-kometa-kids-profile-design.md](../../../docs/plans/2026-10-27-kometa-kids-profile-design.md).

## The `kids` label

An item gets `kids` when it is rated `G`, `TV-Y` or `TV-G` and has no Moderate or Severe parental label. Kometa removes the label from anything that stops matching.

Two labels can be set by hand in Plex to override the rule:

| Label | Effect |
|:--|:--|
| `kids-allow` | Gets `kids` whatever its rating or parental labels. For titles rated `Approved`, `Not Rated` or wrongly. |
| `kids-block` | Never gets `kids`. Wins over `kids-allow`. |

Overrides take effect on the next run.

> **📌 Important:** A title with no IMDb parental guide has no severity labels, so it passes on its rating alone. Titles with no rating never get `kids`.

## Plex profile setup

The managed account uses restriction profile **None**, with Movies and TV Shows set to allow only the label `kids`. Do not use the *Younger Kid* preset, which filters on rating only, and do not add a rating cap, which would block `kids-allow` titles.

## Secrets

`secrets-sealed.yaml` holds `KOMETA_MYPLEX_TOKEN`, `KOMETA_TMDB_KEY` and `KOMETA_OMDB_KEY`. Kometa substitutes them into the `<<MYPLEX_TOKEN>>`, `<<TMDB_KEY>>` and `<<OMDB_KEY>>` placeholders in `config/config.yml`. To change one, reseal all three. The token is deliberately not named `KOMETA_PLEX_TOKEN`: Kometa reserves that name and does not substitute it into the config.

```
kubectl -n media create secret generic kometa-secrets --dry-run=client -o yaml \
  --from-literal=KOMETA_MYPLEX_TOKEN=... \
  --from-literal=KOMETA_TMDB_KEY=... \
  --from-literal=KOMETA_OMDB_KEY=... \
| kubeseal --controller-namespace kube-system --controller-name sealed-secrets-controller --format yaml \
  > apps/media/kometa/secrets-sealed.yaml
```

> **🧠 Pro-tip:** The Plex token is `PlexOnlineToken` in `/config/Library/Application Support/Plex Media Server/Preferences.xml` inside the Plex pod.

## Running it

Start a run without waiting for 03:00, then follow the log:

```
kubectl -n media create job --from=cronjob/kometa kometa-manual-$(date +%s)
kubectl -n media logs -f job/<name>
```

The config files are copied from the ConfigMap onto the `kometa-data` volume at the start of every run, because Kometa rewrites `config.yml` in place. Edits made on the volume are lost; change the files in `config/` instead. The volume also holds the lookup cache and `logs/`.

> **💡 Note:** OMDb's free key allows 1,000 requests a day. The cache keeps results for 60 days, so after the first pass only new titles use the quota.
