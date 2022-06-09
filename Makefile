#!make

TARGETS      := darwin/amd64 darwin/arm64 linux/amd64 linux/arm64
BINNAME      ?= osm
DIST_DIRS    := find * -type d -exec
CTR_REGISTRY ?= cybwan
CTR_TAG      ?= latest
VERIFY_TAGS  ?= false

GOPATH = $(shell go env GOPATH)
GOBIN  = $(GOPATH)/bin
GOX    = go run github.com/mitchellh/gox
SHA256 = sha256sum
ifeq ($(shell uname),Darwin)
	SHA256 = shasum -a 256
endif

DOCKER_GO_VERSION = 1.17
DOCKER_BUILDX_PLATFORM ?= linux/amd64

VERSION ?= v0.0.4
ROOT := github.com/cybwan/osm-edge-demo
ARCH  ?= $(shell go env GOARCH)
BUILD_DATE = $(shell date +'%Y-%m-%dT%H:%M:%SZ')
COMMIT = $(shell git rev-parse --short HEAD)
GOENV  := CGO_ENABLED=0 GOOS=$(shell uname -s | tr A-Z a-z) GOARCH=$(ARCH) GOPROXY=https://goproxy.cn,direct
LDFLAGS ?= -ldflags "-s -w -X $(ROOT)/pkg/version.Release=$(VERSION) -X  $(ROOT)/pkg/version.Commit=$(COMMIT) -X  $(ROOT)/pkg/version.BuildDate=$(BUILD_DATE)"
DOCKER_BUILDX_OUTPUT ?= type=registry

check-env:
ifndef CTR_REGISTRY
	$(error CTR_REGISTRY environment variable is not defined; see the .env.example file for more information; then source .env)
endif
ifndef CTR_TAG
	$(error CTR_TAG environment variable is not defined; see the .env.example file for more information; then source .env)
endif

.PHONY: proto
proto:
	protoc --proto_path=pkg/api/echo --go_out=pkg/api/echo --go-grpc_out=pkg/api/echo echo.proto

.PHONY: go-checks
go-checks: go-lint go-fmt go-mod-tidy

.PHONY: go-vet
go-vet:
	go vet ./...

.PHONY: go-lint
go-lint: embed-files-test
	docker run --rm -v $$(pwd):/app -w /app golangci/golangci-lint:latest golangci-lint run --config .golangci.yml

.PHONY: go-fmt
go-fmt:
	go fmt ./...

.PHONY: go-mod-tidy
go-mod-tidy:
	go mod tidy

.PHONY: kind-up
kind-up:
	./scripts/kind-with-registry.sh

.PHONY: kind-reset
kind-reset:
	kind delete cluster --name osm

build-echo-dubbo-consumer:
	rm -rf bin/echo-dubbo-consumer
	go build -v -o bin/echo-dubbo-consumer ${LDFLAGS} demo/cmd/echo-dubbo-consumer/main.go

build-echo-grpc-consumer:
	rm -rf bin/echo-grpc-consumer
	go build -v -o bin/echo-grpc-consumer ${LDFLAGS} demo/cmd/echo-grpc-consumer/main.go

build-echo-http-consumer:
	rm -rf bin/echo-http-consumer
	go build -v -o bin/echo-http-consumer ${LDFLAGS} demo/cmd/echo-http-consumer/main.go

build-echo-dubbo-server:
	rm -rf bin/echo-dubbo-server
	go build -v -o bin/echo-dubbo-server ${LDFLAGS} demo/cmd/echo-dubbo-server/main.go

build-echo-grpc-server:
	rm -rf bin/echo-dubbo-server
	go build -v -o bin/echo-grpc-server ${LDFLAGS} demo/cmd/echo-grpc-server/main.go

build-echo-http-server:
	rm -rf bin/echo-http-server
	go build -v -o bin/echo-http-server ${LDFLAGS} demo/cmd/echo-http-server/main.go

build-cli: build-echo-grpc-server build-echo-dubbo-server build-echo-http-server build-echo-dubbo-consumer build-echo-grpc-consumer  build-echo-http-consumer

