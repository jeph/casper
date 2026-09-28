.PHONY: generate build run test lint format clean

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
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -quiet test

lint:
	swift format lint --strict --recursive Casper CasperTests

format:
	swift format format --in-place --recursive Casper CasperTests

clean:
	-trash build Casper.xcodeproj Casper/Info.plist Casper/Casper.entitlements
