import Foundation

struct DiscordCSSRuntimeConfiguration: Encodable, Equatable, Sendable {
    let navigationPresentation: String
    let composerMode: String
    let requestedColorScheme: String
    let rootAttributes: [String: String]
    let rootVariables: [String: String]
}

/// Creates the trusted CSS and self-healing JavaScript injected into Discord pages.
enum DiscordCSSComposer {
    static let styleElementID = "sidecord-injected-css"
    static let runtimeKey = "__sidecordWebRuntime_v3__"
    static let notificationBridgeKey = "__sidecordNotificationBridge_v2__"
    static let messageHandlerName = "sidecordRuntime"

    static let managedConfigurationAttributeNames = [
        "data-sidecord-navigation",
        "data-sidecord-composer",
        "data-sidecord-theme",
        "data-sidecord-accent",
        "data-sidecord-color-scheme",
        "data-sidecord-theme-intensity",
        "data-sidecord-hide-members",
        "data-sidecord-hide-account-dock",
        "data-sidecord-simplify-header",
        "data-sidecord-compact-media",
        "data-sidecord-reduce-motion"
    ]

    static let managedRuntimeAttributeNames = [
        "data-sidecord-drawer-open",
        "data-sidecord-resolved-color-scheme"
    ]

    static let managedRootAttributeNames =
        managedConfigurationAttributeNames + managedRuntimeAttributeNames

    static let managedConfigurationVariableNames = [
        "--sidecord-theme-intensity",
        "--sidecord-theme-strength",
        "--sidecord-accent-color",
        "--sidecord-accent-rgb"
    ]

    static let managedRootVariableNames =
        managedConfigurationVariableNames + ["--sidecord-account-dock-height"]

    static func compose(
        preset: CSSPreset,
        compactPresetCSS: String,
        layoutModifiersCSS: String = "",
        visualThemesCSS: String = "",
        layoutOptions: DiscordLayoutOptions = .full,
        customCSS: String,
        customCSSEnabled: Bool
    ) -> String {
        var sections: [String] = []

        if preset == .compact {
            append(compactPresetCSS, to: &sections)
        }

        // Both sheets are trusted, attribute-scoped, and fail open. Keeping them
        // present makes a runtime mode change an atomic attribute update.
        append(layoutModifiersCSS, to: &sections)
        append(visualThemesCSS, to: &sections)

        // User CSS is intentionally last so an explicit user rule can override
        // every curated visual choice.
        if customCSSEnabled {
            append(sanitizeCustomCSS(customCSS), to: &sections)
        }

        return sections.joined(separator: "\n\n")
    }

    static func runtimeConfiguration(
        layoutOptions: DiscordLayoutOptions,
        visualTheme: DiscordVisualTheme,
        themeAccent: SideCordAccent,
        themeIntensity: Double,
        themeColorScheme: ThemeColorScheme
    ) -> DiscordCSSRuntimeConfiguration {
        let intensity = min(max(themeIntensity.isFinite ? themeIntensity : 1, 0), 1)
        let intensityString = decimalString(intensity)
        let strengthString = decimalString(intensity * 100) + "%"
        let accent = accentValues(for: themeAccent)

        var attributes = [
            "data-sidecord-navigation": navigationValue(layoutOptions.navigationPresentation),
            "data-sidecord-composer": composerValue(layoutOptions.composerMode),
            "data-sidecord-theme": themeValue(visualTheme),
            "data-sidecord-accent": accentValue(themeAccent),
            "data-sidecord-color-scheme": colorSchemeValue(themeColorScheme),
            "data-sidecord-theme-intensity": intensityString
        ]

        if layoutOptions.hideMemberList {
            attributes["data-sidecord-hide-members"] = ""
        }
        if layoutOptions.hideAccountDock {
            attributes["data-sidecord-hide-account-dock"] = ""
        }
        if layoutOptions.simplifyHeader {
            attributes["data-sidecord-simplify-header"] = ""
        }
        if layoutOptions.compactMedia {
            attributes["data-sidecord-compact-media"] = ""
        }
        if layoutOptions.reduceMotion {
            attributes["data-sidecord-reduce-motion"] = ""
        }

        return DiscordCSSRuntimeConfiguration(
            navigationPresentation: navigationValue(layoutOptions.navigationPresentation),
            composerMode: composerValue(layoutOptions.composerMode),
            requestedColorScheme: colorSchemeValue(themeColorScheme),
            rootAttributes: attributes,
            rootVariables: [
                "--sidecord-theme-intensity": intensityString,
                "--sidecord-theme-strength": strengthString,
                "--sidecord-accent-color": accent.color,
                "--sidecord-accent-rgb": accent.rgb
            ]
        )
    }

    /// SideCord accepts a deliberately conservative CSS subset. Network-capable
    /// constructs and CSS escape sequences reject the entire custom sheet; this
    /// avoids regex rewriting that can be bypassed with escaped identifiers.
    static func sanitizeCustomCSS(_ css: String) -> String {
        guard validationError(for: css) == nil else {
            return "/* SideCord blocked custom CSS containing network-capable syntax. */"
        }
        return css
    }

    static func validationError(for css: String) -> String? {
        let lowercased = css.lowercased()
        let forbiddenFragments = [
            "@", "\\", "/*", "://", "//", "data:", "file:", "blob:"
        ]

        let networkFunctionPattern = #"(?i)(^|[^a-z0-9_-])(url|image|image-set|-webkit-image-set|src)\s*\("#
        if forbiddenFragments.contains(where: lowercased.contains)
            || lowercased.range(of: networkFunctionPattern, options: .regularExpression) != nil {
            return "Remote resources, @-rules, comments, URLs, and CSS escape sequences aren’t allowed."
        }
        return nil
    }

