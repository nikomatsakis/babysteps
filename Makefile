help:
	@echo "try:"
	@echo "  make serve"
	@echo "  make serve-drafts"
	@echo "  make generate deploy"

serve:
	hugo server --minify

serve-drafts:
	hugo server --minify --buildFuture

generate:
	hugo --minify --buildFuture

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded public/ scf:web/babysteps/
