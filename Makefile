.PHONY: build

build:
	-rm ~/Dropbox/TMAT/software/snipe-it-collector.zip
	zip -e ~/Dropbox/TMAT/software/snipe-it-collector.zip collector.ps1 config.json
