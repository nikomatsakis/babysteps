help:
	@echo "try serve, generate, or deploy"

serve:
	cd babysteps; bundle exec jekyll serve

generate:
	cd babysteps; bundle exec jekyll build

deploy:
	rsync -avr --rsh='ssh' --delete-after --delete-excluded babysteps/_site/ scf:web/babysteps/
