# SideCord plugins

SideCord plugin schema v1 is deliberately declarative. A plugin is a UTF-8 JSON
file no larger than 1 MB containing one `manifest`. XML, JavaScript, native
libraries, shell commands, remote resources, and arbitrary WebView access are
not supported.

## Package example

```json
{
  "manifest": {
    "schemaVersion": 1,
    "identifier": "com.example.quiet-reader",
    "name": "Quiet Reader",
    "version": "1.0.0",
    "author": "Example Author",
    "description": "A quiet layout and locally validated style.",
    "minimumSideCordVersion": "2.1.0",
    "capabilities": ["layout", "styleSheet", "command"],
    "contributions": {
      "layouts": [
        {
          "id": "quiet-layout",
          "name": "Quiet Reader",
          "options": {
            "navigationPresentation": "hidden",
            "composerMode": "hidden",
            "hideMemberList": true,
            "hideAccountDock": true,
            "simplifyHeader": true,
            "compactMedia": false,
            "reduceMotion": true
          }
        }
      ],
      "styleSheets": [
        {
          "id": "quiet-style",
          "name": "Quiet spacing",
          "css": ".sidecord-example { opacity: 0.9; }"
        }
      ],
      "commands": [
        {
          "id": "reader-command",
          "name": "Use Reader",
          "symbol": "book.fill",
          "action": "useReaderLayout"
        }
      ]
    }
  }
}
```

Every included contribution must have a unique identifier. The declared
`capabilities` must exactly match the contribution groups in the package.
Packages install disabled and users explicitly enable them in Settings.

Supported capabilities are `theme`, `layout`, `styleSheet`, and `command`.
Commands may only select built-in layouts/themes, toggle the floating rail, or
reload Discord. Style sheets pass the same conservative validation as custom
CSS and cannot contain URLs, `@` rules, comments, escapes, or network-capable
functions.

## Marketplace signing

A curated catalog is an envelope with Base64-encoded catalog JSON in `payload`
and an Ed25519 signature in `signature`. The release build supplies these Info
properties:

- `SideCordMarketplaceCatalogURL`: HTTPS URL of the signed catalog envelope.
- `SideCordMarketplacePublicKey`: Base64 raw 32-byte Ed25519 public key.

Each catalog entry contains the HTTPS package URL and lowercase SHA-256 package
hash. SideCord verifies the catalog signature before displaying it and verifies
the package hash before installation. The private signing key must stay in the
release system and must never be committed to this repository.
