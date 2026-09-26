# Casper

Private, local dictation for macOS. A native Swift take on [OpenWhispr](https://github.com/OpenWhispr/openwhispr): speech recognition and text cleanup run on your Mac with MLX and the Apple Neural Engine, and your audio never leaves the device.

Early development. Today Casper is a menu bar app shell; dictation is not implemented yet.

## Requirements

- Apple silicon Mac, macOS 15 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

The Xcode project is generated from `project.yml` and not committed.

```sh
make run       # generate the project, build, and launch
make build     # generate and build only
make generate  # generate Casper.xcodeproj to work in Xcode
make lint      # check formatting with swift-format
make format    # apply swift-format
```

## License

[MIT](LICENSE)
