.PHONY: generate build run lint format clean

MODEL := Models/Qwen3-ASR-1.7B-MLX-8bit

generate:
	xcodegen generate --quiet

# Downloads and verifies the bundled speech model again whenever its pinned checksums change.
$(MODEL): $(MODEL).sha256 scripts/download-model.sh
	scripts/download-model.sh
	touch $@

# mlx-swift ships a package plugin, which command-line builds reject unless validation is skipped.
build: generate $(MODEL)
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
