Plex 
====

Home media plex server configured with an NFS share.

## Getting started

Generate a claim token for your Plex account from https://www.plex.tv/claim and store it as a secret.

```
API_TOKEN_CLEAN=claim-pXeuoGzTHfq2ZQe2byFs
API_TOKEN_OPAQUE=$(echo -n ${API_TOKEN_CLEAN} | base64)

envsubst < plex-claim-token.yaml | kubectl apply -f -
```

Deploy plex
```
kubectl apply -f plex.yaml
```
