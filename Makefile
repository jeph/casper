.PHONY: generate build run test archive lint format clean

generate:
	xcodegen generate --quiet

# mlx-swift ships a package plugin, which command-line builds reject unless validation is skipped.
build: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -quiet build

run: build
	open build/Build/Products/Debug/Casper.app

test: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation \
		-onlyUsePackageVersionsFromResolvedFile -quiet test

# A production build: optimized, stripped, with dSYMs beside it, and package versions taken only from the
# committed Package.resolved. ARCHS goes on the command line so package targets skip x86_64 as well.
# Release CI sets VERSION and BUILD_NUMBER, then signs the app with the Developer ID certificate.
VERSION ?= 0.0.0
BUILD_NUMBER ?= 0
archive: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Release \
		-derivedDataPath build -destination 'generic/platform=macOS' -skipPackagePluginValidation \
		-onlyUsePackageVersionsFromResolvedFile -quiet archive -archivePath build/Casper.xcarchive \
		ARCHS=arm64 MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

lint:
	swift format lint --strict --recursive Casper CasperTests

format:
	swift format format --in-place --recursive Casper CasperTests

# Package.resolved inside the project is committed, so only the ignored parts of the project are removed.
clean:
	-trash build Casper/Info.plist Casper/Casper.entitlements \
		$(shell git ls-files --others --ignored --exclude-standard --directory Casper.xcodeproj)
