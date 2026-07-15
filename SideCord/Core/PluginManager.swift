import CryptoKit
import Combine
import Foundation

enum SideCordPluginCapability: String, Codable, CaseIterable, Sendable {
    case theme
    case layout
    case styleSheet
    case command
}

struct SideCordPluginTheme: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let visualTheme: DiscordVisualTheme
    let accent: SideCordAccent
    let colorScheme: ThemeColorScheme?
}

struct SideCordPluginLayout: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let options: DiscordLayoutOptions
}

struct SideCordPluginStyleSheet: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let css: String
}

enum SideCordPluginAction: String, Codable, CaseIterable, Sendable {
    case reloadDiscord
    case toggleFloatingRail
    case useFullLayout
    case useFocusLayout
    case useReaderLayout
    case useSystemGlassTheme
    case useDiscordTheme
    case useOLEDTheme
    case useSoftTheme
}

struct SideCordPluginCommand: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String?
    let action: SideCordPluginAction
}

struct SideCordPluginContributions: Codable, Equatable, Sendable {
    var themes: [SideCordPluginTheme]
    var layouts: [SideCordPluginLayout]
    var styleSheets: [SideCordPluginStyleSheet]
    var commands: [SideCordPluginCommand]

    init(
        themes: [SideCordPluginTheme] = [],
        layouts: [SideCordPluginLayout] = [],
        styleSheets: [SideCordPluginStyleSheet] = [],
        commands: [SideCordPluginCommand] = []
    ) {
        self.themes = themes
        self.layouts = layouts
        self.styleSheets = styleSheets
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey {
        case themes, layouts, styleSheets, commands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themes = try container.decodeIfPresent([SideCordPluginTheme].self, forKey: .themes) ?? []
        layouts = try container.decodeIfPresent([SideCordPluginLayout].self, forKey: .layouts) ?? []
        styleSheets = try container.decodeIfPresent(
            [SideCordPluginStyleSheet].self,
            forKey: .styleSheets
        ) ?? []
        commands = try container.decodeIfPresent(
            [SideCordPluginCommand].self,
            forKey: .commands
        ) ?? []
    }
}

struct SideCordPluginManifest: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let identifier: String
    let name: String
    let version: String
    let author: String
    let description: String
    let minimumSideCordVersion: String
    let capabilities: [SideCordPluginCapability]
    let contributions: SideCordPluginContributions

    var id: String { identifier }
}

struct SideCordPluginPackage: Codable, Equatable, Sendable {
    let manifest: SideCordPluginManifest
}

enum SideCordPluginSource: String, Codable, Equatable, Sendable {
    case local
    case marketplace
}

struct InstalledSideCordPlugin: Codable, Equatable, Identifiable, Sendable {
    let package: SideCordPluginPackage
    let source: SideCordPluginSource
    let installedAt: Date

    var id: String { package.manifest.identifier }
    var manifest: SideCordPluginManifest { package.manifest }
}

struct SideCordMarketplaceCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let plugins: [SideCordMarketplaceEntry]
}

struct SideCordMarketplaceEntry: Codable, Equatable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let version: String
    let author: String
    let summary: String
    let packageURL: URL
    let sha256: String
    let minimumSideCordVersion: String

    var id: String { identifier }
}

struct SignedSideCordCatalogEnvelope: Codable, Equatable, Sendable {
    let payload: String
    let signature: String
}

enum SideCordPluginError: LocalizedError, Equatable {
    case packageTooLarge
    case invalidJSON
    case unsupportedSchema
    case invalidIdentifier
    case invalidVersion
    case incompatibleVersion
    case invalidManifest(String)
    case unsafeStyleSheet(String)
    case invalidCatalog
    case invalidSignature
    case invalidPackageHash
    case marketplaceNotConfigured
    case pluginNotFound

    var errorDescription: String? {
        switch self {
        case .packageTooLarge: "The plugin package exceeds the 1 MB limit."
        case .invalidJSON: "The file is not a valid SideCord JSON plugin package."
        case .unsupportedSchema: "This plugin uses an unsupported schema version."
        case .invalidIdentifier: "The plugin identifier must use lowercase reverse-DNS syntax."
        case .invalidVersion: "The plugin version is not a valid semantic version."
        case .incompatibleVersion: "This plugin requires a newer version of SideCord."
        case let .invalidManifest(message): message
        case let .unsafeStyleSheet(name):
            "The style sheet “\(name)” contains syntax that SideCord does not allow."
        case .invalidCatalog: "The marketplace catalog is malformed."
        case .invalidSignature: "The marketplace catalog signature is invalid."
        case .invalidPackageHash: "The downloaded plugin does not match the catalog hash."
        case .marketplaceNotConfigured:
            "This build does not contain a curated marketplace URL and public verification key."
        case .pluginNotFound: "The plugin could not be found."
        }
    }
}

