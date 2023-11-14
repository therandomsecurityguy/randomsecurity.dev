SHELL:=/bin/bash
BASEDIR=$(CURDIR)
OUTPUTDIR=public

.PHONY: all
all: clean git_update build deploy publish

.PHONY: clean
clean:
	@echo "Removing public directory"
	rm -rf $(BASEDIR)/$(OUTPUTDIR)

.PHONY: git_update
git_update:
	@echo "Updating Hugo git repository"
	git pull

.PHONY: build
build:
	@echo "Generating static site content"
	hugo --gc --minify

.PHONY: deploy
deploy:
	@echo "Preparing commit"
	git add .
	git status
	git commit -m "Deploying via Makefile"
	git push -u origin master

	@echo "Pushed to remote"

.PHONY: deploy
publish:
	@echo "Deploying to Cloudflare Workers"
	wrangler deploy
