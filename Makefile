# Snappy — everyday tasks. Needs a Mac with Xcode for anything but `icon`.

XCODEGEN := $(shell command -v xcodegen 2> /dev/null)
PROJECT := Snappy.xcodeproj
SCHEME := Snappy

.PHONY: help
help:
	@echo "make bootstrap  install XcodeGen and generate $(PROJECT)"
	@echo "make project    regenerate $(PROJECT) from project.yml"
	@echo "make open       generate and open in Xcode"
	@echo "make test       run the unit tests on a simulator"
	@echo "make icon       regenerate the app icon PNG"
	@echo "make clean      remove generated build output"

.PHONY: bootstrap
bootstrap:
ifndef XCODEGEN
	brew install xcodegen
endif
	$(MAKE) project

.PHONY: project
project:
	xcodegen generate

$(PROJECT):
	$(MAKE) project

.PHONY: open
open: project
	open $(PROJECT)

.PHONY: test
test: project
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		CODE_SIGNING_ALLOWED=NO

.PHONY: icon
icon:
	python3 scripts/make_app_icon.py

.PHONY: clean
clean:
	rm -rf build $(PROJECT) Support/Info.plist
