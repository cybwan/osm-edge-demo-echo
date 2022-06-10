#!/bin/bash

# shellcheck disable=SC1091
source .env

memory=$1

K8S_NAMESPACE="${K8S_NAMESPACE:-osm-edge-system}"

kubectl patch meshconfig osm-mesh-config -n "$K8S_NAMESPACE" \
  -p "{\"spec\":{\"sidecar\":{\"resources\":{\"limits\":{\"memory\":\"$memory\"}}}}}" \
  --type=merge
