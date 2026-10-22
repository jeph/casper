# Casper

## Branches and worktrees

Several agents work on this repository at once, so make every change in its own git worktree instead of in the main checkout at `~/Developer/casper`. Create the worktree next to the main checkout on a new branch from `dev`, for example `git worktree add ../casper-<branch> -b <branch> dev`, and leave the main checkout on `dev`.

Documentation changes are the exception. Edit Markdown files such as `AGENTS.md` and `README.md` directly in the main checkout on `dev`; they don't need a worktree. The exception covers documentation only: changes to the build system or release pipeline, such as the `Makefile`, `project.yml`, `Package.resolved`, build scripts, or `.github/workflows/`, go in a worktree like any code change, even though they aren't application logic.

Development is trunk-based: `dev` is the trunk, and work reaches it in small, frequent pushes. There's one installed copy of Casper on this machine, `/Applications/Casper.app`, and any agent may replace it with a build from its worktree to test changes. Always pull `dev` into the worktree before building, with `git fetch origin && git rebase origin/dev`. Resolve any conflicts, and if changes other agents landed on `dev` break yours or don't work with them, fix that in your branch before you build. That way every build tested on this machine is the current `dev` plus your work, so changes on `dev` get integrated and tested together as they land.

Never push to `main`, since every push there publishes a release (see Releases). Finished work goes directly to `dev`, and this project doesn't use pull requests, but only push once the user has explicitly told you to; until then, commit locally and ask. From a worktree, rebase the branch onto `origin/dev` and run `git push origin HEAD:dev`. Never force push, to any branch, with `--force`, `--force-with-lease`, or a `+` refspec. If the push is rejected because `dev` moved, fetch, rebase onto `origin/dev` again, fix any conflicts or breakage, and push again. Worktree branches stay local: never push them to the repository under their own names.

Once the push has landed, remove the worktree and its branch so they don't pile up on this machine. Confirm the work is on `dev` with `git fetch origin && git merge-base --is-ancestor HEAD origin/dev`, then from the main checkout run `git worktree remove ../casper-<branch>` and `git branch -D <branch>`. Finally, bring the main checkout up to date with `git pull --ff-only origin dev`, so it matches `dev`.

## Code you touch

Leave code you change better than you found it, and limit the cleanup to that code: don't refactor whole files or unrelated parts of the codebase. Where a change touches a function or block, flatten its nesting where you can, using early returns and guards and reordering conditions so the common path reads straight down, and simplify what's there. Some nesting is unavoidable; keep it when flattening would make the code harder to follow. Rename variables, properties, and functions in that code whose names no longer match what they hold or do, or could say it more precisely.

## Commits

Write commit messages in the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format: `<type>(<optional scope>): <description>`, for example `fix(dictation): keep the voice bubble on the active screen`. Use `feat` for new behavior, `fix` for bug fixes, `docs` for documentation-only changes, and `refactor`, `perf`, `test`, `build`, `ci`, or `chore` where they fit. Mark breaking changes with `!` after the type or scope and a `BREAKING CHANGE:` footer.

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

Packages also port code from other projects without shipping that project's notice, so search the linked sources for comments such as "port of" and "ported from", and add the upstream project's license and copyright for each port. Today that covers FluidAudio's ports of FunASR, NVIDIA NeMo, Chatterbox, and ZipVoice, and speech-swift's port of NeMo. A "port" that only converts model weights, such as FluidAudio's Core ML port of LocalVQE, needs no entry while the app doesn't bundle the model.

The website ships third-party code to browsers too, so `website/public/third-party-licenses.txt` holds the notices for everything a build of `website/` serves, and `website/public/pagefind/SOURCE.txt` points to the source of Pagefind's search WebAssembly. Starlight's search uses that WebAssembly, and it includes the GPL-3.0 crate `pagefind_microjson`; Casper serves it unmodified, with the GPL text and source links in those two files. Update both files in the same change whenever you add, remove, or upgrade a website package, including the Pagefind version Starlight pulls in. To list what a build serves, build with `vite: { build: { sourcemap: true } }` and read each map's `sources`; then, at the Pagefind tag the lockfile resolves, run `cargo tree -e normal,no-proc-macro --target wasm32-unknown-unknown` in `pagefind_web` and read the dependencies of the `pagefind_ui` and `pagefind_web_js` packages.

Before adding a dependency, check its license. Don't add copyleft code (GPL, LGPL, AGPL) without asking first, since it would change how Casper can be distributed.

## Releases

Every push to `main` runs `.github/workflows/release.yml`, which builds with `make archive`, signs and notarizes the app with the Developer ID certificate, publishes a GitHub release numbered `0.0.<run number>`, and updates the `casper` cask in `jeph/homebrew-tap`. Keep `main` releasable, and keep `make archive` the single definition of a production build so local and CI builds match. The signing, notarization, and tap secrets are repository secrets, passed only to the steps that need them; the build job gets none because package plugins and build scripts run there. Actions must be GitHub-owned and pinned to a full commit SHA, which the repository settings enforce.

Commit `Package.resolved` whenever package versions change; release builds refuse to resolve anything it doesn't pin.
