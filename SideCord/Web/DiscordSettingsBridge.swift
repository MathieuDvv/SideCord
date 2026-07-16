import Foundation

struct SideCordWebPanelSettingsSnapshot: Codable, Equatable, Sendable {
    let identifier: String
    let name: String
    let allowedHosts: [String]
    let persistentWebsiteData: Bool
    let backgroundAudioRequested: Bool
    let backgroundAudioAllowed: Bool
    let visible: Bool
    let height: Double
    let minimumHeight: Double
    let maximumHeight: Double
    let userResizable: Bool
}

struct SideCordPluginSettingsSnapshot: Codable, Equatable, Sendable {
    let identifier: String
    let name: String
    let version: String
    let enabled: Bool
    let webPanel: SideCordWebPanelSettingsSnapshot?

    init(
        identifier: String,
        name: String,
        version: String,
        enabled: Bool,
        webPanel: SideCordWebPanelSettingsSnapshot? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.enabled = enabled
        self.webPanel = webPanel
    }
}

struct SideCordSettingsSnapshot: Codable, Equatable, Sendable {
    let sidebarEdge: String
    let edgeHoverEnabled: Bool
    let sidebarWidth: Double
    let sidebarInset: Double
    let discordLayoutMode: String
    let floatingRailEnabled: Bool
    let visualTheme: String
    let themeAccent: String
    let themeIntensity: Double
    let themeColorScheme: String
    let notificationGlowEnabled: Bool
    let attentionGlowColor: String
    let attentionGlowStrength: String
    let incomingCallCardEnabled: Bool
    let pluginsInstalled: Int
    let pluginsEnabled: Int
    var plugins: [SideCordPluginSettingsSnapshot] = []
}

enum SideCordSettingsMutation {
    @MainActor
    static func apply(
        key: String,
        value: Any,
        to settings: AppSettings
    ) -> Bool {
        func boolValue() -> Bool? {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID()
            else { return nil }
            return number.boolValue
        }
        func doubleValue() -> Double? {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite
            else { return nil }
            return number.doubleValue
        }

        switch key {
        case "sidebarEdge":
            guard let raw = value as? String, let edge = SidebarEdge(rawValue: raw) else { return false }
            settings.sidebarEdge = edge
        case "edgeHoverEnabled":
            guard let next = boolValue() else { return false }
            settings.edgeHoverEnabled = next
        case "sidebarWidth":
            guard let next = doubleValue(), (320 ... 900).contains(next) else { return false }
            settings.resetAllDisplayWidths()
            settings.sidebarWidth = next
        case "sidebarInset":
            guard let next = doubleValue(), (0 ... 48).contains(next) else { return false }
            settings.sidebarInset = next
        case "discordLayoutMode":
            guard let raw = value as? String,
                  let mode = DiscordLayoutMode(rawValue: raw), mode != .custom
            else { return false }
            settings.applyDiscordLayoutMode(mode)
        case "floatingRailEnabled":
            guard let next = boolValue() else { return false }
            settings.floatingRailEnabled = next
        case "visualTheme":
            guard let raw = value as? String, let theme = DiscordVisualTheme(rawValue: raw) else { return false }
            settings.visualTheme = theme
        case "themeAccent":
            guard let raw = value as? String, let accent = SideCordAccent(rawValue: raw) else { return false }
            settings.themeAccent = accent
        case "themeIntensity":
            guard let next = doubleValue(), (0 ... 1).contains(next) else { return false }
            settings.themeIntensity = next
        case "themeColorScheme":
            guard let raw = value as? String, let scheme = ThemeColorScheme(rawValue: raw) else { return false }
            settings.themeColorScheme = scheme
        case "notificationGlowEnabled":
            guard let next = boolValue() else { return false }
            settings.notificationGlowEnabled = next
        case "attentionGlowColor":
            guard let raw = value as? String, let color = AttentionGlowColor(rawValue: raw) else { return false }
            settings.attentionGlowColor = color
        case "attentionGlowStrength":
            guard let raw = value as? String,
                  let strength = AttentionGlowStrength(rawValue: raw)
            else { return false }
            settings.attentionGlowStrength = strength
        case "incomingCallCardEnabled":
            guard let next = boolValue() else { return false }
            settings.incomingCallCardEnabled = next
        default:
            return false
        }
        return true
    }
}

extension DiscordCSSComposer {
    static let settingsBridgeKey = "__sidecordSettingsBridge_v5__"

