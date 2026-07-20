# SideCord for macOS

<p align="center"><img src="../docs/assets/sidecord-icon.png" width="96" height="96" alt="SideCord app icon"></p>

This directory contains SideCord's native macOS implementation built with
Swift 6, AppKit, SwiftUI, and WebKit. It requires macOS 26 and Xcode 26.

Build and test from this directory:

```sh
xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' build
xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' test
```

`project.yml` is the source of truth for the checked-in Xcode project. After
editing it, run `xcodegen generate` from this directory.

Build an unsigned universal drag-to-Applications disk image from the repository root:

```sh
MacOS/scripts/build-installer.sh
```

The output is written to `MacOS/dist/SideCord-macOS-universal-<version>.dmg`.
Signing and notarization can be layered onto this disk image when
Apple Developer ID credentials are configured.

SideCord is source-available under the repository's
[PolyForm Noncommercial License 1.0.0](../LICENSE).
