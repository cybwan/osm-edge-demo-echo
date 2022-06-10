#!/bin/bash

# shellcheck disable=SC1091
source .env

permissiveMode=$1

K8S_NAMESPACE="${K8S_NAMESPACE:-osm-edge-system}"

kubectl patch meshconfig osm-mesh-config -n "$K8S_NAMESPACE" \
  -p "{\"spec\":{\"traffic\":{\"enablePermissiveTrafficPolicyMode\":$permissiveMode}}}" \
  --type=merge