    static func userScriptSource(
        css: String,
        configuration: DiscordCSSRuntimeConfiguration
    ) -> String {
        let encodedCSS = javascriptLiteral(css, fallback: "\"\"")
        let encodedConfiguration = javascriptLiteral(configuration, fallback: "{}")
        let encodedManagedAttributes = javascriptLiteral(managedRootAttributeNames, fallback: "[]")
        let encodedManagedVariables = javascriptLiteral(managedRootVariableNames, fallback: "[]")
        let encodedMessageHandlerName = javascriptLiteral(messageHandlerName, fallback: "\"\"")
        let encodedNotificationBridgeKey = javascriptLiteral(
            notificationBridgeKey,
            fallback: "\"\""
        )

        return """
        (() => {
          const host = window.location.hostname.toLowerCase().replace(/\\.+$/, "");
          const isDiscordHost = host === "discord.com" ||
            host.endsWith(".discord.com") ||
            host === "discordapp.com" ||
            host.endsWith(".discordapp.com");
          if (window.location.protocol !== "https:" || !isDiscordHost) return;

          const runtimeKey = "\(runtimeKey)";
          const styleID = "\(styleElementID)";
          const nextCSS = \(encodedCSS);
          const nextConfiguration = \(encodedConfiguration);
          const managedAttributes = \(encodedManagedAttributes);
          const managedVariables = \(encodedManagedVariables);
          const messageHandlerName = \(encodedMessageHandlerName);
          const notificationBridgeKey = \(encodedNotificationBridgeKey);
          const previousRuntime = window[runtimeKey];

          if (previousRuntime && previousRuntime.version === 6 &&
              typeof previousRuntime.update === "function") {
            previousRuntime.update(nextCSS, nextConfiguration);
            return;
          }
          if (previousRuntime && typeof previousRuntime.dispose === "function") {
            previousRuntime.dispose();
          }

          const tokenSelector = name =>
            `[class^="${name}_"], [class*=" ${name}_"]`;
          const messageSelector =
            `[id^="chat-messages-"], ` +
              `[data-list-item-id^="chat-messages___"]`;
          const messageTimelineSelector =
            `[data-list-id="chat-messages"], ` +
              `[role="log"][aria-label*="messages" i], ` +
              `ol[aria-label*="messages" i]`;
          const incomingCallSelector =
            `${tokenSelector("ringingIncoming")}, ` +
              `${tokenSelector("incomingCall")}, ` +
              `[role="dialog"][aria-label*="incoming call" i], ` +
              `[aria-modal="true"][aria-label*="incoming call" i]`;
          const safeQuery = (root, selector) => {
            try { return root ? root.querySelector(selector) : null; }
            catch (_) { return null; }
          };
          const safeQueryAll = (root, selector) => {
            try { return root ? [...root.querySelectorAll(selector)] : []; }
            catch (_) { return []; }
          };

          const state = {
            version: 6,
            css: nextCSS,
            configuration: nextConfiguration,
            drawerOpen: false,
            disposed: false,
            reconcileScheduled: false,
            frameRequest: 0,
            fallbackTimer: 0,
            railReportTimer: 0,
            lastRailPayload: "",
            incomingCallActive: false,
            messageScanTimer: 0,
            messageArmTimer: 0,
            messageTrackingArmed: false,
            messageBaselineSignature: "",
            messageContext: "",
            messageLastKey: null,
            messageMaxSnowflake: null,
            messageKnownKeys: new Set(),
            railElements: new Map(),
            observedRoot: null,
            observedAccountDock: null,
            observedChannelList: null,
            roleElements: Object.create(null),
            themeScopeElements: new Set(),
            observer: null,
            dockResizeObserver: null,
            mediaQuery: window.matchMedia("(prefers-color-scheme: dark)"),
            update: null,
            dispose: null,
            openDrawer: null,
            closeDrawer: null,
            toggleDrawer: null,
            activateRailItem: null
          };

          const currentRoot = () => document.documentElement;
          const currentStyle = () => document.getElementById(styleID);
          const postRuntimeMessage = payload => {
            try {
              window.webkit?.messageHandlers?.[messageHandlerName]?.postMessage(payload);
            } catch (_) {}
          };
          const reportDrawerState = open => postRuntimeMessage({
            type: "drawer",
            open: !!open
          });
          const reportIncomingCallState = active => {
            const nextActive = !!active;
            if (state.incomingCallActive === nextActive) return;
            state.incomingCallActive = nextActive;
            postRuntimeMessage({ type: "incomingCall", active: nextActive });
          };
          const reportMessageActivity = () => postRuntimeMessage({
            type: "notification"
          });

          const resolvedColorScheme = () => {
            const requested = state.configuration.requestedColorScheme;
            if (requested === "dark" || requested === "light") return requested;
            return state.mediaQuery.matches ? "dark" : "light";
          };

          const shouldOverrideDiscordTheme = () => {
            const requested = state.configuration.requestedColorScheme;
            const theme = state.configuration.rootAttributes?.["data-sidecord-theme"];
            // Discord + System is the one deliberately native combination.
            // Curated themes follow the Mac appearance, while an explicit
            // Light/Dark choice always wins over the Discord account setting.
            return requested !== "system" || theme !== "discord";
          };

          const synchronizeThemeScopes = (root, scheme) => {
            const nextScopes = new Set([
              root,
              document.body,
              document.getElementById("app-mount"),
              ...safeQueryAll(
                document,
                ".theme-dark, .theme-light, .theme-darker, .theme-midnight, [data-theme]"
              )
            ].filter(Boolean));
            for (const element of state.themeScopeElements) {
              if (!nextScopes.has(element) || !element.isConnected) {
                element.removeAttribute("data-sidecord-theme-scope");
              }
            }
            for (const element of nextScopes) {
              if (element.getAttribute("data-sidecord-theme-scope") !== scheme) {
                element.setAttribute("data-sidecord-theme-scope", scheme);
              }
            }
            state.themeScopeElements = nextScopes;
          };

          const clearThemeScopes = () => {
            for (const element of state.themeScopeElements) {
              element.removeAttribute("data-sidecord-theme-scope");
            }
            for (const element of safeQueryAll(document, "[data-sidecord-theme-scope]")) {
              element.removeAttribute("data-sidecord-theme-scope");
            }
            state.themeScopeElements.clear();
          };

          const synchronizeDiscordTheme = root => {
            if (!shouldOverrideDiscordTheme()) {
              clearThemeScopes();
              return;
            }
            const scheme = resolvedColorScheme();
            // Apply SideCord's semantic variables directly on every theme host.
            // Discord keeps ownership of its account classes/data-theme values,
            // so changing a theme while SideCord is active is never overwritten
            // or restored to a stale snapshot.
            synchronizeThemeScopes(root, scheme);
          };

          const setUniqueRole = (role, element) => {
            const previous = state.roleElements[role] || null;
            if (previous === element &&
                (!element || (element.isConnected &&
                  element.getAttribute("data-sidecord-role") === role))) {
              return element;
            }
            for (const oldElement of safeQueryAll(
              document,
              `[data-sidecord-role="${role}"]`
            )) {
              if (oldElement !== element) oldElement.removeAttribute("data-sidecord-role");
            }
            if (previous && previous !== element) {
              previous.removeAttribute("data-sidecord-role");
            }
            if (element) element.setAttribute("data-sidecord-role", role);
            state.roleElements[role] = element || null;
            return element;
          };

          const resolveRole = (role, finder) => {
            const current = state.roleElements[role] || null;
            if (current?.isConnected &&
                current.getAttribute("data-sidecord-role") === role) {
              return current;
            }
            return setUniqueRole(role, finder());
          };

          const findGuildRail = () => safeQuery(
            document,
            `${tokenSelector("guilds")}, nav:has([data-list-id="guildsnav"]), ` +
              `nav[aria-label*="Servers" i]`
          );

          const findChannelList = () => {
            let element = safeQuery(document, tokenSelector("sidebarList"));
            if (element) return element;
            element = safeQuery(
              document,
              `[class^="sidebar_"]:has([data-list-id^="channels"]), ` +
                `[class*=" sidebar_"]:has([data-list-id^="channels"]), ` +
                `[class^="sidebar_"]:has([data-list-id^="private-channels"]), ` +
                `[class*=" sidebar_"]:has([data-list-id^="private-channels"])`
            );
            if (element) return element;
            const navigation = safeQuery(
              document,
              `nav[aria-label*="Channels" i], nav[aria-label*="Direct Messages" i]`
            );
            return navigation?.closest(
              `${tokenSelector("sidebarList")}, ${tokenSelector("sidebar")}`
            ) || navigation;
          };

          const findAccountDock = () => safeQuery(document, tokenSelector("panels"));
          const findComposer = () => safeQuery(document, tokenSelector("channelTextArea"));

          const safeClassName = element =>
            typeof element?.className === "string" ? element.className : "";
          const isVisiblyPresented = element => {
            if (!element?.isConnected) return false;
            for (let node = element; node; node = node.parentElement) {
              if (node.hidden || node.getAttribute?.("aria-hidden") === "true") {
                return false;
              }
              const style = getComputedStyle(node);
              if (style.display === "none" || style.visibility === "hidden" ||
                  Number(style.opacity) === 0) return false;
            }
            const bounds = element.getBoundingClientRect();
            if (bounds.width <= 0 || bounds.height <= 0) return false;
            if (window.innerWidth <= 0 || window.innerHeight <= 0) return true;
            return bounds.bottom > 0 && bounds.right > 0 &&
              bounds.top < window.innerHeight && bounds.left < window.innerWidth;
          };
          const hasVisibleIncomingCall = () => safeQueryAll(
            document,
            incomingCallSelector
          ).some(isVisiblyPresented);
          const currentChannelIsMuted = () => {
            const selected = safeQuery(
              document,
              `[data-list-item-id^="channels___"][aria-selected="true"], ` +
                `[data-list-item-id^="private-channels-"][aria-selected="true"], ` +
                `a[aria-current="page"][href*="/channels/"]`
            );
            if (!selected) return false;
            const row = selected.closest(
              `${tokenSelector("containerDefault")}, ` +
                `${tokenSelector("channel")}, li`
            ) || selected;
            const stateText = `${safeClassName(row)} ` +
              `${row.getAttribute("aria-label") || ""}`;
            return /(^|\\s)(?:modeMuted|muted)_/i.test(stateText) ||
              /\\bmuted\\b/i.test(stateText) ||
              !!safeQuery(row, `${tokenSelector("modeMuted")}, ${tokenSelector("muted")}`);
          };
          const messageHasNotificationSemantic = descriptor => {
            const element = descriptor?.element;
            return !!element && (
              element.matches?.(tokenSelector("mentioned")) ||
              !!safeQuery(element, tokenSelector("mentioned"))
            );
          };
          const timelineFallbackIsAllowed = descriptors => {
            const notificationBridge = window[notificationBridgeKey];
            if (notificationBridge && notificationBridge.enabled !== true) {
              return false;
            }
            const bridgeCapturesPageNotifications =
              notificationBridge?.enabled === true &&
              notificationBridge?.capturesPageNotifications === true &&
              window.Notification === notificationBridge?.notificationProxy;
            return !bridgeCapturesPageNotifications &&
              !currentChannelIsMuted() &&
              descriptors.some(messageHasNotificationSemantic);
          };
          const normalizedSnowflake = value => {
            const digits = String(value || "").replace(/^0+/, "");
            return digits || "0";
          };
          const compareSnowflakes = (left, right) => {
            const a = normalizedSnowflake(left);
            const b = normalizedSnowflake(right);
            if (a.length !== b.length) return a.length < b.length ? -1 : 1;
            return a === b ? 0 : (a < b ? -1 : 1);
          };
          const messageDescriptor = element => {
            const elementID = element?.getAttribute?.("id") || "";
            const listID = element?.getAttribute?.("data-list-item-id") || "";
            const match = elementID.match(/^chat-messages-(\\d+)-(\\d+)$/) ||
              listID.match(/^chat-messages___(\\d+)_(\\d+)$/);
            if (!match) return null;
            return {
              key: `${match[1]}:${match[2]}`,
              channel: match[1],
              snowflake: normalizedSnowflake(match[2]),
              element
            };
          };
          const findMessageTimeline = () => {
            const explicit = safeQuery(document, messageTimelineSelector);
            if (explicit) return explicit;
            const message = safeQuery(document, messageSelector);
            return message?.parentElement || null;
          };
          const collectMessageSnapshot = () => {
            const timeline = findMessageTimeline();
            const descriptors = [];
            const seen = new Set();
            for (const element of safeQueryAll(timeline, messageSelector)) {
              const descriptor = messageDescriptor(element);
              if (!descriptor || seen.has(descriptor.key)) continue;
              seen.add(descriptor.key);
              descriptors.push(descriptor);
              if (descriptors.length >= 500) break;
            }
            const last = descriptors[descriptors.length - 1] || null;
            const pathContext = location.pathname.match(
              /\\/channels\\/(?:@me|\\d+)\\/(\\d+)/
            )?.[1] || location.pathname;
            return {
              timeline,
              descriptors,
              context: last?.channel || pathContext,
              last
            };
          };
          const messageSnapshotSignature = snapshot =>
            `${snapshot.context}|${snapshot.descriptors.map(item => item.key).join(",")}`;
          const rememberMessageSnapshot = (snapshot, resetKnown) => {
            if (resetKnown) {
              state.messageKnownKeys.clear();
              state.messageMaxSnowflake = null;
            }
            for (const descriptor of snapshot.descriptors) {
              state.messageKnownKeys.add(descriptor.key);
              if (!state.messageMaxSnowflake || compareSnowflakes(
                descriptor.snowflake,
                state.messageMaxSnowflake
              ) > 0) {
                state.messageMaxSnowflake = descriptor.snowflake;
              }
            }
            // The live timeline is virtualized. Keep recent identities for
            // rerenders, while the greatest snowflake remains the authoritative
            // guard against older history becoming attention.
            if (state.messageKnownKeys.size > 1_000) {
              state.messageKnownKeys = new Set(
                snapshot.descriptors.slice(-500).map(item => item.key)
              );
            }
            state.messageContext = snapshot.context;
            state.messageLastKey = snapshot.last?.key || null;
          };
          const beginMessageBaseline = snapshot => {
            if (state.messageArmTimer) clearTimeout(state.messageArmTimer);
            state.messageTrackingArmed = false;
            state.messageBaselineSignature = messageSnapshotSignature(snapshot);
            rememberMessageSnapshot(snapshot, true);
            if (!snapshot.timeline) {
              state.messageArmTimer = 0;
              return;
            }
            // Discord hydrates the current channel and can then prepend cached
            // history. Wait for a quiet baseline before treating appended IDs as
            // live activity, so opening SideCord never replays old messages.
            state.messageArmTimer = setTimeout(() => {
              state.messageArmTimer = 0;
              if (state.disposed) return;
              const latest = collectMessageSnapshot();
              const signature = messageSnapshotSignature(latest);
              if (!latest.timeline || signature !== state.messageBaselineSignature) {
                beginMessageBaseline(latest);
                return;
              }
              rememberMessageSnapshot(latest, true);
              state.messageTrackingArmed = true;
            }, 2_000);
          };
          const scanMessageActivity = () => {
            if (state.disposed) return;
            const snapshot = collectMessageSnapshot();
            const signature = messageSnapshotSignature(snapshot);

            if (!state.messageTrackingArmed) {
              if (signature !== state.messageBaselineSignature ||
                  (!state.messageArmTimer && snapshot.timeline)) {
                beginMessageBaseline(snapshot);
              }
              return;
            }

            if (!snapshot.timeline || snapshot.context !== state.messageContext) {
              beginMessageBaseline(snapshot);
              return;
            }

            const previousLastIndex = state.messageLastKey
              ? snapshot.descriptors.findIndex(item => item.key === state.messageLastKey)
              : -1;
            const appendedKeys = new Set(
              previousLastIndex >= 0
                ? snapshot.descriptors
                    .slice(previousLastIndex + 1)
                    .map(item => item.key)
                : []
            );
            const newActivity = snapshot.descriptors.filter(item =>
              !state.messageKnownKeys.has(item.key) && (
                appendedKeys.has(item.key) ||
                !state.messageMaxSnowflake ||
                compareSnowflakes(item.snowflake, state.messageMaxSnowflake) > 0
              )
            );

            rememberMessageSnapshot(snapshot, false);
            state.messageBaselineSignature = signature;
            if (newActivity.length && timelineFallbackIsAllowed(newActivity)) {
              reportMessageActivity();
            }
          };
          const scheduleMessageScan = () => {
            if (state.disposed || state.messageScanTimer) return;
            state.messageScanTimer = setTimeout(() => {
              state.messageScanTimer = 0;
              scanMessageActivity();
            }, 60);
          };
          const trimmedLabel = value => String(value || "")
            .replace(/\\s+/g, " ")
            .trim()
            .slice(0, 120);
          const safeIconSource = element => {
            const image = safeQuery(element, "img[src]");
            const source = image?.currentSrc || image?.getAttribute("src") || "";
            if (!source || source.length > 262144) return null;
            if (/^https:\\/\\//i.test(source) ||
                /^data:image\\/(png|jpeg|webp|gif);base64,/i.test(source)) {
              return source;
            }
            return null;
          };

          const railDescriptor = candidate => {
            const listItem = candidate.closest("[data-list-item-id]") || candidate;
            const listID = listItem.getAttribute("data-list-item-id") || "";
            const anchor = candidate.closest("a[href]") || safeQuery(candidate, "a[href]");
            const href = anchor?.getAttribute("href") || "";
            let id = null;
            let kind = null;

            if (listID === "guildsnav___home" || /\\/channels\\/@me(?:\\/|$)/.test(href)) {
              id = "direct-messages";
              kind = "directMessages";
            } else {
              const guildID = listID.match(/^guildsnav___(\\d+)$/)?.[1] ||
                href.match(/\\/channels\\/(\\d+)(?:\\/|$)/)?.[1];
              if (guildID) {
                id = `server:${guildID}`;
                kind = "server";
              } else if (listID === "guildsnav___create-join-button") {
                id = "action:create-server";
                kind = "action";
              } else if (listID === "guildsnav___guild-discover-button") {
                id = "action:discover-servers";
                kind = "action";
              }
            }
            if (!id || !kind) return null;

            const element = listItem.matches("a, button, [role='button'], [role='treeitem']")
              ? listItem
              : anchor || candidate;
            const label = trimmedLabel(
              element.getAttribute("data-dnd-name") ||
              element.getAttribute("aria-label") ||
              safeQuery(element, "img[alt]")?.getAttribute("alt") ||
              element.textContent
            );
            const selected = element.getAttribute("aria-selected") === "true" ||
              element.getAttribute("aria-current") === "page" ||
              /(^|\\s)selected[_-]/i.test(safeClassName(element)) ||
              !!safeQuery(element, tokenSelector("selected"));
            const unread = /unread|mention/i.test(
              `${safeClassName(element)} ${element.getAttribute("aria-label") || ""}`
            ) || !!safeQuery(
              element,
              `${tokenSelector("unread")}, ${tokenSelector("numberBadge")}, ` +
                `[aria-label*="unread" i], [aria-label*="mention" i]`
            );
            const badge = safeQuery(
              element,
              `${tokenSelector("numberBadge")}, [aria-label*="mention" i]`
            );
            const mentionMatch = `${badge?.textContent || ""} ` +
              `${badge?.getAttribute("aria-label") || ""}`;
            const mentionValue = mentionMatch.match(/\\d+/)?.[0];
            const mentionCount = mentionValue
              ? Math.min(9999, Math.max(1, Number(mentionValue)))
              : null;

            return {
              item: {
                id,
                title: label || (kind === "directMessages" ? "Direct Messages" : "Discord"),
                icon: safeIconSource(element),
                kind,
                selected,
                unread,
                mentions: Number.isFinite(mentionCount) ? mentionCount : null
              },
              element
            };
          };

          const collectRailItems = guildRail => {
            const nextElements = new Map();
            const items = [];
            const candidates = safeQueryAll(
              guildRail,
              `[data-list-item-id^="guildsnav___"], a[href*="/channels/"]`
            );
            for (const candidate of candidates) {
              const descriptor = railDescriptor(candidate);
              if (!descriptor || nextElements.has(descriptor.item.id)) continue;
              nextElements.set(descriptor.item.id, descriptor.element);
              items.push(descriptor.item);
              if (items.length >= 200) break;
            }
            state.railElements = nextElements;
            return items;
          };

          const scheduleRailReport = guildRail => {
            if (state.railReportTimer) return;
            state.railReportTimer = setTimeout(() => {
              state.railReportTimer = 0;
              if (state.disposed) return;
              const items = collectRailItems(
                state.roleElements["guild-rail"]?.isConnected
                  ? state.roleElements["guild-rail"]
                  : guildRail
              );
              const serialized = JSON.stringify(items);
              if (serialized === state.lastRailPayload) return;
              state.lastRailPayload = serialized;
              postRuntimeMessage({ type: "rail", items });
            }, 80);
          };

          const setAccountDockHeight = height => {
            const root = currentRoot();
            if (!root) return;
            const roundedHeight = Math.max(0, Math.ceil(height || 0));
            if (roundedHeight > 0) {
              const value = `${roundedHeight}px`;
              if (root.style.getPropertyValue("--sidecord-account-dock-height") !== value) {
                root.style.setProperty("--sidecord-account-dock-height", value);
              }
            } else if (root.style.getPropertyValue("--sidecord-account-dock-height")) {
              root.style.removeProperty("--sidecord-account-dock-height");
            }
          };

          const bindAccountDockGeometry = (channelList, accountDock) => {
            const isSibling = !!accountDock &&
              (!channelList || !channelList.contains(accountDock));
            const nextAccountDock = isSibling ? accountDock : null;
            if (state.observedAccountDock === nextAccountDock &&
                state.observedChannelList === channelList) return;

            state.dockResizeObserver.disconnect();
            state.observedAccountDock = nextAccountDock;
            state.observedChannelList = channelList;
            if (!nextAccountDock) {
              setAccountDockHeight(0);
              return;
            }

            // One initial measurement covers browsers that defer their first
            // ResizeObserver delivery. Subsequent chat mutations do not reflow.
            setAccountDockHeight(nextAccountDock.getBoundingClientRect().height);
            state.dockResizeObserver.observe(nextAccountDock, { box: "border-box" });
          };

          const markComposerExtra = (composer, kind, selectors) => {
            for (const selector of selectors) {
              for (const match of safeQueryAll(composer, selector)) {
                const control = match.closest("button, [role='button']") || match;
                control.setAttribute("data-sidecord-composer-extra", kind);
              }
            }
          };

          const reconcileDiscordDOM = () => {
            const guildRail = resolveRole("guild-rail", findGuildRail);
            const channelList = resolveRole("channel-list", findChannelList);
            const accountDock = resolveRole("account-dock", findAccountDock);
            const previousComposer = state.roleElements["composer"] || null;
            const composer = resolveRole("composer", findComposer);
            scheduleRailReport(guildRail);
            scheduleMessageScan();
            reportIncomingCallState(hasVisibleIncomingCall());
            bindAccountDockGeometry(channelList, accountDock);

            for (const composerRoot of new Set([previousComposer, composer])) {
              for (const oldControl of safeQueryAll(
                composerRoot,
                "[data-sidecord-composer-extra]"
              )) {
                oldControl.removeAttribute("data-sidecord-composer-extra");
              }
            }
            if (!composer) return;

            markComposerExtra(composer, "gift", [
              "[data-list-item-id*='gift' i]",
              "[data-mana-component*='gift' i]",
              "button[aria-label*='gift' i]"
            ]);
            markComposerExtra(composer, "sticker", [
              "[data-list-item-id*='sticker' i]",
              "[data-mana-component*='sticker' i]",
              "button[aria-label*='sticker' i]"
            ]);
            markComposerExtra(composer, "apps", [
              tokenSelector("channelAppLauncher"),
              "[data-mana-component='channel-app-launcher']"
            ]);
          };

          const ensureStyle = root => {
            const container = document.head || root;
            let style = currentStyle();
            if (!state.css) {
              if (style) style.remove();
              return;
            }
            if (!style) {
              style = document.createElement("style");
              style.id = styleID;
            }
            if (style.parentNode !== container) container.appendChild(style);
            if (style.textContent !== state.css) style.textContent = state.css;
          };

          const ensureRootState = root => {
            const desired = state.configuration.rootAttributes || {};
            for (const name of managedAttributes) {
              if (name === "data-sidecord-drawer-open" ||
                  name === "data-sidecord-resolved-color-scheme") continue;
              if (Object.prototype.hasOwnProperty.call(desired, name)) {
                const value = name === "data-sidecord-navigation" &&
                  state.drawerOpen &&
                  state.configuration.navigationPresentation === "hidden"
                    ? "floating"
                    : String(desired[name]);
                if (root.getAttribute(name) !== value) root.setAttribute(name, value);
              } else if (root.hasAttribute(name)) {
                root.removeAttribute(name);
              }
            }

            const shouldShowDrawer =
              state.configuration.navigationPresentation !== "docked" &&
              state.drawerOpen;
            root.toggleAttribute("data-sidecord-drawer-open", shouldShowDrawer);
            const scheme = resolvedColorScheme();
            if (root.getAttribute("data-sidecord-resolved-color-scheme") !== scheme) {
              root.setAttribute("data-sidecord-resolved-color-scheme", scheme);
            }
            synchronizeDiscordTheme(root);

            const variables = state.configuration.rootVariables || {};
            for (const name of managedVariables) {
              if (name === "--sidecord-account-dock-height") continue;
              if (Object.prototype.hasOwnProperty.call(variables, name)) {
                const value = String(variables[name]);
                if (root.style.getPropertyValue(name) !== value) {
                  root.style.setProperty(name, value);
                }
              } else if (root.style.getPropertyValue(name)) {
                root.style.removeProperty(name);
              }
            }
          };

          const observeRoot = root => {
            if (state.observedRoot === root) return;
            state.observedRoot = root;
            state.observer.observe(root, {
              attributes: true,
              attributeFilter: [...managedAttributes, "style"]
            });
          };

          const reconcile = () => {
            if (state.disposed) return;
            const root = currentRoot();
            if (!root) return;
            observeRoot(root);
            ensureRootState(root);
            ensureStyle(root);
            reconcileDiscordDOM();
          };

          const scheduleReconcile = () => {
            if (state.disposed || state.reconcileScheduled) return;
            state.reconcileScheduled = true;
            const run = () => {
              if (!state.reconcileScheduled) return;
              state.reconcileScheduled = false;
              if (state.frameRequest) cancelAnimationFrame(state.frameRequest);
              if (state.fallbackTimer) clearTimeout(state.fallbackTimer);
              state.frameRequest = 0;
              state.fallbackTimer = 0;
              if (!state.disposed) reconcile();
            };
            state.frameRequest = requestAnimationFrame(run);
            // Hidden/background WebViews may suspend rAF. The bounded fallback
            // keeps styles self-healing while SideCord is retracted.
            state.fallbackTimer = setTimeout(run, 50);
          };

          state.dockResizeObserver = new ResizeObserver(entries => {
            const entry = entries.find(item => item.target === state.observedAccountDock);
            if (!entry) return;
            const borderBox = Array.isArray(entry.borderBoxSize)
              ? entry.borderBoxSize[0]
              : entry.borderBoxSize;
            setAccountDockHeight(borderBox?.blockSize || entry.contentRect.height);
          });

          state.openDrawer = () => {
            if (state.configuration.navigationPresentation === "docked") return;
            if (!state.drawerOpen) {
              state.drawerOpen = true;
              reconcile();
            }
            reportDrawerState(true);
          };
          state.closeDrawer = () => {
            if (state.drawerOpen) {
              state.drawerOpen = false;
              reconcile();
            }
            reportDrawerState(false);
          };
          state.toggleDrawer = () => {
            if (state.drawerOpen) state.closeDrawer();
            else state.openDrawer();
          };
          state.activateRailItem = id => {
            if (typeof id !== "string" || id.length > 128) return false;
            const element = state.railElements.get(id);
            if (!element?.isConnected || typeof element.click !== "function") return false;
            element.click();
            queueMicrotask(() => {
              scheduleRailReport(state.roleElements["guild-rail"] || null);
            });
            return true;
          };

          const elementFromEvent = event =>
            event.target && event.target.nodeType === Node.ELEMENT_NODE
              ? event.target
              : event.target?.parentElement;

          const onClick = event => {
            if (state.configuration.navigationPresentation === "docked") return;
            const target = elementFromEvent(event);
            if (!target) return;
            const guildRail = target.closest("[data-sidecord-role='guild-rail']");
            const guildDestination = target.closest("a[href*='/channels/'], [data-list-item-id]");
            const guildItemID = guildDestination?.getAttribute("data-list-item-id") || "";
            const isGuildDestination = !!guildDestination && (
              !!guildDestination.closest("a[href*='/channels/']") ||
              guildItemID === "guildsnav___home" ||
              /^guildsnav___\\d+$/.test(guildItemID)
            );
            if (guildRail && isGuildDestination) {
              queueMicrotask(() => state.openDrawer());
              return;
            }
            const channelList = target.closest("[data-sidecord-role='channel-list']");
            if (channelList && target.closest(
              "a[href*='/channels/'], [data-list-item-id^='channels___'], " +
                "[data-list-item-id^='private-channels-']"
            )) {
              queueMicrotask(() => state.closeDrawer());
            }
          };

          const onPointerDown = event => {
            if (!state.drawerOpen ||
                state.configuration.navigationPresentation === "docked") return;
            const target = elementFromEvent(event);
            if (!target) return;
            if (target.closest(
              "[data-sidecord-role='guild-rail'], " +
                "[data-sidecord-role='channel-list'], " +
                "[data-sidecord-role='account-dock']"
            )) return;
            state.closeDrawer();
          };

          const onKeyDown = event => {
            if (event.key === "Escape" && state.drawerOpen) state.closeDrawer();
          };
          const onColorSchemeChange = () => scheduleReconcile();

          const elementNode = node => node?.nodeType === Node.ELEMENT_NODE
            ? node
            : node?.parentElement || null;
          const mutationTouchesMessages = mutation => {
            if (mutation.type === "attributes") {
              const target = elementNode(mutation.target);
              return (mutation.attributeName === "id" ||
                  mutation.attributeName === "data-list-item-id") &&
                !!target?.matches?.(messageSelector);
            }
            if (mutation.type !== "childList") return false;
            return [...mutation.addedNodes, ...mutation.removedNodes].some(node => {
              const element = elementNode(node);
              return !!element && (
                element.matches?.(messageTimelineSelector) ||
                element.matches?.(messageSelector) ||
                !!safeQuery(element, messageTimelineSelector) ||
                !!safeQuery(element, messageSelector)
              );
            });
          };
          const mutationNeedsReconcile = mutation => {
            const target = elementNode(mutation.target);
            if (mutation.type === "attributes" &&
                mutation.attributeName === "style") {
              return !!target && (
                target.matches?.(incomingCallSelector) ||
                !!safeQuery(target, incomingCallSelector)
              );
            }
            // Reactions, embeds, typing transitions, and message edits are hot
            // DOM paths but cannot alter SideCord's roles, rail, or call state.
            // New top-level messages are scanned separately through their
            // added or removed message node.
            return !target?.closest?.(messageSelector);
          };

          document.addEventListener("click", onClick, false);
          document.addEventListener("pointerdown", onPointerDown, true);
          document.addEventListener("keydown", onKeyDown, true);
          state.mediaQuery.addEventListener("change", onColorSchemeChange);

          state.observer = new MutationObserver(mutations => {
            if (mutations.some(mutationTouchesMessages)) scheduleMessageScan();
            if (mutations.some(mutationNeedsReconcile)) scheduleReconcile();
          });
          state.observer.observe(document, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: [
              "aria-current",
              "aria-hidden",
              "aria-label",
              "aria-selected",
              "class",
              "data-list-item-id",
              "data-theme",
              "hidden",
              "id",
              "src",
              "style"
            ]
          });

          state.update = (updatedCSS, updatedConfiguration) => {
            const previousNavigation = state.configuration.navigationPresentation;
            state.css = updatedCSS;
            state.configuration = updatedConfiguration;
            if (previousNavigation !== state.configuration.navigationPresentation ||
                state.configuration.navigationPresentation === "docked") {
              state.drawerOpen = false;
            }
            reconcile();
            reportDrawerState(
              state.drawerOpen &&
                state.configuration.navigationPresentation !== "docked"
            );
          };

          state.dispose = () => {
            if (state.disposed) return;
            state.disposed = true;
            reportDrawerState(false);
            reportIncomingCallState(false);
            if (state.frameRequest) cancelAnimationFrame(state.frameRequest);
            if (state.fallbackTimer) clearTimeout(state.fallbackTimer);
            if (state.railReportTimer) clearTimeout(state.railReportTimer);
            if (state.messageScanTimer) clearTimeout(state.messageScanTimer);
            if (state.messageArmTimer) clearTimeout(state.messageArmTimer);
            state.observer.disconnect();
            state.dockResizeObserver.disconnect();
            state.mediaQuery.removeEventListener("change", onColorSchemeChange);
            document.removeEventListener("click", onClick, false);
            document.removeEventListener("pointerdown", onPointerDown, true);
            document.removeEventListener("keydown", onKeyDown, true);

            const root = currentRoot();
            if (root) {
              clearThemeScopes();
              for (const name of managedAttributes) root.removeAttribute(name);
              for (const name of managedVariables) root.style.removeProperty(name);
            }
            for (const element of safeQueryAll(
              document,
              "[data-sidecord-role], [data-sidecord-composer-extra]"
            )) {
              element.removeAttribute("data-sidecord-role");
              element.removeAttribute("data-sidecord-composer-extra");
            }
            state.railElements.clear();
            postRuntimeMessage({ type: "rail", items: [] });
            currentStyle()?.remove();
            if (window[runtimeKey] === state) delete window[runtimeKey];
          };

          window[runtimeKey] = state;
          reconcile();
          reportDrawerState(false);
        })();
        """
    }

