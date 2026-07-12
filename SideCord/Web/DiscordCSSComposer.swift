import Foundation

/// Creates the CSS and JavaScript injected into Discord pages.
enum DiscordCSSComposer {
    static let styleElementID = "sidecord-injected-css"
    static let runtimeKey = "__sidecordCSSRuntime_v1__"
    static let managedRootAttributeNames = [
        "data-sidecord-hide-servers",
        "data-sidecord-hide-channels",
        "data-sidecord-hide-members",
        "data-sidecord-hide-account-dock",
        "data-sidecord-simplify-header",
        "data-sidecord-simplify-composer",
        "data-sidecord-hide-composer",
        "data-sidecord-compact-media",
        "data-sidecord-reduce-motion"
    ]

    static func compose(
        preset: CSSPreset,
        compactPresetCSS: String,
        layoutModifiersCSS: String = "",
        layoutOptions: DiscordLayoutOptions = .full,
        customCSS: String,
        customCSSEnabled: Bool
    ) -> String {
        var sections: [String] = []

        if preset == .compact {
            let compactCSS = compactPresetCSS.trimmingCharacters(in: .whitespacesAndNewlines)
            if !compactCSS.isEmpty {
                sections.append(compactCSS)
            }
        }

        if !layoutOptions.isFull {
            let modifiersCSS = layoutModifiersCSS.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modifiersCSS.isEmpty {
                sections.append(modifiersCSS)
            }
        }

        if customCSSEnabled {
            let sanitizedCSS = sanitizeCustomCSS(customCSS)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sanitizedCSS.isEmpty {
                sections.append(sanitizedCSS)
            }
        }

        return sections.joined(separator: "\n\n")
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

    static func rootAttributeNames(for options: DiscordLayoutOptions) -> [String] {
        var attributeNames: [String] = []
        if options.hideServerRail { attributeNames.append("data-sidecord-hide-servers") }
        if options.hideChannelList { attributeNames.append("data-sidecord-hide-channels") }
        if options.hideMemberList { attributeNames.append("data-sidecord-hide-members") }
        if options.hideAccountDock { attributeNames.append("data-sidecord-hide-account-dock") }
        if options.simplifyHeader { attributeNames.append("data-sidecord-simplify-header") }
        if options.simplifyComposer { attributeNames.append("data-sidecord-simplify-composer") }
        if options.hideComposer { attributeNames.append("data-sidecord-hide-composer") }
        if options.compactMedia { attributeNames.append("data-sidecord-compact-media") }
        if options.reduceMotion { attributeNames.append("data-sidecord-reduce-motion") }
        return attributeNames
    }

    static func userScriptSource(css: String, rootAttributeNames: [String] = []) -> String {
        let encodedCSS = javascriptLiteral(css, fallback: "\"\"")
        let encodedManagedAttributes = javascriptLiteral(managedRootAttributeNames, fallback: "[]")
        let encodedRootAttributes = javascriptLiteral(rootAttributeNames, fallback: "[]")

        return """
        (() => {
          const host = window.location.hostname.toLowerCase().replace(/\\.+$/, "");
          const isDiscordHost = host === "discord.com" ||
            host.endsWith(".discord.com") ||
            host === "discordapp.com" ||
            host.endsWith(".discordapp.com");
          if (window.location.protocol !== "https:" || !isDiscordHost) return;

          const id = "\(styleElementID)";
          const runtimeKey = "\(runtimeKey)";
          const css = \(encodedCSS);
          const managedAttributes = \(encodedManagedAttributes);
          const enabledAttributes = \(encodedRootAttributes);

          const previousRuntime = window[runtimeKey];
          if (previousRuntime && typeof previousRuntime.dispose === "function") {
            previousRuntime.dispose();
          }

          const state = {
            css,
            managedAttributes: new Set(managedAttributes),
            enabledAttributes: new Set(enabledAttributes),
            disposed: false,
            repairScheduled: false,
            observedRoot: null,
            observedContainer: null,
            observer: null,
            dispose: null
          };

          let observer;

          const currentStyle = () => document.getElementById(id);

          const isHealthy = () => {
            const root = document.documentElement;
            const container = document.head || root;
            if (!root || state.observedRoot !== root || state.observedContainer !== container) {
              return false;
            }

            for (const name of state.managedAttributes) {
              if (root.hasAttribute(name) !== state.enabledAttributes.has(name)) {
                return false;
              }
            }

            const style = currentStyle();
            if (!state.css) return !style;
            return !!style && style.parentNode === container && style.textContent === state.css;
          };

          const observeTargets = () => {
            if (!state.css && state.enabledAttributes.size === 0) return;

            const root = document.documentElement;
            const container = document.head || root;
            observer.observe(document, { childList: true });
            observer.observe(root, {
              attributes: true,
              attributeFilter: [...state.managedAttributes],
              childList: true
            });
            if (container !== root) {
              observer.observe(container, { childList: true });
            }
            const style = currentStyle();
            if (style) {
              observer.observe(style, { childList: true, characterData: true, subtree: true });
            }
          };

          const reconcile = () => {
            observer.disconnect();

            const root = document.documentElement;
            const container = document.head || root;
            if (!root || !container) return;

            for (const name of state.managedAttributes) {
              root.toggleAttribute(name, state.enabledAttributes.has(name));
            }

            let style = currentStyle();
            if (!state.css) {
              if (style) style.remove();
            } else {
              if (!style) {
                style = document.createElement("style");
                style.id = id;
              }
              if (style.parentNode !== container) {
                container.appendChild(style);
              }
              if (style.textContent !== state.css) {
                style.textContent = state.css;
              }
            }

            state.observedRoot = root;
            state.observedContainer = container;
            observeTargets();
          };

          const scheduleRepair = () => {
            if (state.disposed || state.repairScheduled) return;
            state.repairScheduled = true;
            queueMicrotask(() => {
              state.repairScheduled = false;
              if (!state.disposed && !isHealthy()) reconcile();
            });
          };

          observer = new MutationObserver(() => {
            if (!state.disposed && !isHealthy()) scheduleRepair();
          });
          state.observer = observer;

          state.dispose = () => {
            state.disposed = true;
            observer.disconnect();
            const root = document.documentElement;
            if (root) {
              for (const name of state.managedAttributes) {
                root.removeAttribute(name);
              }
            }
            const style = currentStyle();
            if (style) style.remove();
            if (window[runtimeKey] === state) delete window[runtimeKey];
          };

          window[runtimeKey] = state;
          reconcile();
        })();
        """
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
