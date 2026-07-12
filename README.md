# SideCord

SideCord is a native macOS 26 menu bar app that keeps Discord available in a
resizable, auto-retracting sidebar on every Space.

## Features

- Persistent Discord session in `WKWebView`; hiding the sidebar does not reload it
- Edge-hover reveal and a configurable global shortcut (Option–D by default)
- Floating AppKit panel with configurable screen spacing that follows the
  pointer's display and joins every Space
- Left or right placement, per-display widths, pinning, and maximize/restore
- Full, Focus, Reader, and Custom Discord layouts with self-healing CSS mods
- Compact density preset and conservative local custom CSS
- Discord attachments, downloads, camera, and microphone permission handling
- Native menu bar, onboarding, Settings, Launch at Login, Liquid Glass controls,
  and Reduce Motion/Transparency support

## Development

Requirements: macOS 26, Xcode 26, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

Generate the checked-in Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

Build and test:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' test
```

The app uses the App Sandbox with outgoing-network, user-selected-file,
microphone, and camera entitlements. Set a development team in Xcode for a
locally signed build. Developer ID signing and notarization are required before
distributing outside the Mac App Store.

## Privacy and limitations

SideCord does not inspect Discord credentials or tokens and contains no analytics.
See [PRIVACY.md](PRIVACY.md) for details. Discord can change its web interface or
embedded-browser support at any time, so compact CSS selectors may occasionally
need an update.

SideCord is independent software and is not affiliated with Discord Inc.
