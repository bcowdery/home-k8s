# Kometa metadata enrichment and a kids profile

Date: 2026-10-27

## Goals

1. Fill in metadata the Plex scanner misses, mainly US content ratings, across the Movies and TV Shows libraries.
2. Add universe and franchise collections.
3. Give a Plex managed account for a child aged 6 or under a library limited to suitable titles, without hand-curating it.

## Starting point

- Plex runs in the `media` namespace (`apps/media/plex/`) and is reachable in-cluster at `plex-tcp.media.svc.cluster.local:32400`.
- Content ratings are missing on most items, so Plex's own age restrictions have nothing to filter on.
- Posters, backgrounds and other artwork from the Plex scanner are fine.
- Secrets are Sealed Secrets. The repo is public, so only ciphertext is committed.

## Decisions

| Topic | Decision |
|:--|:--|
| Tool | [Kometa](https://kometa.wiki), image `kometateam/kometa`, version pinned. |
| Workload | A CronJob in `apps/media/kometa/`, nightly at about 03:00, `--run`. No web UI, no ingress. |
| Config | `config.yml` and `kids.yml` in a ConfigMap, so rule changes are commits. |
| Secrets | Plex token, TMDb key and OMDb key in one SealedSecret. Kometa will not start without a TMDb key. |
| Cache | A small PVC for Kometa's SQLite cache. Without it every run spends the OMDb quota on items it has already looked up. |
| Plex address | The in-cluster Service, which avoids Traefik and the LAN allowlist. |
| Content rating | `mass_content_rating_update: omdb` (US ratings from IMDb certifications). Free tier is 1,000 requests a day, so the first pass takes several nights. |
| Genre | `mass_genre_update: tmdb`. |
| Parental labels | `mass_imdb_parental_labels: moderate`. Writes `Category:Level` labels such as `Frightening:Moderate` for Moderate and Severe only. |
| Collections | `universe` and `franchise` defaults on both libraries. |
| Overlays | None. They repeat data Plex already shows. A ribbon overlay may be revisited later. |
| Artwork | No `mass_poster_update` or `mass_background_update`. Plex art is fine, and these lock the fields against later Plex updates. |
| Kids filter | A `kids` label applied by Kometa. The Plex profile allows only that label. |

## The `kids` rule

A collection in `kids.yml` with `build_collection: false`, so it labels items without creating a collection in Plex. An item gets the `kids` label when:

- its content rating is `G`, `TV-Y` or `TV-G`, **and**
- it has none of the ten `Moderate` or `Severe` parental labels (`Nudity`, `Violence`, `Profanity`, `Alcohol`, `Frightening`), **and**
- it does not carry the manual `kids-block` label.

An item with the manual `kids-allow` label gets `kids` regardless of rating, unless it also has `kids-block`. This is for titles whose rating is wrong, such as older films rated `Approved` or `Not Rated`.

`non_item_remove_label: kids` removes the label from anything that stops matching.

The three ratings are the same set Plex's built-in *Younger Kid* restriction profile allows.

> **💡 Note:** Kometa's default run order is operations, then collections, so each run fills in ratings and parental labels before the `kids` rule reads them. Confirm this during implementation.

> **⚠️ Warning:** A title with no IMDb parental guide gets no severity labels, so the veto cannot catch it and it passes on rating alone. Unrated titles still never get `kids`.

## Failure modes

Each one fails closed: the kids profile never sees more than it should.

| Failure | Effect |
|:--|:--|
| OMDb quota exhausted | Remaining items stay unrated and unlabelled. The next run continues. |
| Plex or IMDb unreachable | The job fails and the next night retries. |
| Plex metadata refresh | Kometa locks the fields it edits, so the refresh does not revert them. |
| Hung run | `concurrencyPolicy: Forbid`, `backoffLimit: 0` and `activeDeadlineSeconds` of about 6 hours. |

## Plex profile setup (manual)

1. Plex Home, **Create Managed Account**.
2. Restriction profile **None**, not *Younger Kid*. The preset filters on rating only, so it has no parental veto and ignores the override labels.
3. Allow only items with the label `kids`. Do not also set a rating cap, because it would block `kids-allow` titles.

## Testing

1. Seal the secrets, let Argo CD sync, then start a run with `kubectl -n media create job --from=cronjob/kometa kometa-manual`.
2. Check the log for authentication errors and the operation summaries.
3. Spot-check in Plex. A known kids title (Bluey, Toy Story) has `kids`. *The Lion King* has `Frightening:Moderate` and no `kids`. An adult title has no `kids`.
4. Filter each library by the `kids` label and review the list.
5. Sign in as the managed account and browse it before handing it over.

## Deliverables

- `apps/media/kometa/`: CronJob, ConfigMap (`config.yml`, `kids.yml`), PVC, SealedSecret, kustomization.
- `apps/media/kometa/Readme.md`: secrets, override labels and the Plex profile setup.
- A Kometa row in the root `Readme.md` app table.
