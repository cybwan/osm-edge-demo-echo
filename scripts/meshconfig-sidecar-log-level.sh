#!/bin/bash

# shellcheck disable=SC1091
source .env

logLevel=$1

K8S_NAMESPACE="${K8S_NAMESPACE:-osm-edge-system}"

kubectl patch meshconfig osm-mesh-config -n "$K8S_NAMESPACE" \
  -p "{\"spec\":{\"sidecar\":{\"logLevel\":\"$logLevel\"}}}" \
  --type=merge
