# SideCord privacy

SideCord loads Discord in Apple's `WKWebView` using WebKit's persistent website
data store. Discord credentials, cookies, and local storage remain inside that
store. SideCord does not inspect, export, synchronize, or log authentication
tokens.

Preferences and custom CSS are stored locally in macOS user defaults. Custom CSS
is injected only into top-level Discord pages. SideCord rejects CSS syntax that
can load remote resources. User-clicked links to other websites open in the
default browser.

SideCord has no analytics or telemetry.
