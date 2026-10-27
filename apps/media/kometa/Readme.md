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

Overrides take effect on the next run. Case does not matter: Plex capitalises labels on save (`kids-allow` becomes `Kids-allow`), and `config/kids.yml` is written to cope with that.

> **📌 Important:** A title with no IMDb parental guide has no severity labels, so it passes on its rating alone. Titles with no rating never get `kids`.

## Plex profile setup

The managed account uses restriction profile **None**, with Movies and TV Shows set to allow only the label `kids`. Do not use the *Younger Kid* preset, which filters on rating only, and do not add a rating cap, which would block `kids-allow` titles.

## Secrets

`secrets-sealed.yaml` holds `KOMETA_MYPLEX_TOKEN`, `KOMETA_TMDB_KEY`, `KOMETA_OMDB_KEY` and `KOMETA_MDBLIST_KEY`. Kometa substitutes them into the matching `<<MYPLEX_TOKEN>>`, `<<TMDB_KEY>>`, `<<OMDB_KEY>>` and `<<MDBLIST_KEY>>` placeholders in `config/config.yml`. To change one, reseal all four. The token is deliberately not named `KOMETA_PLEX_TOKEN`: Kometa reserves that name and does not substitute it into the config.

```
kubectl -n media create secret generic kometa-secrets --dry-run=client -o yaml \
  --from-literal=KOMETA_MYPLEX_TOKEN=... \
  --from-literal=KOMETA_TMDB_KEY=... \
  --from-literal=KOMETA_OMDB_KEY=... \
  --from-literal=KOMETA_MDBLIST_KEY=... \
| kubeseal --controller-namespace kube-system --controller-name sealed-secrets-controller --format yaml \
  > apps/media/kometa/secrets-sealed.yaml
```

> **💥 DANGER:** Never give Kometa the server's `PlexOnlineToken` from `Preferences.xml`, or any token that belongs to another device. Kometa signs in to plex.tv with `X-Plex-Provides: sync`, and plex.tv rewrites the record of whichever device owns the token. With the server's token that turned the server into a `sync` device after every run, and it vanished from Plex Web until Plex was restarted.

The token must belong to Kometa's own client identifier, which Kometa keeps in `/config/UUID` on the `kometa-data` volume. Create one with a PIN login under that identifier:

1. `POST https://plex.tv/api/v2/pins?strong=true` with headers `X-Plex-Client-Identifier: <UUID>` and `X-Plex-Product: Kometa`. Note the `id` and `code` in the reply.
2. Open `https://app.plex.tv/auth#?clientID=<UUID>&code=<code>` and approve it as the Plex admin account.
3. `GET https://plex.tv/api/v2/pins/<id>?code=<code>` with the same client identifier header. `authToken` is the token. It appears under the account's authorized devices as Kometa.

## Running it

Start a run without waiting for 03:00, then follow the log:

```
kubectl -n media create job --from=cronjob/kometa kometa-manual-$(date +%s)
kubectl -n media logs -f job/<name>
```

The config files are copied from the ConfigMap onto the `kometa-data` volume at the start of every run, because Kometa rewrites `config.yml` in place. Edits made on the volume are lost; change the files in `config/` instead. The volume also holds the lookup cache and `logs/`.

> **💡 Note:** OMDb's free key allows 1,000 requests a day. The cache keeps results for 60 days, so after the first pass only new titles use the quota.
