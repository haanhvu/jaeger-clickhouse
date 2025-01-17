GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
GOBUILD=CGO_ENABLED=0 installsuffix=cgo go build -trimpath

TOOLS_MOD_DIR = ./internal/tools
JAEGER_VERSION ?= 1.32.0

DOCKER_REPO ?= ghcr.io/jaegertracing/jaeger-clickhouse
DOCKER_TAG ?= latest

.PHONY: build
build:
	${GOBUILD} -o jaeger-clickhouse-$(GOOS)-$(GOARCH) ./cmd/jaeger-clickhouse/main.go

.PHONY: build-linux-amd64
build-linux-amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) build

.PHONY: build-linux-arm64
build-linux-arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) build

.PHONY: build-darwin-amd64
build-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(MAKE) build

.PHONY: build-darwin-arm64
build-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(MAKE) build

.PHONY: build-all-platforms
build-all-platforms: build-linux-amd64 build-linux-arm64 build-darwin-amd64 build-darwin-arm64

.PHONY: e2e-tests
e2e-tests:
	GOOS=linux GOARCH=amd64 $(MAKE) build
	E2E_TEST=true go test ./e2etests... -v

.PHONY: run
run:
	docker run --network host --name jaeger -e JAEGER_DISABLED=true -p 139.178.81.65:4317:4317 -p 139.178.81.65:14269:14269 -v "${PWD}:/data" -e SPAN_STORAGE_TYPE=grpc-plugin jaegertracing/jaeger-collector --collector.queue-size=100000 --collector.num-workers=100 --grpc-storage-plugin.binary=/data/jaeger-clickhouse-$(GOOS)-$(GOARCH) --grpc-storage-plugin.configuration-file=/data/config.yaml --grpc-storage-plugin.log-level=debug

.PHONY: run-hotrod
run-hotrod:
	docker run --rm --link jaeger --env JAEGER_AGENT_HOST=jaeger --env JAEGER_AGENT_PORT=6831 -p8080:8080 jaegertracing/example-hotrod:${JAEGER_VERSION} all

.PHONY: fmt
fmt:
	go fmt ./...
	goimports -w -local github.com/jaegertracing/jaeger-clickhouse ./

.PHONY: lint
lint:
	golangci-lint -v run --allow-parallel-runners ./...

.PHONY: test
test:
	go test ./...

.PHONY: integration-test
integration-test: build
	STORAGE=grpc-plugin \
	PLUGIN_BINARY_PATH=$(PWD)/jaeger-clickhouse-linux-amd64 \
	PLUGIN_CONFIG_PATH=$(PWD)/integration/config-local.yaml \
	go test ./integration

.PHONY: tar
tar:
	tar -czvf jaeger-clickhouse-$(GOOS)-$(GOARCH).tar.gz  jaeger-clickhouse-$(GOOS)-$(GOARCH) config.yaml

.PHONY: tar-linux-amd64
tar-linux-amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) tar

.PHONY: tar-linux-arm64
tar-linux-arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) tar

.PHONY: tar-darwin-amd64
tar-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(MAKE) tar

.PHONY: tar-darwin-arm64
tar-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(MAKE) tar

.PHONY: tar-all-platforms
tar-all-platforms: tar-linux-amd64 tar-linux-arm64 tar-darwin-amd64 tar-darwin-arm64

.PHONY: docker
docker: build
	docker build -t ${DOCKER_REPO}:${DOCKER_TAG} -f Dockerfile .

.PHONY: docker-push
docker-push: build
	docker push ${DOCKER_REPO}:${DOCKER_TAG}

.PHONY: install-tools
install-tools:
	cd $(TOOLS_MOD_DIR) && go install golang.org/x/tools/cmd/goimports
	cd $(TOOLS_MOD_DIR) && go install github.com/golangci/golangci-lint/cmd/golangci-lint

