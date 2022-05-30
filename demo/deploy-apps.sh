#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091
source .env

DEPLOY_WITH_SAME_SA="${DEPLOY_WITH_SAME_SA:-false}"

# Deploy apps in the order of their dependencies to avoid initial timing errors
# in osm-controller logs. Server apps are deployed before client apps.

# Deploy bookwarehouse
#./demo/deploy-bookwarehouse.sh

# Deploy MySQL
#./demo/deploy-mysql.sh

# Deploy bookstore versions
if [ "$DEPLOY_WITH_SAME_SA" = "true" ]; then
    ./demo/deploy-bookstore-with-same-sa.sh "v1"
else
    ./demo/deploy-echo-grpc-server.sh "v1"
fi

# Deploy bookstore versions
if [ "$DEPLOY_WITH_SAME_SA" = "true" ]; then
    ./demo/deploy-bookstore-with-same-sa.sh "v1"
else
    ./demo/deploy-echo-dubbo-server.sh "v1"
fi

# Deploy bookbuyer
./demo/deploy-echo-consume.sh "v1"