struct SideCordMarketplaceConfiguration: Equatable, Sendable {
    let catalogURL: URL
    let publicKey: Data

    static func fromBundle(_ bundle: Bundle = .main) -> Self? {
        guard let rawURL = bundle.object(
            forInfoDictionaryKey: "SideCordMarketplaceCatalogURL"
        ) as? String,
        let catalogURL = URL(string: rawURL),
        catalogURL.scheme == "https",
        let encodedKey = bundle.object(
            forInfoDictionaryKey: "SideCordMarketplacePublicKey"
        ) as? String,
        let publicKey = Data(base64Encoded: encodedKey),
        publicKey.count == 32
        else { return nil }
        return Self(catalogURL: catalogURL, publicKey: publicKey)
    }
}

enum SideCordCatalogVerifier {
    static func verify(envelopeData: Data, publicKey: Data) throws -> SideCordMarketplaceCatalog {
        guard envelopeData.count <= 2_000_000,
              let envelope = try? JSONDecoder.sideCord.decode(
                SignedSideCordCatalogEnvelope.self,
                from: envelopeData
              ),
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature)
        else { throw SideCordPluginError.invalidCatalog }

        let key: Curve25519.Signing.PublicKey
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw SideCordPluginError.invalidSignature
        }
        guard key.isValidSignature(signature, for: payload) else {
            throw SideCordPluginError.invalidSignature
        }
        guard let catalog = try? JSONDecoder.sideCord.decode(
            SideCordMarketplaceCatalog.self,
            from: payload
        ), catalog.schemaVersion == 1,
        catalog.plugins.count <= 500,
        Set(catalog.plugins.map(\.identifier)).count == catalog.plugins.count,
        catalog.plugins.allSatisfy({ entry in
            entry.packageURL.scheme == "https"
                && entry.identifier.range(
                    of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)+$"#,
                    options: .regularExpression
                ) != nil
                && entry.version.range(
                    of: #"^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$"#,
                    options: .regularExpression
                ) != nil
                && entry.sha256.range(
                    of: #"^[a-fA-F0-9]{64}$"#,
                    options: .regularExpression
                ) != nil
        }) else {
            throw SideCordPluginError.invalidCatalog
        }
        return catalog
    }
}

@MainActor
final class SideCordPluginManager: ObservableObject {
    static let maximumPackageSize = 1_000_000

    @Published private(set) var installed: [InstalledSideCordPlugin] = []
    @Published private(set) var enabledIdentifiers: Set<String> = []
    @Published private(set) var catalog: SideCordMarketplaceCatalog?
    @Published private(set) var marketplaceError: String?
    @Published private(set) var isRefreshingMarketplace = false

