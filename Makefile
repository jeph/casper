.PHONY: generate build run test archive lint format clean

generate:
	xcodegen generate --quiet

# Local builds sign the app with a certificate from this Mac's keychain so macOS keeps the Microphone and
# Accessibility permissions across rebuilds; an ad hoc signature changes with every build. Developer ID comes first:
# the requirement it signs with names only the team, which release builds share. Apple Development is next, and
# with neither the app is signed ad hoc. To choose, set LOCAL_SIGNING_IDENTITY in the environment or on the command
# line to a certificate's SHA-1 hash or name, or to - for ad hoc.
signing_identity = $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/"$(1): /{print $$2; exit}')
ifndef LOCAL_SIGNING_IDENTITY
LOCAL_SIGNING_IDENTITY := $(or $(call signing_identity,Developer ID Application),$(call signing_identity,Apple Development),-)
endif

# mlx-swift ships a package plugin, which command-line builds reject unless validation is skipped.
build: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -quiet build \
		LOCAL_SIGNING_IDENTITY='$(LOCAL_SIGNING_IDENTITY)'

run: build
	open build/Build/Products/Debug/Casper.app

# Testing builds the app into the same products folder, so it signs the same way to leave a signed app behind.
test: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation \
		-onlyUsePackageVersionsFromResolvedFile -quiet test LOCAL_SIGNING_IDENTITY='$(LOCAL_SIGNING_IDENTITY)'

# A production build: optimized, stripped, with dSYMs beside it, and package versions taken only from the
# committed Package.resolved. ARCHS goes on the command line so package targets skip x86_64 as well.
# Release CI sets VERSION and BUILD_NUMBER, then signs the app with the Developer ID certificate, replacing the
# local signature.
VERSION ?= 0.0.0
BUILD_NUMBER ?= 0
archive: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Release \
		-derivedDataPath build -destination 'generic/platform=macOS' -skipPackagePluginValidation \
		-onlyUsePackageVersionsFromResolvedFile -quiet archive -archivePath build/Casper.xcarchive \
		ARCHS=arm64 MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		LOCAL_SIGNING_IDENTITY='$(LOCAL_SIGNING_IDENTITY)'

lint:
	swift format lint --strict --recursive Casper CasperTests

format:
	swift format format --in-place --recursive Casper CasperTests

# Package.resolved inside the project is committed, so only the ignored parts of the project are removed.
clean:
	-trash build Casper/Info.plist Casper/Casper.entitlements \
		$(shell git ls-files --others --ignored --exclude-standard --directory Casper.xcodeproj)
