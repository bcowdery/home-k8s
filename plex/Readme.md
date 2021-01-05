
```
# Get your claim token from https://www.plex.tv/claim

API_TOKEN_CLEAN=claim-pXeuoGzTHfq2ZQe2byFs
API_TOKEN_OPAQUE=$(echo -n ${API_TOKEN_CLEAN} | base64)

tee plex-claim.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: plex-claim-token
  namespace: home-media
type: Opaque
data:
  token: ${API_TOKEN_OPAQUE}
EOF

kubectl apply -f plex-claim.yaml
```
