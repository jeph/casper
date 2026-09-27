.PHONY: generate build run lint format clean

REFINE_MODEL := Models/Qwen3-4B-Instruct-2507-4bit

generate:
	xcodegen generate --quiet

# Downloads and verifies the bundled refine model again whenever its pinned checksums change.
$(REFINE_MODEL): $(REFINE_MODEL).sha256 scripts/download-model.sh
	scripts/download-model.sh mlx-community/Qwen3-4B-Instruct-2507-4bit 50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b $@
	touch $@

# mlx-swift ships a package plugin, which command-line builds reject unless validation is skipped.
build: generate $(REFINE_MODEL)
	xcodebuild -project Casper.xcodeproj -scheme Casper -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -quiet build

run: build
	open build/Build/Products/Debug/Casper.app

lint:
	swift format lint --strict --recursive Casper

format:
	swift format format --in-place --recursive Casper

clean:
	-trash build Casper.xcodeproj Casper/Info.plist Casper/Casper.entitlements
