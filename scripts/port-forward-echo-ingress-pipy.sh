#!/bin/bash

# shellcheck disable=SC1091
source .env

LOCAL_PORT="${LOCAL_PORT:-80}"
INGRESS_PIPY_NAMESPACE="${INGRESS_PIPY_NAMESPACE:-flomesh}"
PIPY_INGRESS_SERVICE=${PIPY_INGRESS_SERVICE:-ingress-pipy-controller}
ECHO_CONSUMER_NAMESPACE="${ECHO_CONSUMER_NAMESPACE:-echo-consumer}"

PIPY_INGRESS_PORT="$(kubectl -n "$INGRESS_PIPY_NAMESPACE" get service "$PIPY_INGRESS_SERVICE" -o jsonpath='{.spec.ports[?(@.name=="http")].port}')"

kubectl describe ingress -n "$ECHO_CONSUMER_NAMESPACE" pipy-echo-ingress

kubectl port-forward --address 0.0.0.0 -n $INGRESS_PIPY_NAMESPACE service/$PIPY_INGRESS_SERVICE "$LOCAL_PORT":"$PIPY_INGRESS_PORT"