run-echo-dubbo-consumer: build-echo-dubbo-consumer
	CONF_CONSUMER_FILE_PATH=${PWD}/misc/echo-dubbo-consumer/client.yml \
	APP_LOG_CONF_FILE=${PWD}/misc/echo-dubbo-consumer/log.yml \
	bin/echo-dubbo-consumer

run-echo-grpc-consumer: build-echo-grpc-consumer
	bin/echo-grpc-consumer grpc-server=127.0.0.1:20001

run-echo-http-consumer: build-echo-http-consumer
	bin/echo-http-consumer http-server=127.0.0.1:20003

run-echo-dubbo-server: build-echo-dubbo-server
	CONF_PROVIDER_FILE_PATH=${PWD}/misc/echo-dubbo-server/server.yml \
	APP_LOG_CONF_FILE=${PWD}/misc/echo-dubbo-server/log.yml \
	bin/echo-dubbo-server

run-echo-grpc-server: build-echo-grpc-server
	bin/echo-grpc-server grpc-port=20001

run-echo-http-server: build-echo-http-server
	bin/echo-http-server http-port=20003

.env:
	cp .env.example .env

.PHONY: kind-demo
kind-demo: export CTR_REGISTRY=localhost:5000
kind-demo: .env kind-up
	./demo/run-osm-demo.sh

.PHONY: docker-build-echo-base
docker-build-echo-base: DOCKER_BUILDX_PLATFORM=linux/amd64,linux/arm64
docker-build-echo-base:
	docker buildx build --builder osm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) -t $(CTR_REGISTRY)/osm-edge-echo-base:latest -f dockerfiles/Dockerfile.base .

DEMO_TARGETS = echo-dubbo-consumer echo-grpc-consumer echo-http-consumer echo-dubbo-server echo-grpc-server echo-http-server
# docker-build-echo-consumer, etc
DOCKER_DEMO_TARGETS = $(addprefix docker-build-, $(DEMO_TARGETS))
.PHONY: $(DOCKER_DEMO_TARGETS)
$(DOCKER_DEMO_TARGETS): NAME=$(@:docker-build-%=%)
$(DOCKER_DEMO_TARGETS):
	docker buildx build --builder osm --platform=$(DOCKER_BUILDX_PLATFORM) -o $(DOCKER_BUILDX_OUTPUT) -t $(CTR_REGISTRY)/osm-edge-demo-$(NAME):$(CTR_TAG) -f dockerfiles/Dockerfile.$(NAME) --build-arg GO_VERSION=$(DOCKER_GO_VERSION) .

.PHONY: docker-build-demo
docker-build-demo: $(DOCKER_DEMO_TARGETS)

.PHONY: buildx-context
buildx-context:
	@if ! docker buildx ls | grep -q "^osm "; then docker buildx create --name osm --driver-opt network=host; fi

check-image-exists-%: NAME=$(@:check-image-exists-%=%)
check-image-exists-%:
	@if [ "$(VERIFY_TAGS)" = "true" ]; then scripts/image-exists.sh $(CTR_REGISTRY)/$(NAME):$(CTR_TAG); fi

$(foreach target,$(DEMO_TARGETS),$(eval docker-build-$(target): check-image-exists-$(target) buildx-context))

docker-digest-%: NAME=$(@:docker-digest-%=%)
docker-digest-%:
	@docker buildx imagetools inspect $(CTR_REGISTRY)/$(NAME):$(CTR_TAG) --raw | $(SHA256) | awk '{print "$(NAME): sha256:"$$1}'

.PHONY: docker-digests-demo
docker-digests: $(addprefix docker-digest-, $(DEMO_TARGETS))

.PHONY: docker-build
docker-build: docker-build-demo

.PHONY: docker-build-cross-demo docker-build-cross
docker-build-cross-demo: DOCKER_BUILDX_PLATFORM=linux/amd64,linux/arm64
docker-build-cross-demo: docker-build-demo
docker-build-cross: go-mod-tidy docker-build-cross-demo
