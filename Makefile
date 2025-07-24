help:
	@echo "try:"
	@echo "  make post NAME=foo-bar"
	@echo "  make serve"
	@echo "  make serve-drafts"
	@echo "  make generate deploy"

# Use Hugo from proto
hugo = hugo

post:
	@if [ -z "${NAME}" ]; then echo "Set NAME to something!"; else ${hugo} new content content/blog/`date '+%Y-%m-%d'`-${NAME}.markdown; fi

serve:
	${hugo} server --minify

serve-drafts:
	${hugo} server --minify --buildFuture

generate:
	${hugo} --minify --buildFuture

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded public/ scf:web/babysteps/

deployci:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded public/ ${DEPLOY_TARGET}

