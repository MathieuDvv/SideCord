# SideCord privacy

SideCord loads Discord in a persistent Chromium session managed by Electron.
Discord credentials, cookies, cache, and local storage remain in SideCord's
per-user application-data directory. SideCord does not inspect, export,
synchronize, or log authentication tokens.

Preferences and custom CSS are stored locally in `settings.json` under the same
application-data directory. Custom CSS is injected only into top-level Discord
pages. SideCord rejects CSS syntax that can load remote resources. Unrelated
HTTPS links open in the default browser; insecure and unsupported navigation is
blocked.

The isolated preload creates SideCord's controls and settings UI. It receives
only SideCord preference values and sends back allow-listed desktop actions and
validated preference changes. To render the optional detached server rail, it
reads the visible server name, icon, selection state, unread state, and mention
count already present in Discord's navigation. That data stays in memory and is
never logged or transmitted by SideCord. It does not collect Discord messages,
channel names, credentials, or account data.

Notification attention is reduced to a boolean event. SideCord also checks
whether Discord visibly exposes an incoming-call dialog, but does not read or
store the caller name or call contents. Attention events are used only to show
the local edge glow and are never persisted.

Camera and microphone access is accepted only for HTTPS Discord origins and is
still subject to Windows privacy controls. Authentication popups are isolated,
have no Node.js integration or native SideCord bridge, and may begin only at a
small allow-list of Discord and identity-provider OAuth endpoints.

SideCord has no analytics or telemetry.
