#!/bin/bash

## 
## System
## 

# MetalLb config 
kubectl apply -f root/metallb/bgppeer.yaml

##
## MEDIA
##

# Shared resources
kubectl apply -f media/namespace.yaml
kubectl apply -f media/volumes.yaml

## Plex
kubectl apply -f media/plex/plex-claim-token.yaml
kubectl apply -f media/plex/plex.yaml

# Usenet Dowload tools
kubectl apply -f media/nzbget/nzbget.yaml
kubectl apply -f media/sonarr/sonarr.yaml