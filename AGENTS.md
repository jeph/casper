# Casper

## Third-party licenses

`Casper/Resources/Acknowledgements.txt` ships inside the app and holds the license text and notices for every third-party component compiled into the binary. Keep it current in the same change whenever you:

- add, remove, or change the version of a Swift package in `project.yml`, including version bumps that change `Package.resolved`
- copy or adapt code, prompts, data, or assets from another project (also keep that project's copyright and license header in the copied file, as `Casper/Refine/RefinePrompt.swift` does)
- bundle model weights or other licensed files in the app instead of downloading them at runtime

List only what ends up in the app: check a Release build with `nm build/Build/Products/Release/Casper.app/Contents/MacOS/Casper` rather than assuming every resolved package is linked. For each component, copy its license file verbatim, add any Apache `NOTICE` file, and include code it vendors or links statically. Today that means the libraries vendored inside mlx-swift's `Cmlx` directory, FluidAudio's `ThirdPartyLicenses/` folder, and the Rust crates in FluidAudio's `NemoTextProcessing` framework (list them with `cargo tree -e normal --features ffi,fst-engine --target aarch64-apple-darwin` at the text-processing-rs tag FluidAudio's `Package.swift` pins, leaving out compile-time-only proc-macro crates).

Before adding a dependency, check its license. Don't add copyleft code (GPL, LGPL, AGPL) without asking first, since it would change how Casper can be distributed.