    static func settingsBridgeUserScriptSource(snapshot: SideCordSettingsSnapshot) -> String {
        let encodedSnapshot = javascriptLiteral(snapshot, fallback: "{}")
        let encodedHandler = javascriptLiteral(messageHandlerName, fallback: "\"\"")
        return """
        (() => {
          const host = window.location.hostname.toLowerCase().replace(/\\.+$/, "");
          const isDiscordHost = host === "discord.com" || host.endsWith(".discord.com") ||
            host === "discordapp.com" || host.endsWith(".discordapp.com");
          if (window.location.protocol !== "https:" || !isDiscordHost) return;

          const key = "\(settingsBridgeKey)";
          const nextSnapshot = \(encodedSnapshot);
          const handlerName = \(encodedHandler);
          const previous = window[key];
          if (previous?.version === 9 && typeof previous.update === "function") {
            previous.update(nextSnapshot);
            return;
          }
          if (typeof previous?.dispose === "function") previous.dispose();

          const post = payload => {
            try { window.webkit?.messageHandlers?.[handlerName]?.postMessage(payload); }
            catch (_) {}
          };
          const state = {
            version: 9,
            snapshot: nextSnapshot,
            observer: null,
            timer: 0,
            openTimer: 0,
            navButton: null,
            navButtons: [],
            sectionLabel: null,
            page: null,
            contentRegion: null,
            hiddenDiscordContent: [],
            shellDetected: false,
            selected: false,
            selectedPageKey: "settings",
            settingsButtonFound: false,
            settingsActivationCount: 0,
            lastHealth: "",
            navBaseClass: "",
            navSelectedClass: "",
            webpackRequire: null,
            react: null,
            settingsRouter: null,
            rootLayout: null,
            rootPatched: false,
            pendingNativeOpen: false,
            webpackHookInstalled: false,
            lastWebpackCacheSize: -1,
            activeRangeKey: null,
            rangeCommitTimer: 0,
            pluginListHost: null,
            pluginListSignature: "",
            update: null,
            open: null,
            dispose: null
          };

          const safeQuery = (root, selector) => {
            try { return root?.querySelector(selector) || null; } catch (_) { return null; }
          };
          const safeQueryAll = (root, selector) => {
            try { return [...(root?.querySelectorAll(selector) || [])]; } catch (_) { return []; }
          };
          const classNames = element => typeof element?.className === "string"
            ? element.className.split(/\\s+/).filter(Boolean)
            : [];
          const hasClassStem = (element, stem) => {
            const lowerStem = String(stem).toLowerCase();
            return classNames(element).some(name => {
              const lowerName = name.toLowerCase();
              return lowerName === lowerStem || lowerName.startsWith(`${lowerStem}_`);
            });
          };
          const stemSelector = stem =>
            `[class="${stem}"], [class^="${stem}_"], [class*=" ${stem}_"]`;
          const queryStem = (root, stem) => safeQuery(root, stemSelector(stem));
          const queryAllStem = (root, stem) => safeQueryAll(root, stemSelector(stem));
          const lastConnected = elements => [...elements].reverse().find(element => element?.isConnected) || null;
          const settingsRoot = () => {
            const explicit = lastConnected(queryAllStem(document, "standardSidebarView")) ||
              lastConnected(safeQueryAll(document, `[class*="standardSidebarView" i]`));
            if (explicit) return explicit;
            const sidebarRegion = lastConnected(queryAllStem(document, "sidebarRegion")) ||
              lastConnected(safeQueryAll(document, `[class*="sidebarRegion" i]`));
            if (!sidebarRegion) return null;
            let candidate = sidebarRegion.parentElement;
            while (candidate && candidate !== document.body) {
              if (queryStem(candidate, "contentRegion") ||
                  safeQuery(candidate, `[class*="contentRegion" i]`)) return candidate;
              candidate = candidate.parentElement;
            }
            return null;
          };
          const resolveShell = () => {
            const mobileSidebar = lastConnected(safeQueryAll(
              document,
              `aside:has(nav ${stemSelector("sublist")})`
            ));
            if (mobileSidebar) {
              const root = mobileSidebar.parentElement;
              const contentRegion = root && (
                [...root.children].find(child => hasClassStem(child, "content")) ||
                queryStem(root, "content")
              );
              if (root && contentRegion) {
                return { root, sidebar: mobileSidebar, content: contentRegion, mobile: true };
              }
            }
            const root = settingsRoot();
            if (!root) return null;
            const sidebarRegion = queryStem(root, "sidebarRegion") ||
              safeQuery(root, `[class*="sidebarRegion" i]`);
            const contentRegion = queryStem(root, "contentRegion") ||
              safeQuery(root, `[class*="contentRegion" i]`);
            const sidebar = sidebarRegion && (
              queryStem(sidebarRegion, "sidebar") || safeQuery(sidebarRegion, "nav") || sidebarRegion
            );
            const content = contentRegion && (
              queryStem(contentRegion, "contentColumn") || safeQuery(contentRegion, "main") || contentRegion
            );
            return sidebar && content ? { root, sidebar, content, mobile: false } : null;
          };
          const isNavigationItem = child => child?.matches?.(
            `button, [role="tab"], [role="button"], [tabindex]`
          ) || hasClassStem(child, "item");
          const directNavigationItems = candidate => [...(candidate?.children || [])].filter(child =>
            isNavigationItem(child) && !hasClassStem(child, "header") &&
              !hasClassStem(child, "separator") && !hasClassStem(child, "divider")
          );
          const navigationHostScore = candidate => {
            const children = [...(candidate?.children || [])];
            const rows = directNavigationItems(candidate).length;
            const headings = children.filter(child =>
              hasClassStem(child, "header") || hasClassStem(child, "section")
            ).length;
            return rows * 20 + headings * 4 +
              (hasClassStem(candidate, "side") ? 30 : 0) +
              (candidate?.tagName?.toLowerCase() === "nav" ? 12 : 0) +
              (candidate?.getAttribute?.("role") === "tablist" ? 12 : 0);
          };
          const resolveNavigationHost = sidebar => {
            const mobileList = queryStem(sidebar, "sublist");
            if (mobileList) return mobileList;
            const candidates = [
              sidebar,
              ...queryAllStem(sidebar, "side"),
              ...safeQueryAll(sidebar, `nav, [role="tablist"], div`)
            ];
            let best = sidebar;
            let bestScore = navigationHostScore(sidebar);
            for (const candidate of candidates) {
              const score = navigationHostScore(candidate);
              if (score > bestScore) { best = candidate; bestScore = score; }
            }
            return best;
          };
          const option = (value, label) => `<option value="${value}">${label}</option>`;
          const escapeHTML = value => String(value ?? "")
            .replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
          const select = (key, entries) => `
            <select data-sidecord-key="${key}">
              ${entries.map(([value, label]) => option(value, label)).join("")}
            </select>`;
          const toggle = key => `<input type="checkbox" data-sidecord-key="${key}">`;
          const range = (key, min, max, step) =>
            `<input type="range" min="${min}" max="${max}" step="${step}" data-sidecord-key="${key}">`;
          const row = (title, detail, control) => `
            <label class="sc-row"><span><b>${title}</b><small>${detail}</small></span>${control}</label>`;

          const pageHTML = () => `
            <style>
              [data-sidecord-settings-page] { overflow:auto; color:#f2f3f5; color-scheme:dark; }
              html[data-sidecord-resolved-color-scheme="light"] [data-sidecord-settings-page] {
                color:#1f2328; color-scheme:light; }
              [data-sidecord-settings-page]:not([data-sidecord-native-layout]) { position:absolute; inset:0;
                z-index:100; padding:60px 40px 96px;
                background:var(--background-base-lowest,var(--background-primary,#111214)) !important; }
              [data-sidecord-native-layout] { width:100%; padding:0 0 96px; }
              [data-sidecord-settings-page] * { box-sizing:border-box; }
              .sc-wrap { max-width:740px; margin:0; font-family:var(--font-primary,gg sans,sans-serif); }
              .sc-title { margin-bottom:34px; }
              .sc-mark { display:none; }
              .sc-title h1 { margin:0; color:inherit; font-size:20px; line-height:24px; }
              .sc-title p { margin:8px 0 0; color:#b8bdc7; font-size:14px; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-title p { color:#4b5563; }
              .sc-section { display:none; margin:0 0 38px; }
              [data-sidecord-selected-page="theme"] .sc-section[data-sidecord-page="theme"],
              [data-sidecord-selected-page="layout"] .sc-section[data-sidecord-page="layout"],
              [data-sidecord-selected-page="settings"] .sc-section[data-sidecord-page="settings"],
              [data-sidecord-selected-page="plugins"] .sc-section[data-sidecord-page="plugins"] { display:block; }
              .sc-section h2 { margin:0 0 8px; font-size:12px; line-height:16px; letter-spacing:.02em;
                text-transform:uppercase; color:#c7c9ce; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-section h2 { color:#3f454d; }
              .sc-row { min-height:64px; display:flex; align-items:center; justify-content:space-between; gap:32px;
                border-top:1px solid rgb(255 255 255 / 14%); padding:16px 0; cursor:default; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-row {
                border-top-color:rgb(31 35 40 / 18%); }
              .sc-row:first-of-type { border-top:0; } .sc-row span { display:grid; gap:4px; }
              .sc-row b,.sc-footer b { color:inherit; font-size:16px; font-weight:500; }
              .sc-row small,.sc-footer small { color:#b8bdc7; font-size:14px; line-height:18px; }
              html[data-sidecord-resolved-color-scheme="light"] :is(.sc-row small,.sc-footer small) { color:#4b5563; }
              .sc-row select { width:210px; border:0; border-radius:4px; padding:10px 12px;
                color:#f2f3f5; background:#2b2d31; font:inherit; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-row select { color:#1f2328; background:#e3e5e8; }
              .sc-row input[type=range] { width:210px; accent-color:#7886ff; touch-action:none; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-row input[type=range] { accent-color:#4752c4; }
              .sc-row input[type=checkbox] { appearance:none; width:40px; height:24px; border-radius:12px;
                flex:0 0 auto; background:#686d73; border:1px solid #8b919a; position:relative;
                transition:background .15s ease; cursor:pointer; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-row input[type=checkbox] {
                background:#68707b; border-color:#4b5563; }
              .sc-row input[type=checkbox]::after { content:""; position:absolute; width:18px; height:18px;
                left:3px; top:3px; border-radius:50%; background:white; transition:transform .15s ease; }
              .sc-row input[type=checkbox]:checked { background:#7886ff; border-color:#a9b2ff; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-row input[type=checkbox]:checked {
                background:#4752c4; border-color:#343d9f; }
              .sc-row input[type=checkbox]:checked::after { transform:translateX(16px); }
              :is(.sc-row input,.sc-row select,.sc-button):focus-visible { outline:3px solid #9aa4ff; outline-offset:2px; }
              html[data-sidecord-resolved-color-scheme="light"] :is(.sc-row input,.sc-row select,.sc-button):focus-visible {
                outline-color:#343d9f; }
              .sc-button { border:1px solid transparent; border-radius:4px; padding:10px 16px; color:white; cursor:pointer;
                background:#5865f2; font:inherit; font-weight:600; }
              .sc-button:hover { background:#4752c4; }
              .sc-button.sc-secondary { color:inherit; background:transparent; border-color:currentColor; }
              .sc-button.sc-danger { color:#ffb4ae; background:transparent; border-color:#da373c; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-button.sc-danger { color:#a1282d; }
              .sc-footer { display:flex; justify-content:space-between; align-items:center; gap:16px; }
              .sc-actions { display:flex; flex-wrap:wrap; gap:10px; margin-top:22px; }
              .sc-plugin-list { display:grid; gap:0; margin-top:18px; }
              .sc-plugin { display:grid; gap:14px; padding:18px 0;
                border-top:1px solid rgb(255 255 255 / 14%); }
              html[data-sidecord-resolved-color-scheme="light"] .sc-plugin { border-top-color:rgb(31 35 40 / 18%); }
              .sc-plugin-head { display:flex; align-items:center; gap:16px; }
              .sc-plugin-head > span { display:grid; gap:3px; flex:1; min-width:0; }
              .sc-plugin input[type=checkbox] { width:18px; height:18px; accent-color:#7886ff; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-plugin input[type=checkbox] { accent-color:#4752c4; }
              .sc-plugin-permission { color:#b8bdc7; font-size:13px; line-height:19px; margin:0; }
              html[data-sidecord-resolved-color-scheme="light"] .sc-plugin-permission { color:#4b5563; }
              .sc-plugin-controls { display:grid; gap:10px; padding:12px 14px; border-radius:8px;
                background:rgb(255 255 255 / 6%); }
              html[data-sidecord-resolved-color-scheme="light"] .sc-plugin-controls { background:rgb(31 35 40 / 7%); }
              .sc-plugin-control { display:flex; align-items:center; justify-content:space-between; gap:18px; }
              .sc-plugin-control input[type=range] { width:min(240px,45%); accent-color:#7886ff; }
              .sc-plugin-actions { display:flex; flex-wrap:wrap; gap:8px; }
              @media(max-width:650px) { [data-sidecord-settings-page]{padding:28px 20px 64px}.sc-row{align-items:flex-start;flex-direction:column}.sc-row select,.sc-row input[type=range]{width:100%} }
            </style>
            <div class="sc-wrap">
              <div class="sc-title"><div class="sc-mark">S</div><div><h1 data-sidecord-page-title>SideCord Settings</h1><p>Discord, one edge away.</p></div></div>
              <section class="sc-section" data-sidecord-page="settings"><h2>Sidebar</h2>
                ${row("Screen edge","Where SideCord waits.",select("sidebarEdge",[["left","Left"],["right","Right"]]))}
                ${row("Edge reveal","Reveal when the pointer rests at the edge.",toggle("edgeHoverEnabled"))}
                ${row("Width","Default width for new displays.",range("sidebarWidth",320,900,20))}
                ${row("Floating inset","Space around the SideCord panel.",range("sidebarInset",0,48,4))}
              </section>
              <section class="sc-section" data-sidecord-page="layout"><h2>Discord layout</h2>
                ${row("Layout preset","Choose the amount of Discord chrome.",select("discordLayoutMode",[["full","Full"],["focus","Focus"],["reader","Reader"]]))}
                ${row("Floating server rail","Keep servers beside SideCord.",toggle("floatingRailEnabled"))}
                <div class="sc-actions"><button class="sc-button sc-secondary" type="button" data-sidecord-action="resetLayout">Reset layout</button></div>
              </section>
              <section class="sc-section" data-sidecord-page="theme"><h2>Appearance</h2>
                ${row("Theme","Curated SideCord surface palette.",select("visualTheme",[["systemGlass","System Glass"],["discord","Discord"],["oled","OLED"],["soft","Soft"]]))}
                ${row("Accent","Used by themes, controls and optional glow.",select("themeAccent",[["automatic","Automatic"],["blurple","Blurple"],["blue","Blue"],["purple","Purple"],["pink","Pink"],["green","Green"],["orange","Orange"],["white","White"]]))}
                ${row("Theme intensity","Strength of SideCord surfaces.",range("themeIntensity",0,1,.05))}
                ${row("Color scheme","Follow macOS or force an appearance.",select("themeColorScheme",[["system","System"],["light","Light"],["dark","Dark"]]))}
                <div class="sc-actions"><button class="sc-button sc-secondary" type="button" data-sidecord-action="resetTheme">Reset theme</button></div>
              </section>
              <section class="sc-section" data-sidecord-page="settings"><h2>Attention</h2>
                ${row("Activity glow","Pulse the configured screen edge.",toggle("notificationGlowEnabled"))}
                ${row("Glow color","Independent or following the theme.",select("attentionGlowColor",[["followTheme","Follow Theme"],["blurple","Blurple"],["blue","Blue"],["purple","Purple"],["pink","Pink"],["green","Green"],["orange","Orange"],["white","White"]]))}
                ${row("Glow strength","Visual intensity of the bloom.",select("attentionGlowStrength",[["subtle","Subtle"],["normal","Normal"],["strong","Strong"]]))}
                ${row("Incoming-call controls","Show Answer and Decline at the edge.",toggle("incomingCallCardEnabled"))}
                <div class="sc-actions"><button class="sc-button sc-danger" type="button" data-sidecord-action="resetAll">Reset all SideCord settings</button></div>
              </section>
              <section class="sc-section" data-sidecord-page="plugins"><h2>Plugins</h2><div class="sc-footer">
                <span><b>${escapeHTML(state.snapshot.pluginsEnabled)} of ${escapeHTML(state.snapshot.pluginsInstalled)} plugins enabled</b><br><small>Plugins remain declarative; web panels use isolated, host-managed browser profiles.</small></span>
                <button class="sc-button" type="button" data-sidecord-action="installPlugin">Import JSON…</button>
              </div><div class="sc-plugin-list" data-sidecord-plugin-list></div></section>
            </div>`;

          const renderPluginList = () => {
            const host = safeQuery(state.page, "[data-sidecord-plugin-list]");
            if (!host) return;
            const plugins = Array.isArray(state.snapshot.plugins) ? state.snapshot.plugins : [];
            let signature = "";
            try {
              signature = JSON.stringify(plugins.map(plugin => {
                const panel = plugin.webPanel;
                return [
                  String(plugin.identifier || ""), String(plugin.name || ""),
                  String(plugin.version || ""), !!plugin.enabled,
                  panel ? [
                    String(panel.identifier || ""), String(panel.name || ""),
                    [...(panel.allowedHosts || [])].map(String).sort(),
                    !!panel.persistentWebsiteData, !!panel.backgroundAudioRequested,
                    !!panel.backgroundAudioAllowed, !!panel.visible,
                    Number(panel.height || 0), Number(panel.minimumHeight || 0),
                    Number(panel.maximumHeight || 0), !!panel.userResizable
                  ] : null
                ];
              }));
            } catch (_) {}
            if (state.pluginListHost === host && state.pluginListSignature === signature) return;
            state.pluginListHost = host;
            state.pluginListSignature = signature;
            host.replaceChildren();
            if (!plugins.length) {
              const empty = document.createElement("small");
              empty.textContent = "No plugins installed.";
              host.appendChild(empty);
              return;
            }
            for (const plugin of plugins) {
              const rowNode = document.createElement("div");
              rowNode.className = "sc-plugin";
              const head = document.createElement("div");
              head.className = "sc-plugin-head";
              const description = document.createElement("span");
              const name = document.createElement("b");
              name.textContent = String(plugin.name || plugin.identifier || "Plugin");
              const version = document.createElement("small");
              version.textContent = `Version ${String(plugin.version || "")}`;
              description.append(name, version);
              const enabled = document.createElement("input");
              enabled.type = "checkbox";
              enabled.checked = !!plugin.enabled;
              enabled.setAttribute("aria-label", `Enable ${name.textContent}`);
              enabled.setAttribute("data-sidecord-plugin-enabled", String(plugin.identifier || ""));
              enabled.addEventListener("click", event => {
                event.stopPropagation();
              });
              enabled.addEventListener("change", event => {
                event.stopPropagation();
                if (enabled.checked && plugin.webPanel) {
                  const panel = plugin.webPanel;
                  const domains = Array.isArray(panel.allowedHosts) ? panel.allowedHosts.join(", ") : "declared domains";
                  const warning = `This plugin loads content and executable website code from ${domains}, ` +
                    `${panel.persistentWebsiteData ? "stores cookies and local data" : "uses temporary website data"}` +
                    `${panel.backgroundAudioRequested ? ", and may continue playing audio while SideCord is hidden." : "."}`;
                  if (!window.confirm(warning)) {
                    enabled.checked = false;
                    return;
                  }
                }
                post({ type: "settingsAction", action: "setPluginEnabled",
                  identifier: String(plugin.identifier || ""), value: !!enabled.checked });
              });
              head.append(description, enabled);
              rowNode.appendChild(head);

              const panel = plugin.webPanel;
              if (panel) {
                const permission = document.createElement("p");
                permission.className = "sc-plugin-permission";
                const domains = Array.isArray(panel.allowedHosts) ? panel.allowedHosts.join(", ") : "";
                permission.textContent = `Loads website content and executable website code from ${domains || "declared domains"}. ` +
                  `${panel.persistentWebsiteData ? "Stores isolated cookies and local data." : "Uses a temporary isolated session."} ` +
                  `${panel.backgroundAudioRequested ? "May continue audio while SideCord is hidden when allowed." : "Background audio is not requested."}`;
                rowNode.appendChild(permission);

                const controls = document.createElement("div");
                controls.className = "sc-plugin-controls";
                const control = (labelText, input) => {
                  const label = document.createElement("label");
                  label.className = "sc-plugin-control";
                  const text = document.createElement("span");
                  text.textContent = labelText;
                  label.append(text, input);
                  controls.appendChild(label);
                };
                const configure = (input, kind) => {
                  input.setAttribute("data-sidecord-plugin-panel-setting", kind);
                  input.setAttribute("data-sidecord-plugin-id", String(plugin.identifier || ""));
                  input.setAttribute("data-sidecord-panel-id", String(panel.identifier || ""));
                  input.disabled = !plugin.enabled;
                  const postValue = () => {
                    const actions = { visible: "setPluginPanelVisible", height: "setPluginPanelHeight",
                      backgroundAudio: "setPluginPanelBackgroundAudio" };
                    post({ type: "settingsAction", action: actions[kind],
                      identifier: String(plugin.identifier || ""),
                      panelIdentifier: String(panel.identifier || ""),
                      value: input.type === "checkbox" ? !!input.checked : Number(input.value) });
                  };
                  input.addEventListener("click", event => {
                    if (input.type !== "checkbox") return;
                    event.stopPropagation();
                  });
                  input.addEventListener("change", event => {
                    event.stopPropagation();
                    postValue();
                  });
                  return input;
                };
                const visible = configure(document.createElement("input"), "visible");
                visible.type = "checkbox";
                visible.checked = !!panel.visible;
                control("Visible below Discord", visible);

                const height = configure(document.createElement("input"), "height");
                height.type = "range";
                height.min = String(panel.minimumHeight || 120);
                height.max = String(panel.maximumHeight || 320);
                height.step = "1";
                height.value = String(panel.height || 190);
                height.disabled = !plugin.enabled || !panel.userResizable;
                control(`Height (${Math.round(Number(panel.height || 190))} px)`, height);

                if (panel.backgroundAudioRequested) {
                  const audio = configure(document.createElement("input"), "backgroundAudio");
                  audio.type = "checkbox";
                  audio.checked = !!panel.backgroundAudioAllowed;
                  control("Allow audio while hidden", audio);
                }
                rowNode.appendChild(controls);

                const panelActions = document.createElement("div");
                panelActions.className = "sc-plugin-actions";
                for (const [action, title] of [["reloadPluginPanel", "Reload"], ["openPluginPanel", "Open in browser"], ["clearPluginPanelData", "Clear website data"]]) {
                  const button = document.createElement("button");
                  button.type = "button";
                  button.className = "sc-button sc-secondary";
                  button.textContent = title;
                  button.disabled = !plugin.enabled;
                  button.setAttribute("data-sidecord-plugin-panel-action", action);
                  button.setAttribute("data-sidecord-plugin-id", String(plugin.identifier || ""));
                  button.setAttribute("data-sidecord-panel-id", String(panel.identifier || ""));
                  button.addEventListener("click", event => {
                    event.stopPropagation();
                    if (action === "clearPluginPanelData" &&
                        !window.confirm("Clear this panel’s cookies, sign-in, cache, and local website data?")) return;
                    post({ type: "settingsAction", action,
                      identifier: String(plugin.identifier || ""),
                      panelIdentifier: String(panel.identifier || "") });
                  });
                  panelActions.appendChild(button);
                }
                rowNode.appendChild(panelActions);
              }

              const removeActions = document.createElement("div");
              removeActions.className = "sc-plugin-actions";
              const remove = document.createElement("button");
              remove.type = "button";
              remove.className = "sc-button sc-danger";
              remove.textContent = "Remove";
              remove.setAttribute("data-sidecord-plugin-remove", String(plugin.identifier || ""));
              remove.addEventListener("click", event => {
                event.stopPropagation();
                post({ type: "settingsAction", action: "removePlugin",
                  identifier: String(plugin.identifier || "") });
              });
              removeActions.appendChild(remove);
              if (panel?.persistentWebsiteData) {
                const removeData = document.createElement("button");
                removeData.type = "button";
                removeData.className = "sc-button sc-danger";
                removeData.textContent = "Remove and delete website data";
                removeData.setAttribute("data-sidecord-plugin-remove-data", String(plugin.identifier || ""));
                removeData.setAttribute("data-sidecord-panel-id", String(panel.identifier || ""));
                removeData.addEventListener("click", event => {
                  event.stopPropagation();
                  if (!window.confirm("Remove this plugin and permanently delete its isolated website data?")) return;
                  post({ type: "settingsAction", action: "removePluginAndData",
                    identifier: String(plugin.identifier || ""),
                    panelIdentifier: String(panel.identifier || "") });
                });
                removeActions.appendChild(removeData);
              }
              rowNode.appendChild(removeActions);
              host.appendChild(rowNode);
            }
          };

          const applySnapshot = () => {
            if (!state.page) return;
            for (const input of safeQueryAll(state.page, "[data-sidecord-key]")) {
              const key = input.getAttribute("data-sidecord-key");
              if (!(key in state.snapshot)) continue;
              if (input.type === "range" &&
                  (state.activeRangeKey === key || input === document.activeElement)) continue;
              if (input.type === "checkbox") input.checked = !!state.snapshot[key];
              else input.value = String(state.snapshot[key]);
            }
            renderPluginList();
          };
          const pageTitles = {
            theme: "SideCord Theme",
            layout: "SideCord Layout",
            settings: "SideCord Settings",
            plugins: "SideCord Plugins"
          };
          const showPageContent = (node, pageKey) => {
            if (!node) return;
            const resolvedKey = pageTitles[pageKey] ? pageKey : "settings";
            node.setAttribute("data-sidecord-selected-page", resolvedKey);
            const title = safeQuery(node, "[data-sidecord-page-title]");
            if (title) title.textContent = pageTitles[resolvedKey];
          };
          const postSetting = input => {
            const value = input.type === "checkbox" ? input.checked :
              input.type === "range" ? Number(input.value) : input.value;
            post({ type: "settingsSet", key: input.getAttribute("data-sidecord-key"), value });
          };
          const finishRangeInteraction = input => {
            if (!input || input.type !== "range") return;
            if (state.rangeCommitTimer) clearTimeout(state.rangeCommitTimer);
            state.rangeCommitTimer = 0;
            postSetting(input);
            setTimeout(() => {
              if (state.activeRangeKey === input.getAttribute("data-sidecord-key")) {
                state.activeRangeKey = null;
                applySnapshot();
              }
            }, 180);
          };
          const bindPageInteractions = node => {
            if (!node || node.dataset.sidecordSettingsBound) return;
            node.dataset.sidecordSettingsBound = "true";
            safeQuery(node, '[data-sidecord-action="installPlugin"]')?.addEventListener("click", event => {
              event.stopPropagation();
              post({ type: "settingsAction", action: "installPlugin" });
            });
            node.addEventListener("pointerdown", event => {
              const input = event.target?.closest?.('input[type="range"][data-sidecord-key]');
              if (input) state.activeRangeKey = input.getAttribute("data-sidecord-key");
            });
            for (const eventName of ["pointerup", "pointercancel"]) {
              node.addEventListener(eventName, event => {
                const input = event.target?.closest?.('input[type="range"][data-sidecord-key]');
                if (input) finishRangeInteraction(input);
              });
            }
            node.addEventListener("input", event => {
              const input = event.target?.closest?.('input[type="range"][data-sidecord-key]');
              if (!input) return;
              state.activeRangeKey = input.getAttribute("data-sidecord-key");
              if (state.rangeCommitTimer) clearTimeout(state.rangeCommitTimer);
              state.rangeCommitTimer = setTimeout(() => {
                state.rangeCommitTimer = 0;
                postSetting(input);
              }, 120);
            });
            node.addEventListener("change", event => {
              const pluginToggle = event.target?.closest?.("[data-sidecord-plugin-enabled]");
              if (pluginToggle) {
                const plugin = (state.snapshot.plugins || []).find(item =>
                  String(item.identifier || "") === pluginToggle.getAttribute("data-sidecord-plugin-enabled"));
                if (pluginToggle.checked && plugin?.webPanel) {
                  const panel = plugin.webPanel;
                  const domains = Array.isArray(panel.allowedHosts) ? panel.allowedHosts.join(", ") : "declared domains";
                  const warning = `This plugin loads content and executable website code from ${domains}, ` +
                    `${panel.persistentWebsiteData ? "stores cookies and local data" : "uses temporary website data"}` +
                    `${panel.backgroundAudioRequested ? ", and may continue playing audio while SideCord is hidden." : "."}`;
                  if (!window.confirm(warning)) {
                    pluginToggle.checked = false;
                    return;
                  }
                }
                post({ type: "settingsAction", action: "setPluginEnabled",
                  identifier: pluginToggle.getAttribute("data-sidecord-plugin-enabled"),
                  value: !!pluginToggle.checked });
                return;
              }
              const panelSetting = event.target?.closest?.("[data-sidecord-plugin-panel-setting]");
              if (panelSetting) {
                const kind = panelSetting.getAttribute("data-sidecord-plugin-panel-setting");
                const actions = { visible: "setPluginPanelVisible", height: "setPluginPanelHeight",
                  backgroundAudio: "setPluginPanelBackgroundAudio" };
                post({ type: "settingsAction", action: actions[kind],
                  identifier: panelSetting.getAttribute("data-sidecord-plugin-id"),
                  panelIdentifier: panelSetting.getAttribute("data-sidecord-panel-id"),
                  value: panelSetting.type === "checkbox" ? !!panelSetting.checked : Number(panelSetting.value) });
                return;
              }
              const input = event.target?.closest?.("[data-sidecord-key]");
              if (!input) return;
              if (input.type === "range") finishRangeInteraction(input);
              else postSetting(input);
            });
            node.addEventListener("click", event => {
              const panelAction = event.target?.closest?.("[data-sidecord-plugin-panel-action]");
              if (panelAction) {
                const action = panelAction.getAttribute("data-sidecord-plugin-panel-action");
                if (action === "clearPluginPanelData" &&
                    !window.confirm("Clear this panel’s cookies, sign-in, cache, and local website data?")) return;
                post({ type: "settingsAction", action,
                  identifier: panelAction.getAttribute("data-sidecord-plugin-id"),
                  panelIdentifier: panelAction.getAttribute("data-sidecord-panel-id") });
                return;
              }
              const removeData = event.target?.closest?.("[data-sidecord-plugin-remove-data]");
              if (removeData) {
                if (!window.confirm("Remove this plugin and permanently delete its isolated website data?")) return;
                post({ type: "settingsAction", action: "removePluginAndData",
                  identifier: removeData.getAttribute("data-sidecord-plugin-remove-data"),
                  panelIdentifier: removeData.getAttribute("data-sidecord-panel-id") });
                return;
              }
              const remove = event.target?.closest?.("[data-sidecord-plugin-remove]");
              if (remove) {
                post({ type: "settingsAction", action: "removePlugin",
                  identifier: remove.getAttribute("data-sidecord-plugin-remove") });
                return;
              }
              const action = event.target?.closest?.("[data-sidecord-action]")
                ?.getAttribute("data-sidecord-action");
              if (!action) return;
              if (action === "resetAll" &&
                  !window.confirm("Reset all SideCord settings to their defaults?")) return;
              post({ type: "settingsAction", action });
            });
          };
          const bindSettingsNode = (node, pageKey = state.selectedPageKey) => {
            if (!node) return;
            state.page = node;
            if (!node.dataset.sidecordSettingsBound) {
              node.innerHTML = pageHTML();
              bindPageInteractions(node);
            }
            showPageContent(node, pageKey);
            applySnapshot();
          };
          const nativePanelComponent = pageKey => () => {
              const React = state.react;
              if (!React?.createElement) return null;
              return React.createElement("div", {
                "data-sidecord-settings-page": "",
                "data-sidecord-native-layout": "",
                "data-sidecord-selected-page": pageKey,
                ref: node => bindSettingsNode(node, pageKey)
              });
            };
          const buildNativeItem = (pageKey, title, searchTerms) => ({
            key: `sidecord_${pageKey}`,
            type: 2,
            useTitle: () => title,
            useSearchTerms: () => ["SideCord", title, ...searchTerms],
            buildLayout: () => [{
              key: `sidecord_${pageKey}_panel`,
              type: 3,
              useTitle: () => title,
              buildLayout: () => [{
                key: `sidecord_${pageKey}_category`,
                type: 5,
                buildLayout: () => [{
                  key: `sidecord_${pageKey}_custom`,
                  type: 19,
                  Component: nativePanelComponent(pageKey),
                  useSearchTerms: () => ["SideCord", title, ...searchTerms]
                }]
              }]
            }]
          });
          const buildNativeSection = () => ({
            key: "sidecord_section",
            type: 1,
            useTitle: () => "SideCord",
            buildLayout: () => [
              buildNativeItem("theme", "Theme", ["appearance", "accent", "color"]),
              buildNativeItem("layout", "Layout", ["Discord", "sidebar", "rail"]),
              buildNativeItem("settings", "Settings", ["glow", "calls", "edge"]),
              buildNativeItem("plugins", "Plugins", ["extensions", "marketplace"])
            ]
          });
          const maybeOpenNativeSettings = () => {
            if (!state.pendingNativeOpen || !state.rootPatched ||
                typeof state.settingsRouter?.openUserSettings !== "function") return false;
            state.pendingNativeOpen = false;
            try {
              state.settingsRouter.openUserSettings(
                "sidecord_settings_panel",
                { section: "sidecord_settings" }
              );
              return true;
            } catch (_) {
              state.pendingNativeOpen = true;
              return false;
            }
          };
          const patchRootLayout = root => {
            if (!root || typeof root.buildLayout !== "function") return false;
            if (root.__sidecordOriginalBuildLayout) {
              state.rootLayout = root;
              state.rootPatched = true;
              maybeOpenNativeSettings();
              return true;
            }
            const original = root.buildLayout;
            try {
              Object.defineProperty(root, "__sidecordOriginalBuildLayout", {
                value: original, configurable: true
              });
              root.buildLayout = function(...args) {
                const layout = original.apply(this, args);
                if (!Array.isArray(layout) || layout.some(entry => entry?.key === "sidecord_section")) {
                  return layout;
                }
                let index = layout.findIndex(entry => entry?.key === "activity_section");
                if (index >= 0) index += 1;
                else {
                  index = layout.findIndex(entry => entry?.key === "utility_section");
                  if (index < 0) index = layout.length;
                }
                layout.splice(index, 0, buildNativeSection());
                return layout;
              };
              state.rootLayout = root;
              state.rootPatched = true;
              state.pendingNativeOpen = true;
              reportHealth(true);
              maybeOpenNativeSettings();
              return true;
            } catch (_) { return false; }
          };
          const inspectWebpackValue = value => {
            if (!value || (typeof value !== "object" && typeof value !== "function")) return;
            try {
              if (!state.react && typeof value.createElement === "function" &&
                  typeof value.useState === "function" && typeof value.useEffect === "function") {
                state.react = value;
              }
              if (!state.settingsRouter && typeof value.openUserSettings === "function") {
                state.settingsRouter = value;
              }
              if (value.key === "$Root" && typeof value.buildLayout === "function") {
                patchRootLayout(value);
              }
            } catch (_) {}
          };
          const inspectWebpackExports = exports => {
            inspectWebpackValue(exports);
            let values = [];
            try { values = Object.values(exports || {}); } catch (_) {}
            for (const value of values) inspectWebpackValue(value);
            maybeOpenNativeSettings();
          };
          const captureWebpackRequire = (require, force = false) => {
            if (!require?.b || !require?.c) return;
            state.webpackRequire = require;
            const cacheSize = Object.keys(require.c).length;
            if (!force && cacheSize === state.lastWebpackCacheSize) return;
            state.lastWebpackCacheSize = cacheSize;
            for (const module of Object.values(require.c)) inspectWebpackExports(module?.exports);
          };
          const installWebpackHook = () => {
            if (state.webpackHookInstalled) return;
            state.webpackHookInstalled = true;
            const chunks = window.webpackChunkdiscord_app ??= [];
            try {
              chunks.push([[Symbol("SideCord")], {}, require => captureWebpackRequire(require)]);
            } catch (_) {}
          };
          const restoreDiscordContent = () => {
            for (const record of state.hiddenDiscordContent) {
              const element = record.element;
              if (!element) continue;
              if (record.display) element.style.setProperty("display", record.display, record.priority);
              else element.style.removeProperty("display");
              if (record.ariaHidden == null) element.removeAttribute("aria-hidden");
              else element.setAttribute("aria-hidden", record.ariaHidden);
            }
            state.hiddenDiscordContent = [];
          };
          const hideDiscordContent = () => {
            const region = state.contentRegion;
            if (!region || !state.page || state.hiddenDiscordContent.length) return;
            for (const element of [...region.children]) {
              if (element === state.page) continue;
              state.hiddenDiscordContent.push({
                element,
                display: element.style.getPropertyValue("display"),
                priority: element.style.getPropertyPriority("display"),
                ariaHidden: element.getAttribute("aria-hidden")
              });
              element.style.setProperty("display", "none", "important");
              element.setAttribute("aria-hidden", "true");
            }
          };
          const selectPage = (pageKey = state.selectedPageKey, requestedButton = null) => {
            const resolvedKey = pageTitles[pageKey] ? pageKey : "settings";
            const button = requestedButton || state.navButtons.find(candidate =>
              candidate.dataset.sidecordSettingsPageKey === resolvedKey
            ) || state.navButton;
            if (!state.page || !button) return false;
            state.selected = true;
            state.selectedPageKey = resolvedKey;
            state.navButton = button;
            state.page.hidden = false;
            showPageContent(state.page, resolvedKey);
            for (const candidate of state.navButtons.length ? state.navButtons : [button]) {
              const selected = candidate === button;
              candidate.setAttribute("aria-selected", selected ? "true" : "false");
              candidate.className = selected && state.navSelectedClass
                ? state.navSelectedClass
                : state.navBaseClass || candidate.className;
              candidate.style.background = selected && !state.navSelectedClass
                ? "var(--background-modifier-selected)"
                : "";
            }
            hideDiscordContent();
            applySnapshot();
            return true;
          };
          const deselectPage = () => {
            state.selected = false;
            if (state.page) state.page.hidden = true;
            restoreDiscordContent();
            for (const button of state.navButtons.length ? state.navButtons : [state.navButton]) {
              if (!button) continue;
              button.setAttribute("aria-selected", "false");
              if (state.navBaseClass) button.className = state.navBaseClass;
              button.style.background = "";
            }
          };
          const mountMobileNavigation = navigationHost => {
            const sections = [...(navigationHost?.children || [])].filter(child =>
              hasClassStem(child, "section")
            );
            const sectionTemplate = sections.find(section =>
              queryStem(section, "sectionLabel") && queryStem(section, "sectionList")
            );
            const listTemplate = sectionTemplate && queryStem(sectionTemplate, "sectionList");
            const itemContainerTemplate = listTemplate && queryStem(listTemplate, "itemContainer");
            const itemTemplate = itemContainerTemplate && queryStem(itemContainerTemplate, "item");
            if (!sectionTemplate || !listTemplate || !itemContainerTemplate || !itemTemplate) return false;

            const section = document.createElement("li");
            section.className = sectionTemplate.className;
            section.setAttribute("data-sidecord-settings-section", "");

            const label = queryStem(sectionTemplate, "sectionLabel").cloneNode(true);
            const heading = safeQuery(label, "h1,h2,h3,h4,span") || label;
            heading.textContent = "SideCord";
            section.appendChild(label);

            const list = document.createElement("ul");
            list.className = listTemplate.className;
            const baseClass = itemTemplate.className
              .split(/\\s+/)
              .filter(name => !/^active_|^destructive_/.test(name))
              .join(" ");
            state.navButtons = [];
            const pageIcons = {
              theme: '<path d="M12 3a9 9 0 1 0 0 18h1.3a1.7 1.7 0 0 0 0-3.4h-.8a1.5 1.5 0 0 1 0-3h2.2A6.3 6.3 0 0 0 21 8.3C21 5.4 17 3 12 3Zm-4.8 8.2a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6Zm2-4.1a1.3 1.3 0 1 1 2.6 0 1.3 1.3 0 0 1-2.6 0Zm5.2.2a1.3 1.3 0 1 1 2.6 0 1.3 1.3 0 0 1-2.6 0Zm3.1 4.1a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6Z"/>',
              layout: '<path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h15A1.5 1.5 0 0 1 21 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 19.5v-15ZM5 5v14h4V5H5Zm6 0v5h8V5h-8Zm0 7v7h8v-7h-8Z"/>',
              settings: '<path d="M19.4 13a7.7 7.7 0 0 0 0-2l2-1.6-2-3.5-2.5 1a8 8 0 0 0-1.7-1L14.8 3h-4l-.4 2.8a8 8 0 0 0-1.7 1l-2.5-1-2 3.5 2 1.6a7.7 7.7 0 0 0 0 2l-2 1.6 2 3.5 2.5-1a8 8 0 0 0 1.7 1l.4 2.8h4l.4-2.8a8 8 0 0 0 1.7-1l2.5 1 2-3.5-2-1.6ZM12.8 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7Z"/>',
              plugins: '<path d="M20.5 13H18v-2h2.5a1.5 1.5 0 0 0 0-3H18V4a1 1 0 0 0-1-1h-4v2.5a1.5 1.5 0 0 1-3 0V3H6a1 1 0 0 0-1 1v4h2.5a1.5 1.5 0 0 1 0 3H5v4a1 1 0 0 0 1 1h4v2.5a1.5 1.5 0 0 0 3 0V16h4a1 1 0 0 0 1-1v-2h2.5Z"/>'
            };
            for (const [pageKey, title] of [
              ["theme", "Theme"],
              ["layout", "Layout"],
              ["settings", "Settings"],
              ["plugins", "Plugins"]
            ]) {
              const itemContainer = document.createElement("li");
              itemContainer.className = itemContainerTemplate.className;
              const button = document.createElement("div");
              button.className = baseClass;
              button.setAttribute("role", "link");
              button.setAttribute("tabindex", "0");
              button.setAttribute("aria-label", title);
              button.setAttribute("data-sidecord-settings-nav", pageKey);
              button.setAttribute("data-sidecord-settings-page-key", pageKey);
              button.innerHTML =
                '<span style="display:flex;align-items:center;gap:12px;min-width:0">' +
                  '<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="currentColor">' +
                    pageIcons[pageKey] +
                  '</svg><span>' + title + '</span>' +
                '</span>';
              button.addEventListener("click", event => {
                event.stopPropagation();
                selectPage(pageKey, button);
              });
              button.addEventListener("keydown", event => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  selectPage(pageKey, button);
                }
              });
              itemContainer.appendChild(button);
              list.appendChild(itemContainer);
              state.navButtons.push(button);
            }
            section.appendChild(list);
            navigationHost.insertBefore(section, sections[sections.length - 1] || null);

            const selectedTemplate = queryAllStem(navigationHost, "item").find(item =>
              classNames(item).some(name => /^active_/.test(name))
            );
            state.navBaseClass = baseClass;
            state.navSelectedClass = selectedTemplate?.className || `${baseClass} active_caf372`;
            state.sectionLabel = section;
            state.navButton = state.navButtons.find(button =>
              button.dataset.sidecordSettingsPageKey === state.selectedPageKey
            ) || state.navButtons[0];
            return true;
          };
          const reportHealth = injected => {
            const signature = `${state.shellDetected}:${!!injected}`;
            if (signature === state.lastHealth) return;
            state.lastHealth = signature;
            post({
              type: "settingsHealth", shellDetected: state.shellDetected, categoryInjected: !!injected
            });
          };
          const mount = () => {
            if (state.webpackRequire &&
                (!state.rootPatched || !state.settingsRouter || !state.react)) {
              captureWebpackRequire(state.webpackRequire);
            }
            const shell = resolveShell();
            state.shellDetected = !!shell;
            if (!shell) { reportHealth(false); return false; }
            const navigationHost = resolveNavigationHost(shell.sidebar);
            if (!state.sectionLabel?.isConnected && !state.navButton?.isConnected) {
              if (shell.mobile && mountMobileNavigation(navigationHost)) {
                // The current compact settings layout groups rows into semantic sections.
              } else {
              const nativeItems = directNavigationItems(navigationHost);
              const selectedTemplate = nativeItems.find(item =>
                item.getAttribute?.("aria-selected") === "true" || hasClassStem(item, "selected")
              ) || null;
              const template = nativeItems.find(item =>
                item !== selectedTemplate && !/danger|logout|red/i.test(String(item.className || ""))
              ) || selectedTemplate || null;
              const tag = template?.tagName?.toLowerCase() || "div";
              const button = document.createElement(tag);
              if (tag === "button") button.type = "button";
              button.textContent = "SideCord";
              button.setAttribute("role", "tab");
              button.setAttribute("tabindex", "0");
              button.setAttribute("data-sidecord-settings-nav", "");
              state.navBaseClass = typeof template?.className === "string" ? template.className : "";
              state.navSelectedClass = typeof selectedTemplate?.className === "string"
                ? selectedTemplate.className
                : state.navBaseClass;
              button.className = state.navBaseClass;
              if (!button.className) {
                button.style.cssText = "width:100%;border:0;border-radius:4px;padding:8px 10px;text-align:left;color:var(--interactive-normal);background:transparent;font:inherit;font-weight:500;cursor:pointer";
              }
              button.addEventListener("click", event => { event.stopPropagation(); selectPage(); });
              const dangerBoundary = [...(navigationHost.children || [])].find(child =>
                /danger|logout|red/i.test(String(child.className || "")) ||
                  /logout|log-out/i.test(String(child.getAttribute?.("data-list-item-id") || ""))
              ) || null;
              const headingTemplate = [...(navigationHost.children || [])].find(child =>
                !nativeItems.includes(child) &&
                (hasClassStem(child, "header") || hasClassStem(child, "section") ||
                  /header|section|title/i.test(String(child.className || ""))) &&
                String(child.textContent || "").trim().length > 0
              );
              if (headingTemplate) {
                const heading = document.createElement(headingTemplate.tagName.toLowerCase());
                heading.className = headingTemplate.className;
                heading.textContent = "SideCord";
                heading.setAttribute("data-sidecord-settings-heading", "");
                navigationHost.insertBefore(heading, dangerBoundary);
                state.sectionLabel = heading;
              }
              navigationHost.insertBefore(button, dangerBoundary);
              state.navButton = button;
              state.navButtons = [button];
              }
            }
            if (!state.page?.isConnected) {
              restoreDiscordContent();
              const page = document.createElement("div");
              page.setAttribute("data-sidecord-settings-page", "");
              page.setAttribute("data-sidecord-selected-page", state.selectedPageKey);
              page.hidden = true;
              page.innerHTML = pageHTML();
              bindPageInteractions(page);
              const region = shell.content.closest(`[class*="contentRegion" i]`) || shell.content;
              if (getComputedStyle(region).position === "static") region.style.position = "relative";
              region.appendChild(page);
              state.contentRegion = region;
              state.page = page;
            }
            if (state.selected) selectPage(state.selectedPageKey);
            for (const item of safeQueryAll(navigationHost, "button, [role='tab'], [role='button'], [role='link']")) {
              if (item.hasAttribute("data-sidecord-settings-nav") ||
                  item.dataset.sidecordSettingsBound) continue;
              item.dataset.sidecordSettingsBound = "true";
              item.addEventListener("click", deselectPage);
            }
            reportHealth(true);
            return true;
          };
          const scheduleMount = () => {
            if (state.timer) return;
            state.timer = setTimeout(() => { state.timer = 0; mount(); }, 60);
          };
          state.observer = new MutationObserver(scheduleMount);
          state.observer.observe(document, { childList:true, subtree:true });
          state.update = snapshot => { state.snapshot = snapshot || {}; applySnapshot(); };
          state.open = () => {
            state.selected = true;
            state.pendingNativeOpen = true;
            if (state.webpackRequire) captureWebpackRequire(state.webpackRequire, true);
            const nativeOpened = maybeOpenNativeSettings() || (
              state.rootPatched && !!state.settingsRouter && !state.pendingNativeOpen
            );
            if (mount()) {
              selectPage(state.selectedPageKey);
              state.navButton?.scrollIntoView?.({ block: "center", behavior: "smooth" });
              return true;
            }
            if (!nativeOpened && typeof state.settingsRouter?.openUserSettings === "function") {
              try {
                state.settingsRouter.openUserSettings("my_account_panel");
              } catch (_) {}
            }
            const findSettingsButton = () => safeQuery(
              document,
              `button[aria-label*="User Settings" i], button[aria-label="Settings" i], ` +
                `[role="button"][aria-label*="User Settings" i], [data-list-item-id*="settings" i], ` +
                `button[aria-label*="param" i], [role="button"][aria-label*="param" i], ` +
                `button[aria-label*="einstellungen" i], button[aria-label*="ajustes" i], ` +
                `button[aria-label*="impostazioni" i]`
            );
            let attempts = 0;
            const activateSettingsButton = button => {
              try { button.focus?.({ preventScroll: true }); } catch (_) {}
              let invokedReactHandler = false;
              let target = button;
              for (let depth = 0; target && depth < 3 && !invokedReactHandler; depth += 1) {
                const propsKey = Object.keys(target).find(candidate =>
                  candidate.startsWith("__reactProps$")
                );
                const onClick = propsKey ? target[propsKey]?.onClick : null;
                if (typeof onClick === "function") {
                  try {
                    onClick({
                      type: "click", button: 0, target: button, currentTarget: target,
                      preventDefault() {}, stopPropagation() {}, persist() {},
                      isDefaultPrevented: () => false, isPropagationStopped: () => false
                    });
                    invokedReactHandler = true;
                  } catch (_) {}
                }
                target = target.parentElement;
              }
              if (!invokedReactHandler) {
                try { button.click(); } catch (_) {}
              }
            };
            const poll = () => {
              attempts += 1;
              if (mount()) {
                if (state.openTimer) clearInterval(state.openTimer);
                state.openTimer = 0;
                selectPage(state.selectedPageKey);
                state.navButton?.scrollIntoView?.({ block: "center", behavior: "smooth" });
                return;
              }
              if (attempts === 1 || attempts % 16 === 0) {
                const settingsButton = findSettingsButton();
                state.settingsButtonFound = !!settingsButton;
                if (settingsButton && typeof settingsButton.click === "function") {
                  state.settingsActivationCount += 1;
                  activateSettingsButton(settingsButton);
                }
              }
              if (attempts >= 320 && state.openTimer) {
                clearInterval(state.openTimer);
                state.openTimer = 0;
              }
            };
            poll();
            if (!state.openTimer) state.openTimer = setInterval(poll, 125);
            return true;
          };
          state.dispose = () => {
            state.observer?.disconnect();
            if (state.timer) clearTimeout(state.timer);
            if (state.openTimer) clearInterval(state.openTimer);
            if (state.rangeCommitTimer) clearTimeout(state.rangeCommitTimer);
            restoreDiscordContent();
            state.page?.remove(); state.navButton?.remove(); state.sectionLabel?.remove();
            if (window[key] === state) delete window[key];
          };
          window[key] = state;
          installWebpackHook();
          scheduleMount();
        })();
        """
    }

    static func openSideCordSettingsSource() -> String {
        """
        (() => {
          const bridge = window['\(settingsBridgeKey)'];
          return !!bridge && typeof bridge.open === 'function' && bridge.open() === true;
        })();
        """
    }

}
