# SideCord privacy

SideCord loads Discord in Apple's `WKWebView` using WebKit's persistent website
data store. Discord credentials, cookies, and local storage remain inside that
store. SideCord does not inspect, export, synchronize, or log authentication
tokens.

Preferences and custom CSS are stored locally in macOS user defaults. Custom CSS
is injected only into top-level Discord pages. SideCord rejects CSS syntax that
can load remote resources. User-clicked links to other websites open in the
default browser.

SideCord adds a local settings category to Discord's settings interface. That
bridge receives only SideCord preference values and posts back allow-listed,
type-checked preference changes. It does not read Discord settings, messages,
channels, credentials, or account data.

When an incoming call is visibly ringing, SideCord reads only the caller or
group display name exposed by that call dialog and a transient UI identifier.
Those values are kept in memory only, are never written to preferences or files,
and are never logged. Answer and Decline are allow-listed actions scoped to the
visible call dialog; if either control cannot be identified unambiguously,
SideCord opens Discord instead of clicking an uncertain element.

Declarative plugin packages are stored in SideCord's sandboxed Application
Support container. Plugins cannot execute code, inspect Discord content, access
files, or initiate network requests. Release-configured marketplace catalogs are
verified with an embedded Ed25519 public key, and downloaded packages are checked
against the catalog's SHA-256 hash before installation. Local packages require
an explicit warning and are still schema- and capability-validated.

SideCord has no analytics or telemetry.
