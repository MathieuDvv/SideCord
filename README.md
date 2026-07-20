<div align="center">
  <img src="docs/assets/sidecord-icon.png" width="112" height="112" alt="SideCord app icon">
  <h1>SideCord</h1>
  <p>
    <strong>Discord, one edge away.</strong><br>
    A focused, edge-native Discord sidebar for macOS and Windows.
  </p>
  <p>
    <img src="https://img.shields.io/badge/macOS-26%2B-111318?style=flat-square&logo=apple&logoColor=white" alt="macOS 26 or newer">
    <img src="https://img.shields.io/badge/Windows-10%2B-0078D4?style=flat-square&logo=windows&logoColor=white" alt="Windows 10 or newer">
    <a href="https://github.com/MathieuDvv/SideCord/releases/latest"><img src="https://img.shields.io/github/v/release/MathieuDvv/SideCord?style=flat-square&label=release&color=6757eb" alt="Latest SideCord release"></a>
  </p>
  <p>
    <a href="#install-sidecord"><strong>Install SideCord</strong></a>
    &nbsp;·&nbsp;
    <a href="#what-you-get">Features</a>
    &nbsp;·&nbsp;
    <a href="#build-from-source">Build from source</a>
  </p>
  <p>
    <a href="https://ko-fi.com/dotslimy"><img src="https://img.shields.io/badge/Tip%20the%20creator-Ko--fi-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white" alt="Tip the creator on Ko-fi"></a>
  </p>
</div>

<picture>
  <source media="(prefers-reduced-motion: reduce)" srcset="docs/assets/sidecord-demo-still.png">
  <img src="docs/assets/sidecord-demo.gif" width="960" alt="SideCord edge glow and sidebar reveal on macOS">
</picture>

SideCord keeps Discord close without dedicating a permanent window to it. Move
the pointer to your chosen display edge or press a global shortcut: your same
Discord session slides into view, then stays alive when the sidebar retracts.

## Install SideCord

