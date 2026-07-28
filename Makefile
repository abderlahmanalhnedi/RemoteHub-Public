.PHONY: bootstrap generate build test ui-test core-check clean open lint

REMOTEHUB_DERIVED_DATA_PATH ?= $(shell getconf DARWIN_USER_CACHE_DIR)com.alhnedi.RemoteHub/DerivedData
MAC_ARCH := $(shell uname -m)

bootstrap:
	./Scripts/bootstrap.sh

generate:
	@if command -v xcodegen >/dev/null 2>&1; then xcodegen generate; else echo "XcodeGen is required to regenerate RemoteHub.xcodeproj (brew install xcodegen)."; exit 1; fi

build:
	REMOTEHUB_DERIVED_DATA_PATH='$(REMOTEHUB_DERIVED_DATA_PATH)' ./Scripts/build.sh

test:
	./Scripts/test.sh

ui-test:
	xcodebuild -project RemoteHub.xcodeproj -scheme RemoteHub -configuration Debug -derivedDataPath '$(REMOTEHUB_DERIVED_DATA_PATH)' -destination 'platform=macOS,arch=$(MAC_ARCH)' test

core-check:
	./Scripts/core-check.sh

clean:
	swift package clean
	xcodebuild -project RemoteHub.xcodeproj -scheme RemoteHub -derivedDataPath '$(REMOTEHUB_DERIVED_DATA_PATH)' clean

open:
	@if [ -d /Applications/Xcode.app ]; then open RemoteHub.xcodeproj; else echo "Install full Xcode, then run: make open"; exit 1; fi

lint:
	./Scripts/lint.sh
