.PHONY: generate build run lint format clean

generate:
	xcodegen generate --quiet

build: generate
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -quiet build

run: build
	open build/Build/Products/Debug/Casper.app

lint:
	swift format lint --strict --recursive Casper

format:
	swift format format --in-place --recursive Casper

clean:
	-trash build Casper.xcodeproj Casper/Info.plist Casper/Casper.entitlements