Choose the installer for your computer from the
[latest GitHub Release](https://github.com/MathieuDvv/SideCord/releases/latest):

| | macOS | Windows |
|---|---|---|
| **Download** | `SideCord-macOS-universal-<version>.dmg` | `SideCord-Setup-<version>-x64.exe` |
| **Requires** | macOS 26 or newer | Windows 10 version 1809 or newer (x64) |
| **Built with** | Native Swift, AppKit, SwiftUI, and WebKit | Electron, Chromium, and a native Windows shell |

### 🍎 macOS

1. Open the [latest release](https://github.com/MathieuDvv/SideCord/releases/latest)
   and download the file ending in `.dmg`.
2. Open the downloaded disk image, then drag **SideCord** onto the
   **Applications** shortcut.
3. Open **SideCord** from Applications.
4. Follow the welcome screen, sign in to Discord, and choose your edge.

The macOS installer is universal: the same download works on Apple silicon and
Intel Macs. If macOS blocks the first launch, try opening SideCord once, then
follow [Apple's current instructions](https://support.apple.com/guide/mac-help/open-an-app-by-overriding-security-settings-mh40617/mac): open **System
Settings → Privacy & Security**, find the SideCord message under Security,
choose **Open Anyway**, and confirm **Open**.

### 🪟 Windows

1. Open the [latest release](https://github.com/MathieuDvv/SideCord/releases/latest)
   and download the file ending in `-x64.exe`.
2. Double-click the downloaded setup file.
3. If Microsoft Defender SmartScreen appears, choose **More info**, verify that
   you downloaded the file from this repository's Releases page, then choose
   **Run anyway**.
4. Complete the installer and open **SideCord** from the Start Menu or the
   optional desktop shortcut.

Windows may not offer **Run anyway** on a managed computer or when Smart App
Control is enforcing signed apps. In that case, do not disable your computer's
security controls; SideCord will need a code-signed release.

> [!IMPORTANT]
> Current community installers are not code-signed, and the macOS build is not
> notarized. Gatekeeper or SmartScreen may therefore ask for the confirmation
> described above. Only download SideCord from this repository's GitHub
> Releases page.

<details>
<summary><strong>Verify your download (optional)</strong></summary>

Every release includes `SHA256SUMS.txt`. This is not an installer; it contains
checksums that let you confirm your download has not changed.

On macOS, run `shasum -a 256 SideCord-macOS-universal-<version>.dmg`. On
Windows, run
`Get-FileHash .\SideCord-Setup-<version>-x64.exe -Algorithm SHA256` in
PowerShell. The result should match the corresponding line in
`SHA256SUMS.txt`.

</details>

## What you get

- Persistent Discord session that survives sidebar retraction
- Left or right placement, multi-display geometry, pinning, and maximize/restore
- Edge-hover reveal and configurable global shortcuts
- Full, Focus, Reader, and Custom Discord layouts
- Optional detached server rail with selection, unread, and mention state
- Theme-aware edge glow for Discord activity
- Discord-integrated SideCord settings instead of a separate settings window
- Mica, Discord, OLED, and Soft themes with configurable accents
- Local custom CSS with remote-resource primitives rejected
- Strict Discord navigation, OAuth popup, permission, and external-link policies
- No SideCord analytics or telemetry

Mica uses the Windows 11 22H2 system backdrop material on Windows and falls back
to an opaque matching palette where DWM Mica is unavailable. OLED always keeps
the detached Windows rail opaque pure black.

## Platform notes

The two implementations intentionally share the product behavior while using
the strongest native integration available on each operating system.

- **macOS:** native nonactivating panels, Spaces support, WebKit, Reduce Motion
  and Reduce Transparency integration, incoming-call controls, and declarative
  plugins with isolated web panels.
- **Windows:** native Mica, a system tray menu, launch-at-login integration,
  Windows global accelerators, an isolated Electron preload, and a separate
  always-on-top server rail window.

See [MacOS/README.md](MacOS/README.md) and
[Windows/README.md](Windows/README.md) for platform-specific development notes.

## Repository layout

```text
SideCord/
├── MacOS/          Native Swift implementation, Xcode project, and tests
├── Windows/        Electron implementation, Node tests, and NSIS packaging
├── docs/           Shared documentation and product artwork
├── scripts/        Shared plugin-catalog tooling
├── README.md       Cross-platform product and build guide
├── CONTRIBUTING.md Development workflow and security boundaries
├── LICENSE         PolyForm Noncommercial 1.0.0 terms
└── PRIVACY.md      Cross-platform privacy policy
```

## Build from source

### macOS

Requirements: macOS 26, Xcode 26, and XcodeGen when regenerating the project.

```sh
cd MacOS
xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' build
xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' test
```

After changing `MacOS/project.yml`, regenerate and commit the checked-in project:

```sh
cd MacOS
xcodegen generate
```

Build the unsigned universal macOS drag-to-Applications disk image:

```sh
MacOS/scripts/build-installer.sh
```

### Windows

Requirements: Node.js 22 or newer. Development works on macOS, Windows, and
Linux; the final NSIS installer is built on Windows.

```powershell
cd Windows
npm ci
npm test
npm start
npm run dist
```

Pushing a version tag runs both installer builds on GitHub-hosted macOS 26 and
Windows runners, verifies the platform tests, and publishes the installers and
`SHA256SUMS.txt` to a GitHub Release.

## Privacy, plugins, and contributions

SideCord does not inspect Discord credentials or tokens and has no analytics.
Read [PRIVACY.md](PRIVACY.md) for platform-specific storage, permission, rail,
call, and plugin details.

macOS plugins are declarative JSON packages rather than executable extensions.
They can contribute validated styles, layouts, commands, and isolated web
panels. See [docs/PLUGINS.md](docs/PLUGINS.md) for the format and marketplace
security model.

Bug fixes, selector updates, accessibility improvements, platform parity work,
and documentation contributions are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

SideCord is source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). Noncommercial forks and
modified copies are permitted, but every redistributed copy must include the
license and required notice. Commercial use, monetization, and monetized
distribution require separate written permission from the creator.

If SideCord saves you time, you can
[tip the creator on Ko-fi](https://ko-fi.com/dotslimy).

<p align="center"><sub>SideCord is independent software and is not affiliated with Discord Inc.</sub></p>
