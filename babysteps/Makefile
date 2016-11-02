help:
	@echo "try serve, generate, or deploy"

serve:
	bundle exec jekyll serve --incremental

generate:
	bundle exec jekyll build

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded _site/ scf:web/babysteps/
