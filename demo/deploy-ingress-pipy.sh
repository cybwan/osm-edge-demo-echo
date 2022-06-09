#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091
source .env
MESH_NAME="${MESH_NAME:-osm-edge}"
INGRESS_PIPY_NAMESPACE="${INGRESS_PIPY_NAMESPACE:-flomesh}"
PIPY_INGRESS_SERVICE=${PIPY_INGRESS_SERVICE:-ingress-pipy-controller}
ECHO_CONSUMER_NAMESPACE="${ECHO_CONSUMER_NAMESPACE:-echo-consumer}"

VERSION=${1:-v1}
SVC_ECHO_HTTP_CONSUMER="echo-http-consumer-$VERSION"
SVC_ECHO_GRPC_CONSUMER="echo-grpc-consumer-$VERSION"
SVC_ECHO_DUBBO_CONSUMER="echo-dubbo-consumer-$VERSION"

K8S_INGRESS_NODE="${K8S_INGRESS_NODE:-osm-worker}"

kubectl label node "$K8S_INGRESS_NODE" ingress-ready=true --overwrite=true

helm repo add fsm https://flomesh-io.github.io/fsm

helm install fsm fsm/fsm --namespace "$INGRESS_PIPY_NAMESPACE" --create-namespace
sleep 5

kubectl wait --namespace "$INGRESS_PIPY_NAMESPACE" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=ingress-pipy \
  --timeout=600s

kubectl patch deployment -n "$INGRESS_PIPY_NAMESPACE" ingress-pipy -p \
'{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "ingress",
            "ports": [
              {
                "containerPort": 8000,
                "hostPort": 80,
                "name": "ingress",
                "protocol": "TCP"
              }
            ]
          }
        ],
        "nodeSelector": {
          "ingress-ready": "true"
        }
      }
    }
  }
}'

kubectl wait --namespace "$INGRESS_PIPY_NAMESPACE" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=ingress-pipy \
  --timeout=600s

kubectl patch service -n "$INGRESS_PIPY_NAMESPACE" "$PIPY_INGRESS_SERVICE" -p '{"spec":{"type":"NodePort"}}'

osm namespace add "$INGRESS_PIPY_NAMESPACE" --mesh-name "$MESH_NAME" --disable-sidecar-injection

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pipy-echo-ingress
  namespace: $ECHO_CONSUMER_NAMESPACE
spec:
  ingressClassName: pipy
  rules:
  - http:
      paths:
      - path: /httpEcho
        pathType: Prefix
        backend:
          service:
            name: $SVC_ECHO_HTTP_CONSUMER
            port:
              number: 8090
      - path: /grpcEcho
        pathType: Prefix
        backend:
          service:
            name: $SVC_ECHO_GRPC_CONSUMER
            port:
              number: 8090
      - path: /dubboEcho
        pathType: Prefix
        backend:
          service:
            name: $SVC_ECHO_DUBBO_CONSUMER
            port:
              number: 8090
---
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: pipy-echo-ingress-backend
  namespace: $ECHO_CONSUMER_NAMESPACE
spec:
  backends:
  - name: $SVC_ECHO_HTTP_CONSUMER
    port:
      number: 8090
      protocol: http
  - name: $SVC_ECHO_GRPC_CONSUMER
    port:
      number: 8090
      protocol: http
  - name: $SVC_ECHO_DUBBO_CONSUMER
    port:
      number: 8090
      protocol: http
  sources:
  - kind: Service
    namespace: "$INGRESS_PIPY_NAMESPACE"
    name: "$PIPY_INGRESS_SERVICE"
EOF
