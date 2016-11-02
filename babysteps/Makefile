help:
	@echo "try:"
	@echo "  make serve"
	@echo "  make generate deploy"
	@echo "  make post NAME='Foo'"

serve:
	bundle exec jekyll serve --incremental

generate:
	bundle exec jekyll build

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded _site/ scf:web/babysteps/

post:
	@if [ "${NAME}" != '' ]; \
	then bundle exec jekyll post "${NAME}"; \
	else echo "Usage: make post NAME='foo'"; \
	fi