    /// Runs before Discord's application bundle and lets SideCord's glow act as
    /// the notification surface when WebKit cannot grant HTML notification
    /// permission. Discord still decides which events qualify; notification
    /// arguments never leave the page.
    static func notificationBridgeUserScriptSource(isEnabled: Bool = true) -> String {
        let encodedMessageHandlerName = javascriptLiteral(
            messageHandlerName,
            fallback: "\"\""
        )
        let encodedEnabled = isEnabled ? "true" : "false"
        return """
        (() => {
          const host = window.location.hostname.toLowerCase().replace(/\\.+$/, "");
          const isDiscordHost = host === "discord.com" ||
            host.endsWith(".discord.com") ||
            host === "discordapp.com" ||
            host.endsWith(".discordapp.com");
          if (window.location.protocol !== "https:" || !isDiscordHost) return;

          const bridgeKey = "\(notificationBridgeKey)";
          const nextEnabled = \(encodedEnabled);
          const previousBridge = window[bridgeKey];
          if (previousBridge && typeof previousBridge.update === "function") {
            previousBridge.update(nextEnabled);
            return;
          }
          if (previousBridge) return;

          const messageHandlerName = \(encodedMessageHandlerName);
          const postNotificationEvent = () => {
            try {
              window.webkit?.messageHandlers?.[messageHandlerName]?.postMessage({
                type: "notification"
              });
            } catch (_) {}
          };

          const bridge = {
            originalNotification: null,
            notificationProxy: null,
            capturesPageNotifications: false,
            enabled: nextEnabled,
            usesVirtualPermission: false,
            originalPermission: "unavailable",
            serviceWorkerNotificationsBaselined: false,
            knownServiceWorkerNotificationsByScope: new Map(),
            serviceWorkerPollTimer: 0,
            refreshPermissionState: null,
            update(enabled) {
              this.enabled = enabled === true;
              this.refreshPermissionState?.();
            }
          };
          try {
            Object.defineProperty(window, bridgeKey, {
              configurable: false,
              enumerable: false,
              writable: false,
              value: bridge
            });
          } catch (_) {
            return;
          }

          const OriginalNotification = window.Notification;
          const NotificationTarget = typeof OriginalNotification === "function"
            ? OriginalNotification
            : function SideCordVirtualNotification() {};
          const refreshPermissionState = () => {
            let permission = "unavailable";
            try {
              if (typeof OriginalNotification?.permission === "string") {
                permission = OriginalNotification.permission;
              }
            } catch (_) {}
            bridge.originalPermission = permission;
            bridge.usesVirtualPermission = permission !== "granted";
          };
          bridge.refreshPermissionState = refreshPermissionState;
          refreshPermissionState();

          const virtualRequestPermission = callback => {
            const result = Promise.resolve("granted");
            if (typeof callback === "function") {
              result.then(permission => {
                try { callback(permission); } catch (_) {}
              });
            }
            return result;
          };
          const unavailableRequestPermission = callback => {
            const result = Promise.resolve("default");
            if (typeof callback === "function") {
              result.then(permission => {
                try { callback(permission); } catch (_) {}
              });
            }
            return result;
          };
          const createVirtualNotification = (target, argumentsList, newTarget) => {
            const title = String(argumentsList[0] ?? "");
            const options = argumentsList[1] && typeof argumentsList[1] === "object"
              ? argumentsList[1]
              : {};
            const prototype = newTarget?.prototype || target.prototype || Object.prototype;
            const instance = Object.create(prototype);
            const listeners = new Map();
            const vibrate = Object.freeze(
              options.vibrate == null
                ? []
                : Array.isArray(options.vibrate)
                  ? [...options.vibrate]
                  : [options.vibrate]
            );
            let closed = false;

            const emit = type => {
              const event = typeof Event === "function"
                ? new Event(type)
                : { type, defaultPrevented: false };
              const handler = instance[`on${type}`];
              if (typeof handler === "function") {
                try { handler.call(instance, event); } catch (_) {}
              }
              for (const listener of listeners.get(type) || []) {
                try { listener.call(instance, event); } catch (_) {}
              }
              return !event.defaultPrevented;
            };
            const defineValue = (value, writable = false) => ({
              configurable: true,
              enumerable: true,
              writable,
              value
            });
            Object.defineProperties(instance, {
              title: defineValue(title),
              dir: defineValue(options.dir || "auto"),
              lang: defineValue(options.lang || ""),
              body: defineValue(options.body || ""),
              navigate: defineValue(String(options.navigate ?? "")),
              tag: defineValue(options.tag || ""),
              icon: defineValue(options.icon || ""),
              badge: defineValue(options.badge || ""),
              image: defineValue(options.image || ""),
              vibrate: defineValue(vibrate),
              data: defineValue(options.data),
              timestamp: defineValue(Number(options.timestamp) || Date.now()),
              renotify: defineValue(!!options.renotify),
              silent: defineValue(options.silent == null ? null : !!options.silent),
              requireInteraction: defineValue(!!options.requireInteraction),
              actions: defineValue(Array.isArray(options.actions) ? options.actions : []),
              onclick: defineValue(null, true),
              onshow: defineValue(null, true),
              onerror: defineValue(null, true),
              onclose: defineValue(null, true),
              addEventListener: defineValue((type, listener) => {
                if (typeof listener !== "function") return;
                if (!listeners.has(type)) listeners.set(type, new Set());
                listeners.get(type).add(listener);
              }),
              removeEventListener: defineValue((type, listener) => {
                listeners.get(type)?.delete(listener);
              }),
              dispatchEvent: defineValue(event => emit(event?.type || "")),
              close: defineValue(() => {
                if (closed) return;
                closed = true;
                queueMicrotask(() => emit("close"));
              })
            });
            queueMicrotask(() => {
              if (!closed) emit("show");
            });
            return instance;
          };

          const NotificationProxy = new Proxy(NotificationTarget, {
            get(target, property, receiver) {
              refreshPermissionState();
              if (bridge.enabled && bridge.usesVirtualPermission &&
                  property === "permission") {
                return "granted";
              }
              if (bridge.enabled && bridge.usesVirtualPermission &&
                  property === "requestPermission") {
                return virtualRequestPermission;
              }
              if (typeof OriginalNotification !== "function" &&
                  property === "permission") {
                return "default";
              }
              if (typeof OriginalNotification !== "function" &&
                  property === "requestPermission") {
                return unavailableRequestPermission;
              }
              return Reflect.get(target, property, receiver);
            },
            has(target, property) {
              refreshPermissionState();
              if (bridge.enabled && bridge.usesVirtualPermission &&
                  (property === "permission" || property === "requestPermission")) {
                return true;
              }
              if (typeof OriginalNotification !== "function" &&
                  (property === "permission" || property === "requestPermission")) {
                return true;
              }
              return Reflect.has(target, property);
            },
            construct(target, argumentsList, newTarget) {
              refreshPermissionState();
              let instance;
              if (bridge.enabled && bridge.usesVirtualPermission) {
                instance = createVirtualNotification(target, argumentsList, newTarget);
              } else if (typeof OriginalNotification === "function") {
                instance = Reflect.construct(target, argumentsList, newTarget);
              } else {
                throw new DOMException(
                  "Notifications are unavailable",
                  "NotAllowedError"
                );
              }
              if (bridge.enabled) postNotificationEvent();
              return instance;
            }
          });
          try { window.Notification = NotificationProxy; } catch (_) {}
          if (window.Notification !== NotificationProxy) {
            try {
              Object.defineProperty(window, "Notification", {
                configurable: true,
                writable: true,
                value: NotificationProxy
              });
            } catch (_) {}
          }
          if (window.Notification === NotificationProxy) {
            bridge.originalNotification = typeof OriginalNotification === "function"
              ? OriginalNotification
              : null;
            bridge.notificationProxy = NotificationProxy;
            bridge.capturesPageNotifications = true;
          }

          const serviceWorkerNotificationKey = (notification, index) => {
            const tag = typeof notification?.tag === "string" ? notification.tag : "";
            const timestampValue = Number(notification?.timestamp);
            const timestamp = Number.isFinite(timestampValue) ? timestampValue : 0;
            if (tag || timestamp) return `${tag}:${timestamp}`;
            return `anonymous:${index}`;
          };
          const scheduleServiceWorkerPoll = () => {
            if (bridge.serviceWorkerPollTimer) return;
            bridge.serviceWorkerPollTimer = setTimeout(() => {
              bridge.serviceWorkerPollTimer = 0;
              pollServiceWorkerNotifications();
            }, 1_000);
          };
          const pollServiceWorkerNotifications = async () => {
            try {
              const getRegistrations = navigator.serviceWorker?.getRegistrations;
              if (typeof getRegistrations !== "function") return;
              const registrations = await getRegistrations.call(navigator.serviceWorker);
              const groups = await Promise.all(registrations.map(registration => {
                if (typeof registration?.getNotifications !== "function") return [];
                return Promise.resolve(registration.getNotifications()).catch(() => []);
              }));
              const previousByScope = bridge.knownServiceWorkerNotificationsByScope;
              const nextByScope = new Map();
              let hasNewNotification = false;
              groups.forEach((notifications, registrationIndex) => {
                const registration = registrations[registrationIndex];
                const scope = typeof registration?.scope === "string" && registration.scope
                  ? registration.scope
                  : `registration:${registrationIndex}`;
                const keys = new Set();
                notifications.forEach((notification, index) => {
                  keys.add(serviceWorkerNotificationKey(notification, index));
                });
                const previousKeys = previousByScope.get(scope);
                if (previousKeys && [...keys].some(key => !previousKeys.has(key))) {
                  hasNewNotification = true;
                }
                // A newly discovered registration receives its own quiet
                // baseline, so worker startup and registration reordering never
                // replay notifications that were already present.
                nextByScope.set(scope, keys);
              });
              bridge.knownServiceWorkerNotificationsByScope = nextByScope;
              bridge.serviceWorkerNotificationsBaselined = true;
              if (bridge.enabled && hasNewNotification) postNotificationEvent();
            } catch (_) {
            } finally {
              scheduleServiceWorkerPoll();
            }
          };

          pollServiceWorkerNotifications();
        })();
        """
    }

