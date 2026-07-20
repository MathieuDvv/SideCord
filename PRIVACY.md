# SideCord privacy

SideCord has no analytics or telemetry. Both platform implementations load
Discord in a persistent, platform-managed browser profile so signing in once
does not require signing in again whenever the sidebar retracts.

## Discord sessions

- **macOS** uses WebKit's persistent website data store.
- **Windows** uses an Electron Chromium partition in SideCord's per-user
  application-data directory.

Discord credentials, cookies, cache, and local storage remain in those browser
profiles. SideCord does not inspect, export, synchronize, or log authentication
tokens. User-clicked links to unrelated websites open in the default browser.

## Preferences and settings integration

macOS preferences are stored in user defaults. Windows preferences and local
custom CSS are stored in `settings.json` in SideCord's application-data
directory. Custom CSS is injected only into top-level Discord pages and syntax
capable of loading remote resources is rejected.

SideCord adds local categories to Discord's settings interface. The bridge
receives only SideCord preference values and sends back allow-listed,
type-checked preference changes. It does not read Discord settings, messages,
channels, credentials, or account data.

## Server rail and attention state

The optional detached server rail reads the server identifier, visible name,
icon, selection state, unread state, and mention count already present in
Discord's navigation. That bounded metadata stays in memory and is never logged
or transmitted by SideCord. The rail does not read messages or channel names.

Ordinary notification attention is reduced to a boolean event used only to
display the local edge glow. It is never persisted.

On macOS, when an incoming call is visibly ringing, SideCord additionally reads
the display name and a transient UI identifier exposed by the call dialog. They
remain in memory and are never logged. Answer and Decline actions are restricted
to unambiguously matched controls; otherwise SideCord opens the call interface.

## Plugins on macOS

Declarative plugin packages are stored in SideCord's sandboxed Application
Support container. Plugins cannot execute native code or plugin-supplied
JavaScript, inspect Discord content, or access arbitrary files.

A plugin web panel may load declared HTTPS sites in a SideCord-owned WebKit
profile isolated from Discord and every other plugin. SideCord displays declared
hosts before enabling, restricts navigation to exact allowed hosts, exposes no
native message bridge, and rejects downloads. Persistent panel data and
background audio require declared permissions and user approval.

Release-configured marketplace catalogs are verified with an embedded Ed25519
public key. Downloaded packages are checked against their catalog SHA-256 hash
before installation. Local packages still pass schema, capability, hostname,
permission, and CSS validation.

## Camera and microphone

Camera and microphone access is considered only for HTTPS Discord origins and
remains subject to macOS or Windows privacy controls. Authentication popups are
isolated from SideCord's native bridge and restricted to Discord and a narrow
allow-list of identity-provider entry points.
