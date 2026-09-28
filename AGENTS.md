# Casper

## Third-party licenses

`Casper/Resources/Acknowledgements.txt` ships inside the app and holds the license text and notices for every third-party component compiled into the binary. Keep it current in the same change whenever you:

- add, remove, or change the version of a Swift package in `project.yml`, including version bumps that change `Package.resolved`
- copy or adapt code, prompts, data, or assets from another project (also keep that project's copyright and license header in the copied file, as `Casper/Refine/RefinePrompt.swift` does)
- bundle model weights or other licensed files in the app instead of downloading them at runtime

List what ends up in the app, starting from a fresh Release build rather than assuming every resolved package is linked:

- The package products the target depends on, and what they depend on, from `project.yml` and each package's `Package.swift`, including binary targets (prebuilt `.xcframework`s).
- Everything in `Casper.app/Contents/Resources/`, including the resource bundles packages ship, such as model data, lexicons, and Metal libraries.
- Symbols in `Casper.app/Contents/MacOS/Casper` (`nm`, `strings`), to confirm the above. Symbols can be stripped or inlined, so a missing symbol isn't a reason to drop a notice.

For each component, copy its license file verbatim, add any Apache `NOTICE` file, and include what it vendors or links statically, down to license headers inside individual source files. Today that means the libraries vendored inside mlx-swift's `Cmlx` directory, along with the file-level notices in MLX and JSON for Modern C++; FluidAudio's `ThirdPartyLicenses/` folder; and the Rust crates in FluidAudio's `NemoTextProcessing` framework (list them with `cargo tree -e normal --features ffi,fst-engine --target aarch64-apple-darwin` at the text-processing-rs tag FluidAudio's `Package.swift` pins, leaving out compile-time-only proc-macro crates).

Before adding a dependency, check its license. Don't add copyleft code (GPL, LGPL, AGPL) without asking first, since it would change how Casper can be distributed.