    static func runtimeActionSource(_ action: String) -> String {
        let allowedActions = ["toggleDrawer", "openDrawer", "closeDrawer"]
        guard allowedActions.contains(action) else { return "false;" }
        return """
        (() => {
          const runtime = window['\(runtimeKey)'];
          if (!runtime || typeof runtime.\(action) !== 'function') return false;
          runtime.\(action)();
          return true;
        })();
        """
    }

    static func railActivationSource(id: String) -> String {
        guard !id.isEmpty,
              id.count <= DiscordRailModel.maximumIDLength,
              id.range(
                of: #"^[A-Za-z0-9:@._-]+$"#,
                options: .regularExpression
              ) != nil
        else { return "false;" }
        let encodedID = javascriptLiteral(id, fallback: "null")
        return """
        (() => {
          const runtime = window['\(runtimeKey)'];
          if (!runtime || typeof runtime.activateRailItem !== 'function') return false;
          return runtime.activateRailItem(\(encodedID)) === true;
        })();
        """
    }

    private static func append(_ css: String, to sections: inout [String]) {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sections.append(trimmed) }
    }

    private static func navigationValue(_ value: DiscordNavigationPresentation) -> String {
        switch value {
        case .docked: "docked"
        case .floating: "floating"
        case .hidden: "hidden"
        }
    }

    private static func composerValue(_ value: DiscordComposerMode) -> String {
        switch value {
        case .full: "full"
        case .essential: "essential"
        case .hidden: "hidden"
        }
    }

    private static func themeValue(_ value: DiscordVisualTheme) -> String {
        switch value {
        case .systemGlass: "system-glass"
        case .discord: "discord"
        case .oled: "oled"
        case .soft: "soft"
        }
    }

    private static func accentValue(_ value: SideCordAccent) -> String {
        switch value {
        case .automatic: "automatic"
        case .blurple: "blurple"
        case .blue: "blue"
        case .purple: "purple"
        case .pink: "pink"
        case .green: "green"
        case .orange: "orange"
        }
    }

    private static func colorSchemeValue(_ value: ThemeColorScheme) -> String {
        switch value {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        }
    }

    private static func accentValues(for accent: SideCordAccent) -> (color: String, rgb: String) {
        switch accent {
        case .automatic, .blurple: ("#5865f2", "88 101 242")
        case .blue: ("#0a84ff", "10 132 255")
        case .purple: ("#af52de", "175 82 222")
        case .pink: ("#ff2d55", "255 45 85")
        case .green: ("#30d158", "48 209 88")
        case .orange: ("#ff9f0a", "255 159 10")
        }
    }

    private static func decimalString(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func javascriptLiteral<Value: Encodable>(
        _ value: Value,
        fallback: String
    ) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8)
        else {
            return fallback
        }
        return literal
    }
}
