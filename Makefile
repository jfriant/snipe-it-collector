FN := deploy.txt
DEPLOY_PATH := $(shell cat ${FN})

.PHONY: build clean

build: clean
	zip -e $(DEPLOY_PATH)/snipe-it-collector.zip collector.ps1 config.json

clean:
	-rm $(DEPLOY_PATH)/snipe-it-collector.zip
