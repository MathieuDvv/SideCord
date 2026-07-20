# SideCord for Windows

<p align="center"><img src="../docs/assets/sidecord-icon.png" width="96" height="96" alt="SideCord app icon"></p>

This directory contains SideCord's Windows implementation. Electron hosts a
persistent Discord Chromium session while the main process provides the tray,
global shortcuts, multi-monitor panel geometry, launch at login, native Mica,
notification glow, and the detached server rail.

## Requirements

- Windows 10 version 1809 or newer
- Node.js 22 or newer when building from source

Mica uses the Windows 11 22H2 system backdrop. Older Windows versions receive an
opaque matching fallback. OLED keeps the detached rail opaque pure black.

## Develop and test

```powershell
npm ci
npm test
npm start
```

The persistent Discord profile and `settings.json` are stored in Electron's
standard per-user application-data directory.

## Build the installer

Run on Windows x64:

```powershell
npm run dist
```

This creates `dist/SideCord-Setup-<version>-x64.exe`, an interactive NSIS
installer with Start Menu and optional desktop shortcuts plus an uninstaller.
`npm run pack` remains available for an unpacked development build, but unpacked
output is not published as the release installer.

This community build is unsigned, so Windows SmartScreen may require explicit
confirmation until an Authenticode certificate is configured.

For shared features, privacy, downloads, and contribution guidance, return to
the [repository README](../README.md).

SideCord is source-available under the repository's
[PolyForm Noncommercial License 1.0.0](../LICENSE).
