# Contributing to SideCord

Thanks for helping improve SideCord. Contributions should preserve the focused,
edge-native experience and the privacy boundary between Discord content and the
native host.

## Before opening a change

1. Search existing issues and pull requests for overlapping work.
2. Keep changes scoped to one coherent behavior or platform-parity improvement.
3. Never include Discord credentials, cookies, tokens, private server data,
   signing certificates, or marketplace signing keys.
4. Open a draft pull request early for architectural, permission, plugin, or
   cross-platform changes.

## Repository structure

- `MacOS/` contains the native Swift/AppKit/SwiftUI/WebKit implementation.
- `Windows/` contains the Electron/Chromium implementation and NSIS packaging.
- `docs/` contains shared artwork and long-form documentation.
- `scripts/` contains the signed plugin-catalog tooling used by GitHub Actions.

Shared product behavior belongs in the root documentation. Platform-specific
implementation notes belong beside that platform's source.

## macOS development

Requirements: macOS 26, Xcode 26, and XcodeGen when editing the project model.

```sh
cd MacOS
xcodebuild -project SideCord.xcodeproj -scheme SideCord \
  -destination 'platform=macOS' test
```

`MacOS/project.yml` is the project source of truth. When it changes, run
`xcodegen generate` from `MacOS/` and commit both the YAML and generated
`SideCord.xcodeproj` changes.

## Windows development

Requirements: Node.js 22 or newer.

```sh
cd Windows
npm ci
npm test
npm start
```

Run `npm run dist` on Windows to exercise the complete NSIS installer build.
`npm run pack` creates an unpacked x64 directory for local packaging checks.

## Web and privacy boundaries

- Keep Node integration disabled for Discord and authentication content.
- Keep context isolation and sandboxing enabled.
- Validate every renderer-to-native message and verify its sender.
- Do not expose tokens, arbitrary filesystem access, process execution, or a
  general-purpose native bridge to Discord or plugin pages.
- Keep top-level navigation restricted to HTTPS Discord origins; external links
  should leave SideCord.
- Treat Discord selectors as unstable. Prefer semantic roles, bounded fallbacks,
  and tests that fail safely when Discord changes.
- Do not add analytics or telemetry.

## Documentation and artwork

The shared product logo is `docs/assets/sidecord-icon.png`. Platform icon sources
must stay visually aligned with it. Update screenshots or animation sources only
when the represented behavior materially changes, and provide descriptive alt
text for new documentation images.

## Pull request checklist

- The relevant macOS and/or Windows tests pass.
- New behavior has proportionate automated coverage.
- Security and privacy implications are documented.
- User-facing changes update the root or platform README.
- Generated files are updated intentionally.
- No build output, dependency directory, local profile, or credential is added.

## Contribution license

SideCord is distributed under the
[PolyForm Noncommercial License 1.0.0](LICENSE). By submitting a contribution,
you confirm that you have the right to provide it and agree that it may be
distributed as part of SideCord under that license. Forks and modified
distributions must preserve the license and required notice. Commercial use or
monetization requires separate written permission from the creator.

Maintainers create releases from version tags. The release workflow builds an
unsigned universal macOS DMG and an unsigned Windows x64 NSIS installer, then
publishes both with SHA-256 checksums after their platform tests pass.
