PROJECT := Yapper.xcodeproj
SCHEME := Yapper
DESTINATION := platform=macOS,arch=arm64
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData/Yapper-scaffold
APP := $(DERIVED_DATA)/Build/Products/Debug/Yapper.app
# Tests build unsigned (CODE_SIGNING_ALLOWED=NO). Keep them out of DERIVED_DATA so they never replace the
# signed app that macOS privacy permissions (Accessibility, Input Monitoring, Microphone) are granted to.
TEST_DERIVED_DATA := $(DERIVED_DATA)-tests

.PHONY: help build run test lint clean
.DEFAULT_GOAL := help

help:
	@printf '%s\n' 'make run    Build Debug and launch Yapper' \
		'make build  Build Debug only' \
		'make test   Run the test suite' \
		'make lint   Run strict Swift formatting lint' \
		'make clean  Clean Xcode build products'

build:
	xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath '$(DERIVED_DATA)' build

run:
	@if pgrep -x Yapper >/dev/null 2>&1; then \
		printf '%s\n' 'Yapper is already running. Quit it from the menu bar, then run make run again.' >&2; \
		exit 1; \
	fi
	$(MAKE) build
	open '$(APP)'

test:
	xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath '$(TEST_DERIVED_DATA)' test CODE_SIGNING_ALLOWED=NO

lint:
	xcrun swift format lint --strict --recursive Yapper YapperTests

clean:
	xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath '$(DERIVED_DATA)' clean
