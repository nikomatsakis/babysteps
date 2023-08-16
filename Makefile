# Required header
include $(shell bash .mkdkr init)

define build_hugo =
	mkdir -p bin
	[ -z "$(FORCE_BUILD)" ] || [ ! -f "bin/hugo" ]
	@$(dkr)
	instance: golang:alpine
	run: apk add gcc clang g++ gcompat musl-dev
	run: CGO_ENABLED=1 go install -tags extended github.com/gohugoio/hugo@latest
	run: hugo version
	pull: /go/bin/hugo bin/hugo
endef

define container_hugo =
	@$(dkr)
	dind: docker:latest
	retry: 3 10 docker build --rm -t hugo:latest -f Dockerfile.amd64 bin/
	var-run: TAG docker run --rm -i hugo:latest
	run: docker tag hugo:latest hugo:`echo "$$TAG" | awk '{ print $$2 }' | sed 's:\+.*::'`
endef

define update_hugo =
	$(build_hugo)
	$(container_hugo)
endef

hugo: bin/container.sh
	[ -z "$(FORCE_BUILD)" ] || \
		( rm bin/* && make hugo FORCE_BUILD=$(FORCE_BUILD) )
	docker run --rm -i hugo:latest

bin/container.sh: bin/hugo
	mkdir -p .tmp/bin
	$(container_hugo)
	cp container.sh bin/container.sh
	chmod +x bin/container.sh

bin/hugo:
	$(build_hugo)
	rm bin/container.sh
	chmod +x bin/hugo
