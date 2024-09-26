help:
	@echo "try:"
	@echo "  make post NAME=foo-bar"
	@echo "  make serve"
	@echo "  make serve-drafts"
	@echo "  make generate deploy"

HUGOURL=https://github.com/gohugoio/hugo/releases/download/v0.118.2/hugo_extended_0.118.2_linux-amd64.tar.gz
hugo ?= ./hugo

hugo:
	curl -L ${HUGOURL} | tar zxf -> hugo

post: hugo
	@if [ -z "${NAME}" ]; then echo "Set NAME to something!"; else ${hugo} new content content/blog/`date '+%Y-%m-%d'`-${NAME}.markdown; fi

serve: hugo
	${hugo} server --minify

serve-drafts: hugo
	./hugo server --minify --buildFuture

generate: hugo
	./hugo --minify --buildFuture

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded public/ scf:web/babysteps/

deployci:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded public/ ${DEPLOY_TARGET}