    private let fileManager: FileManager
    private let rootURL: URL
    private let defaults: UserDefaults
    private let marketplaceConfiguration: SideCordMarketplaceConfiguration?
    private let enabledKey = "plugins.enabledIdentifiers"

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        defaults: UserDefaults = .standard,
        marketplaceConfiguration: SideCordMarketplaceConfiguration? = .fromBundle()
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.marketplaceConfiguration = marketplaceConfiguration
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        enabledIdentifiers = Set(defaults.stringArray(forKey: enabledKey) ?? [])
        reloadInstalledPlugins()
    }

    var isMarketplaceConfigured: Bool { marketplaceConfiguration != nil }

    var combinedStyleSheet: String {
        installed
            .filter { enabledIdentifiers.contains($0.id) }
            .sorted { $0.id < $1.id }
            .flatMap(\.manifest.contributions.styleSheets)
            .map(\.css)
            .joined(separator: "\n\n")
    }

    func isEnabled(_ plugin: InstalledSideCordPlugin) -> Bool {
        enabledIdentifiers.contains(plugin.id)
    }

    func setEnabled(_ enabled: Bool, identifier: String) {
        guard installed.contains(where: { $0.id == identifier }) else { return }
        if enabled { enabledIdentifiers.insert(identifier) }
        else { enabledIdentifiers.remove(identifier) }
        persistEnabledIdentifiers()
        objectWillChange.send()
    }

    @discardableResult
    func install(data: Data, source: SideCordPluginSource) throws -> InstalledSideCordPlugin {
        guard data.count <= Self.maximumPackageSize else {
            throw SideCordPluginError.packageTooLarge
        }
        let package: SideCordPluginPackage
        do { package = try JSONDecoder.sideCord.decode(SideCordPluginPackage.self, from: data) }
        catch { throw SideCordPluginError.invalidJSON }
        try validate(package)
        try fileManager.createDirectory(at: packagesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let destination = packageURL(identifier: package.manifest.identifier)
        if fileManager.fileExists(atPath: destination.path),
           let existing = installed.first(where: { $0.id == package.manifest.identifier }) {
            let backup = backupsURL.appendingPathComponent(
                "\(existing.id)-\(existing.manifest.version).json"
            )
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.copyItem(at: destination, to: backup)
        }

        let record = InstalledSideCordPlugin(
            package: package,
            source: source,
            installedAt: Date()
        )
        let encoded = try JSONEncoder.sideCord.encode(record)
        try encoded.write(to: destination, options: .atomic)
        reloadInstalledPlugins()
        return record
    }

    func uninstall(identifier: String) throws {
        let url = packageURL(identifier: identifier)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SideCordPluginError.pluginNotFound
        }
        try fileManager.removeItem(at: url)
        enabledIdentifiers.remove(identifier)
        persistEnabledIdentifiers()
        reloadInstalledPlugins()
    }

    func rollback(identifier: String) throws {
        let prefix = identifier + "-"
        let backups = try fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }
        let newest = try backups.max { left, right in
            let leftDate = try left.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            let rightDate = try right.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            return leftDate < rightDate
        }
        guard let newest else { throw SideCordPluginError.pluginNotFound }
        let data = try Data(contentsOf: newest)
        let record = try JSONDecoder.sideCord.decode(InstalledSideCordPlugin.self, from: data)
        try validate(record.package)
        try data.write(to: packageURL(identifier: identifier), options: .atomic)
        reloadInstalledPlugins()
    }

    func refreshMarketplace() async {
        guard let marketplaceConfiguration else {
            marketplaceError = SideCordPluginError.marketplaceNotConfigured.localizedDescription
            return
        }
        isRefreshingMarketplace = true
        defer { isRefreshingMarketplace = false }
        do {
            let (data, response) = try await URLSession.shared.data(
                from: marketplaceConfiguration.catalogURL
            )
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw SideCordPluginError.invalidCatalog
            }
            catalog = try SideCordCatalogVerifier.verify(
                envelopeData: data,
                publicKey: marketplaceConfiguration.publicKey
            )
            marketplaceError = nil
        } catch {
            marketplaceError = error.localizedDescription
        }
    }

    func installMarketplaceEntry(_ entry: SideCordMarketplaceEntry) async throws {
        guard marketplaceConfiguration != nil else {
            throw SideCordPluginError.marketplaceNotConfigured
        }
        guard entry.packageURL.scheme == "https" else {
            throw SideCordPluginError.invalidCatalog
        }
        let (data, response) = try await URLSession.shared.data(from: entry.packageURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SideCordPluginError.invalidCatalog
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256.lowercased() else {
            throw SideCordPluginError.invalidPackageHash
        }
        _ = try install(data: data, source: .marketplace)
    }

    func apply(_ theme: SideCordPluginTheme, to settings: AppSettings) {
        settings.visualTheme = theme.visualTheme
        settings.themeAccent = theme.accent
        if let colorScheme = theme.colorScheme {
            settings.themeColorScheme = colorScheme
        }
    }

    func apply(_ layout: SideCordPluginLayout, to settings: AppSettings) {
        settings.customDiscordLayoutOptions = layout.options
        settings.discordLayoutMode = .custom
    }

    func perform(
        _ command: SideCordPluginCommand,
        settings: AppSettings,
        webController: DiscordWebController
    ) {
        switch command.action {
        case .reloadDiscord: webController.reload()
        case .toggleFloatingRail: settings.floatingRailEnabled.toggle()
        case .useFullLayout: settings.applyDiscordLayoutMode(.full)
        case .useFocusLayout: settings.applyDiscordLayoutMode(.focus)
        case .useReaderLayout: settings.applyDiscordLayoutMode(.reader)
        case .useSystemGlassTheme: settings.visualTheme = .systemGlass
        case .useDiscordTheme: settings.visualTheme = .discord
        case .useOLEDTheme: settings.visualTheme = .oled
        case .useSoftTheme: settings.visualTheme = .soft
        }
    }

    func validate(_ package: SideCordPluginPackage) throws {
        let manifest = package.manifest
        guard manifest.schemaVersion == 1 else { throw SideCordPluginError.unsupportedSchema }
        guard manifest.identifier.range(
            of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)+$"#,
            options: .regularExpression
        ) != nil, manifest.identifier.count <= 128 else {
            throw SideCordPluginError.invalidIdentifier
        }
        guard Self.semanticVersion(manifest.version) != nil,
              let required = Self.semanticVersion(manifest.minimumSideCordVersion)
        else { throw SideCordPluginError.invalidVersion }
        if let current = Self.semanticVersion(Self.currentAppVersion),
           Self.compareVersion(required, current) == .orderedDescending {
            throw SideCordPluginError.incompatibleVersion
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80,
              !manifest.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.author.count <= 80,
              manifest.description.count <= 400
        else { throw SideCordPluginError.invalidManifest("Plugin metadata is missing or too long.") }

        let contributionIDs = manifest.contributions.themes.map(\.id)
            + manifest.contributions.layouts.map(\.id)
            + manifest.contributions.styleSheets.map(\.id)
            + manifest.contributions.commands.map(\.id)
        guard Set(contributionIDs).count == contributionIDs.count,
              contributionIDs.allSatisfy({ !$0.isEmpty && $0.count <= 80 })
        else { throw SideCordPluginError.invalidManifest("Contribution identifiers must be unique.") }

        var actualCapabilities = Set<SideCordPluginCapability>()
        if !manifest.contributions.themes.isEmpty { actualCapabilities.insert(.theme) }
        if !manifest.contributions.layouts.isEmpty { actualCapabilities.insert(.layout) }
        if !manifest.contributions.styleSheets.isEmpty {
            actualCapabilities.insert(.styleSheet)
        }
        if !manifest.contributions.commands.isEmpty { actualCapabilities.insert(.command) }
        guard actualCapabilities == Set(manifest.capabilities) else {
            throw SideCordPluginError.invalidManifest(
                "Declared capabilities must exactly match the included contributions."
            )
        }
        for sheet in manifest.contributions.styleSheets {
            if DiscordCSSComposer.validationError(for: sheet.css) != nil {
                throw SideCordPluginError.unsafeStyleSheet(sheet.name)
            }
        }
    }

    private func reloadInstalledPlugins() {
        try? fileManager.createDirectory(at: packagesURL, withIntermediateDirectories: true)
        let urls = (try? fileManager.contentsOfDirectory(
            at: packagesURL,
            includingPropertiesForKeys: nil
        )) ?? []
        installed = urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  data.count <= Self.maximumPackageSize + 4_096,
                  let record = try? JSONDecoder.sideCord.decode(
                    InstalledSideCordPlugin.self,
                    from: data
                  ),
                  (try? validate(record.package)) != nil
            else { return nil }
            return record
        }.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }

        let installedIDs = Set(installed.map(\.id))
        enabledIdentifiers.formIntersection(installedIDs)
        persistEnabledIdentifiers()
    }

    private var packagesURL: URL { rootURL.appendingPathComponent("Packages", isDirectory: true) }
    private var backupsURL: URL { rootURL.appendingPathComponent("Backups", isDirectory: true) }

    private func packageURL(identifier: String) -> URL {
        packagesURL.appendingPathComponent(identifier).appendingPathExtension("json")
    }

    private func persistEnabledIdentifiers() {
        defaults.set(enabledIdentifiers.sorted(), forKey: enabledKey)
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("SideCord/Plugins", isDirectory: true)
    }

    private static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "2.1.0"
    }

    private static func semanticVersion(_ value: String) -> [Int]? {
        let core = value.split(separator: "-", maxSplits: 1).first ?? ""
        let parts = core.split(separator: ".")
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 && numbers.allSatisfy { $0 >= 0 } ? numbers : nil
    }

    private static func compareVersion(_ left: [Int], _ right: [Int]) -> ComparisonResult {
        for (lhs, rhs) in zip(left, right) {
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
        }
        return .orderedSame
    }
}

private extension JSONDecoder {
    static var sideCord: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var sideCord: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
