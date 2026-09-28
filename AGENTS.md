# Casper

## Branches and worktrees

Several agents work on this repository at once, so make every change in its own git worktree instead of in the main checkout at `~/Developer/casper`. Create the worktree next to the main checkout on a new branch from `dev`, for example `git worktree add ../casper-<branch> -b <branch> dev`, and leave the main checkout on `dev`.

Documentation changes are the exception. Edit Markdown files such as `AGENTS.md` and `README.md` directly in the main checkout on `dev`; they don't need a worktree.

Never push to `main`, since every push there publishes a release (see Releases). Push finished work directly to `dev` instead; that's always allowed, and this project doesn't use pull requests. From a worktree, rebase the branch onto `origin/dev` and run `git push origin HEAD:dev`.

## Third-party licenses

`Casper/Resources/Acknowledgements.txt` ships inside the app and holds the license text and notices for every third-party component compiled into the binary. Keep it current in the same change whenever you:

- add, remove, or change the version of a Swift package in `project.yml`, including version bumps that change `Package.resolved`
- copy or adapt code, prompts, data, or assets from another project (also keep that project's copyright and license header in the copied file, as `Casper/Refine/RefinePrompt.swift` does)
- bundle model weights or other licensed files in the app instead of downloading them at runtime

List what ends up in the app, starting from a fresh `make archive` rather than assuming every resolved package is linked:

- The package products the target depends on, and what they depend on, from `project.yml` and each package's `Package.swift`, including binary targets (prebuilt `.xcframework`s).
- Everything in `Casper.app/Contents/Resources/`, including the resource bundles packages ship, such as model data, lexicons, and Metal libraries.
- Symbols and strings in the release binary, to confirm the above. The archived binary is stripped, so run `nm` on `build/Casper.xcarchive/dSYMs/Casper.app.dSYM/Contents/Resources/DWARF/Casper`; run `strings` on the app's own `Contents/MacOS/Casper`, since the dSYM holds no string data. Symbols can also be inlined, so a missing symbol isn't a reason to drop a notice.

For each component, copy its license file verbatim, add any Apache `NOTICE` file, and include what it vendors or links statically, down to license headers inside individual source files. Today that means the libraries vendored inside mlx-swift's `Cmlx` directory, along with the file-level notices in MLX and JSON for Modern C++, and FluidAudio's `ThirdPartyLicenses/` folder. `project.yml` turns off FluidAudio's `NemoTextProcessing` trait, so its prebuilt Rust library isn't linked. If you turn it back on, add text-processing-rs and its Rust crates (list them with `cargo tree -e normal --features ffi,fst-engine --target aarch64-apple-darwin` at the tag FluidAudio's `Package.swift` pins, leaving out compile-time-only proc-macro crates).

Before adding a dependency, check its license. Don't add copyleft code (GPL, LGPL, AGPL) without asking first, since it would change how Casper can be distributed.

## Releases

Every push to `main` runs `.github/workflows/release.yml`, which builds with `make archive`, signs and notarizes the app with the Developer ID certificate, publishes a GitHub release numbered `0.0.<run number>`, and updates the `casper` cask in `jeph/homebrew-tap`. Keep `main` releasable, and keep `make archive` the single definition of a production build so local and CI builds match. The signing, notarization, and tap secrets are repository secrets, passed only to the steps that need them; the build job gets none because package plugins and build scripts run there. Actions must be GitHub-owned and pinned to a full commit SHA, which the repository settings enforce.

Commit `Package.resolved` whenever package versions change; release builds refuse to resolve anything it doesn't pin.
