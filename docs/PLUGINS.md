# SideCord plugins

SideCord plugins are declarative UTF-8 JSON files no larger than 1 MB. They
cannot contain or execute plugin-supplied Swift, JavaScript, native libraries,
or shell commands. Schema v1 remains supported unchanged. Schema v2 adds a
host-managed `webPanel` contribution for remote web players, dashboards,
calendars, documentation, and similar accessories. Schema v3 lets a panel
rearrange existing page elements through host-managed document-layout slots.

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

Schema v1 capabilities are `theme`, `layout`, `styleSheet`, and `command`.
Commands may only select built-in layouts/themes, toggle the floating rail, or
reload Discord. Style sheets pass the same conservative validation as custom
CSS and cannot contain URLs, `@` rules, comments, escapes, or network-capable
functions.

## Schema v2 web panel

Schema v2 adds the `webPanel` capability and a `permissions` object. SideCord,
not the plugin, creates and controls the `WKWebView`:

```json
{
  "manifest": {
    "schemaVersion": 2,
    "identifier": "com.mathieudvv.youtube-music",
    "name": "YouTube Music",
    "version": "1.0.0",
    "author": "MathieuDvv",
    "description": "Adds a compact YouTube Music player below Discord.",
    "minimumSideCordVersion": "2.3.0",
    "capabilities": ["webPanel"],
    "permissions": {
      "networkHosts": ["music.youtube.com", "accounts.google.com"],
      "persistentWebsiteData": true,
      "backgroundAudio": true
    },
    "contributions": {
      "webPanels": [
        {
          "id": "youtube-music-player",
          "name": "YouTube Music",
          "placement": "bottom",
          "initialURL": "https://music.youtube.com/",
          "allowedNavigationHosts": [
            "music.youtube.com",
            "accounts.google.com"
          ],
          "preferredHeight": 190,
          "minimumHeight": 140,
          "maximumHeight": 300,
          "userResizable": true,
          "customCSS": "ytmusic-nav-bar { display: none !important; }"
        }
      ]
    }
  }
}
```

Web-panel validation is intentionally strict:

- Initial URLs must use HTTPS and cannot contain credentials, custom ports, IP
  addresses, local files, or custom schemes.
- Hosts are exact lowercase DNS names. Wildcards are not supported.
- The initial host must be allowed for navigation, and every navigation host
  must also be declared in `permissions.networkHosts`.
- A plugin can declare one web panel and at most 16 hosts. SideCord activates
  only one bottom panel at a time.
- Contribution identifiers must be unique across all contribution types.
- Panel CSS is limited to 64 KB and uses the same conservative validator as
  other plugin CSS. It cannot load remote resources.
- SideCord clamps height to its own 120–320 point limits, at most 40% of the
  sidebar height, while preserving a minimum Discord area.

The remote website's own JavaScript runs because modern web applications need
it. The plugin package cannot supply JavaScript, does not receive the `WKWebView`,
and has no native message bridge. SideCord injects optional validated CSS using
its own generated top-level script. Top-level navigation and popups are limited
to declared HTTPS hosts. User-clicked external links open in the default
browser, while programmatic external navigation and downloads are rejected.

## Browser profiles and lifecycle

Each web panel receives a stable browser-profile identifier derived from its
plugin and contribution identifiers. Persistent profiles keep their own cookies,
cache, and local data and are never shared with Discord or another plugin.
Updates reuse the profile; normal disable or uninstall does not silently delete
the session.

Enabling creates the host-managed web view and loads the declared initial URL.
Retracting SideCord retains the view and session without reloading. Audio pauses
while hidden unless the declared background-audio permission was explicitly
approved. Disabling stops playback and destroys the runtime while retaining
website data. Settings provide visibility, height, reload, open-in-browser,
background-audio, and clear-data controls. Uninstall offers a separate choice to
delete the isolated website data.

The Discord card and bottom web-panel card live inside the same transparent
SideCord panel. Their combined height never changes the outer window, so reveal,
retract, screen selection, pinning, fullscreen behavior, and window ordering
remain synchronized.

## Schema v3 document layouts

Schema v3 web panels may add `documentLayouts`. Each layout targets one exact
host already present in `allowedNavigationHosts`, names a `mountSelector`, and
declares up to eight ordered slots. A slot has a lowercase identifier, up to
eight conservative selectors, a `selection` of `first` or `firstVisible`, and
an optional `strategy` of `move` (the default) or `preserve`.

```json
"documentLayouts": [{
  "host": "music.youtube.com",
  "mountSelector": "ytmusic-app",
  "slots": [{
    "id": "player",
    "selectors": ["ytmusic-app-layout > ytmusic-player-bar"],
    "selection": "first",
    "strategy": "preserve"
  }]
}]
```

SideCord waits for every initial slot before activating the layout, creates
`#sidecord-plugin-layout`, and follows dynamic page replacements. `move` slots
move matched native elements into `[data-sidecord-slot]` containers without
cloning them, so the website's own event handlers remain attached. `preserve`
slots participate in readiness and reserve their ordered shell row, but the
matched element stays in its native parent. Use `preserve` for stateful web
components whose lifecycle depends on their original DOM ancestry.
The shell publishes `data-sidecord-width` (`narrow`, `regular`, or `wide`) and
`data-sidecord-height` (`compact`, `standard`, or `tall`) because plugin CSS
does not allow `@media` rules. It also exposes `--sidecord-panel-width` and
`--sidecord-panel-height`. Layouts run only in the top-level document on their
declared host and still cannot contain plugin-supplied JavaScript.

## Security guarantees

- Plugins cannot execute native code or plugin-supplied JavaScript.
- Network access is performed only by host-managed web panels.
- Top-level navigation is restricted to declared exact HTTPS hosts, all shown
  before enabling.
- Browser data is isolated by plugin and never shared with Discord.
- No native bridge is exposed to remote content.
- Marketplace signing and SHA-256 package verification remain unchanged.

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
