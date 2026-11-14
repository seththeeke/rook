SHELL := /bin/bash
SCHEME := Rook
PROJECT := Rook.xcodeproj
SIMULATOR ?= iPhone 16 Pro
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
BUILD_DIR := build
RESULT_BUNDLE := $(BUILD_DIR)/RookTests.xcresult
# Amplify's dependency smithy-swift ships an SPM build plugin; Xcode asks to trust it once in the UI,
# and command-line builds need these flags instead.
XCODE_FLAGS := -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO

.PHONY: help generate test test-kit test-app uitest build lint clean open

help:
	@echo "make generate   Generate Rook.xcodeproj from project.yml (XcodeGen)"
	@echo "make test       RookKit (swift test) + app unit & UI tests on $(SIMULATOR)"
	@echo "make test-kit   RookKit tests only (fast, no simulator)"
	@echo "make build      Debug build for the simulator"
	@echo "make lint       Brand check (no 'repwise' in user-facing code)"
	@echo "make open       Generate and open in Xcode"

generate:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

test: lint test-kit test-app

test-kit:
	cd RookKit && swift test --enable-code-coverage
	python3 scripts/check-coverage.py "$$(cd RookKit && swift test --show-codecov-path)"

test-app: generate
	rm -rf $(RESULT_BUNDLE)
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -resultBundlePath $(RESULT_BUNDLE) \
		$(XCODE_FLAGS) -quiet
	@xcrun xccov view --report --only-targets $(RESULT_BUNDLE) || true

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		$(XCODE_FLAGS) -quiet

# Fails if the old brand appears anywhere except backend endpoint values in Config/.
lint:
	@if grep -rniI "repwise" --exclude-dir=Config --exclude-dir=build --exclude-dir=.build \
		--exclude-dir='*.xcodeproj' --exclude=Makefile --exclude=README.md . ; then \
		echo "error: 'repwise' found above — Rook must not ship Repwise branding."; exit 1; \
	else echo "brand check: ok"; fi

open: generate
	open $(PROJECT)

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) RookKit/.build
