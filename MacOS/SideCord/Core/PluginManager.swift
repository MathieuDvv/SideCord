import CryptoKit
import Combine
import Darwin
import Foundation

enum SideCordPluginCapability: String, Codable, CaseIterable, Sendable {
    case theme
    case layout
    case styleSheet
    case command
    case webPanel
}

enum SideCordPluginPanelPlacement: String, Codable, CaseIterable, Sendable {
    case bottom
}

enum SideCordPluginDocumentLayoutSelection: String, Codable, CaseIterable, Sendable {
    case first
    case firstVisible
}

enum SideCordPluginDocumentLayoutSlotStrategy: String, Codable, CaseIterable, Sendable {
    case move
    case preserve
}

struct SideCordPluginDocumentLayoutSlot: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let selectors: [String]
    let selection: SideCordPluginDocumentLayoutSelection
    let strategy: SideCordPluginDocumentLayoutSlotStrategy

    init(
        id: String,
        selectors: [String],
        selection: SideCordPluginDocumentLayoutSelection = .first,
        strategy: SideCordPluginDocumentLayoutSlotStrategy = .move
    ) {
        self.id = id
        self.selectors = selectors
        self.selection = selection
        self.strategy = strategy
    }

    private enum CodingKeys: String, CodingKey {
        case id, selectors, selection, strategy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        selectors = try container.decode([String].self, forKey: .selectors)
        selection = try container.decodeIfPresent(
            SideCordPluginDocumentLayoutSelection.self,
            forKey: .selection
        ) ?? .first
        strategy = try container.decodeIfPresent(
            SideCordPluginDocumentLayoutSlotStrategy.self,
            forKey: .strategy
        ) ?? .move
    }
}

struct SideCordPluginDocumentLayout: Codable, Equatable, Identifiable, Sendable {
    let host: String
    let mountSelector: String
    let slots: [SideCordPluginDocumentLayoutSlot]

    var id: String { host }
}

struct SideCordPluginWebPanel: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let placement: SideCordPluginPanelPlacement
    let initialURL: URL
    let allowedNavigationHosts: [String]
    let preferredHeight: Double
    let minimumHeight: Double?
    let maximumHeight: Double?
    let userResizable: Bool?
    let customCSS: String?
    let documentLayouts: [SideCordPluginDocumentLayout]

    init(
        id: String,
        name: String,
        placement: SideCordPluginPanelPlacement,
        initialURL: URL,
        allowedNavigationHosts: [String],
        preferredHeight: Double,
        minimumHeight: Double?,
        maximumHeight: Double?,
        userResizable: Bool?,
        customCSS: String?,
        documentLayouts: [SideCordPluginDocumentLayout] = []
    ) {
        self.id = id
        self.name = name
        self.placement = placement
        self.initialURL = initialURL
        self.allowedNavigationHosts = allowedNavigationHosts
        self.preferredHeight = preferredHeight
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
        self.userResizable = userResizable
        self.customCSS = customCSS
        self.documentLayouts = documentLayouts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, placement, initialURL, allowedNavigationHosts
        case preferredHeight, minimumHeight, maximumHeight, userResizable
        case customCSS, documentLayouts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        placement = try container.decode(SideCordPluginPanelPlacement.self, forKey: .placement)
        initialURL = try container.decode(URL.self, forKey: .initialURL)
        allowedNavigationHosts = try container.decode([String].self, forKey: .allowedNavigationHosts)
        preferredHeight = try container.decode(Double.self, forKey: .preferredHeight)
        minimumHeight = try container.decodeIfPresent(Double.self, forKey: .minimumHeight)
        maximumHeight = try container.decodeIfPresent(Double.self, forKey: .maximumHeight)
        userResizable = try container.decodeIfPresent(Bool.self, forKey: .userResizable)
        customCSS = try container.decodeIfPresent(String.self, forKey: .customCSS)
        documentLayouts = try container.decodeIfPresent(
            [SideCordPluginDocumentLayout].self,
            forKey: .documentLayouts
        ) ?? []
    }
}

struct SideCordPluginPermissions: Codable, Equatable, Sendable {
    var networkHosts: [String]
    var persistentWebsiteData: Bool
    var backgroundAudio: Bool

    init(
        networkHosts: [String] = [],
        persistentWebsiteData: Bool = false,
        backgroundAudio: Bool = false
    ) {
        self.networkHosts = networkHosts
        self.persistentWebsiteData = persistentWebsiteData
        self.backgroundAudio = backgroundAudio
    }

    static let none = SideCordPluginPermissions()

    private enum CodingKeys: String, CodingKey {
        case networkHosts, persistentWebsiteData, backgroundAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        networkHosts = try container.decodeIfPresent(
            [String].self,
            forKey: .networkHosts
        ) ?? []
        persistentWebsiteData = try container.decodeIfPresent(
            Bool.self,
            forKey: .persistentWebsiteData
        ) ?? false
        backgroundAudio = try container.decodeIfPresent(
            Bool.self,
            forKey: .backgroundAudio
        ) ?? false
    }
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
    var webPanels: [SideCordPluginWebPanel]

    init(
        themes: [SideCordPluginTheme] = [],
        layouts: [SideCordPluginLayout] = [],
        styleSheets: [SideCordPluginStyleSheet] = [],
        commands: [SideCordPluginCommand] = [],
        webPanels: [SideCordPluginWebPanel] = []
    ) {
        self.themes = themes
        self.layouts = layouts
        self.styleSheets = styleSheets
        self.commands = commands
        self.webPanels = webPanels
    }

    private enum CodingKeys: String, CodingKey {
        case themes, layouts, styleSheets, commands, webPanels
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
        webPanels = try container.decodeIfPresent(
            [SideCordPluginWebPanel].self,
            forKey: .webPanels
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
    let permissions: SideCordPluginPermissions
    let contributions: SideCordPluginContributions

    var id: String { identifier }

    var catalogPermissionLabels: [String] {
        var labels = Set(capabilities.map(\.rawValue))
        if permissions.persistentWebsiteData { labels.insert("persistentWebsiteData") }
        if permissions.backgroundAudio { labels.insert("backgroundAudio") }
        return labels.sorted()
    }

    init(
        schemaVersion: Int,
        identifier: String,
        name: String,
        version: String,
        author: String,
        description: String,
        minimumSideCordVersion: String,
        capabilities: [SideCordPluginCapability],
        permissions: SideCordPluginPermissions = .none,
        contributions: SideCordPluginContributions
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.minimumSideCordVersion = minimumSideCordVersion
        self.capabilities = capabilities
        self.permissions = permissions
        self.contributions = contributions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, identifier, name, version, author, description
        case minimumSideCordVersion, capabilities, permissions, contributions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decode(String.self, forKey: .author)
        description = try container.decode(String.self, forKey: .description)
        minimumSideCordVersion = try container.decode(
            String.self,
            forKey: .minimumSideCordVersion
        )
        capabilities = try container.decode(
            [SideCordPluginCapability].self,
            forKey: .capabilities
        )
        permissions = try container.decodeIfPresent(
            SideCordPluginPermissions.self,
            forKey: .permissions
        ) ?? .none
        contributions = try container.decode(
            SideCordPluginContributions.self,
            forKey: .contributions
        )
    }
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
    let marketplaceMetadata: SideCordInstalledMarketplaceMetadata?

    var id: String { package.manifest.identifier }
    var manifest: SideCordPluginManifest { package.manifest }

    init(
        package: SideCordPluginPackage,
        source: SideCordPluginSource,
        installedAt: Date,
        marketplaceMetadata: SideCordInstalledMarketplaceMetadata? = nil
    ) {
        self.package = package
        self.source = source
        self.installedAt = installedAt
        self.marketplaceMetadata = marketplaceMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case package, source, installedAt, marketplaceMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        package = try container.decode(SideCordPluginPackage.self, forKey: .package)
        source = try container.decode(SideCordPluginSource.self, forKey: .source)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        marketplaceMetadata = try container.decodeIfPresent(
            SideCordInstalledMarketplaceMetadata.self,
            forKey: .marketplaceMetadata
        )
    }
}

struct SideCordInstalledMarketplaceMetadata: Codable, Equatable, Sendable {
    let repository: URL
    let publisher: String
    let verifiedPublisher: Bool
}

struct SideCordMarketplaceCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let plugins: [SideCordMarketplaceEntry]
    let blocklist: [SideCordMarketplaceBlock]

    init(
        schemaVersion: Int,
        generatedAt: Date,
        plugins: [SideCordMarketplaceEntry],
        blocklist: [SideCordMarketplaceBlock] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.plugins = plugins
        self.blocklist = blocklist
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, plugins, blocklist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        plugins = try container.decode([SideCordMarketplaceEntry].self, forKey: .plugins)
        blocklist = try container.decodeIfPresent(
            [SideCordMarketplaceBlock].self,
            forKey: .blocklist
        ) ?? []
    }
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
    let repository: URL?
    let publisher: String?
    let iconURL: URL?
    let categories: [String]
    let permissions: [String]
    let networkHosts: [String]
    let verifiedPublisher: Bool

    var id: String { identifier }

    var publisherDisplayName: String {
        publisher.map { "Published by @\($0)" } ?? "Publisher identity unavailable"
    }

    var repositoryDisplayName: String? {
        guard let repository else { return nil }
        return repository.pathComponents.dropFirst().joined(separator: "/")
    }

    init(
        identifier: String,
        name: String,
        version: String,
        author: String,
        summary: String,
        packageURL: URL,
        sha256: String,
        minimumSideCordVersion: String,
        repository: URL? = nil,
        publisher: String? = nil,
        iconURL: URL? = nil,
        categories: [String] = [],
        permissions: [String] = [],
        networkHosts: [String] = [],
        verifiedPublisher: Bool = false
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.packageURL = packageURL
        self.sha256 = sha256
        self.minimumSideCordVersion = minimumSideCordVersion
        self.repository = repository
        self.publisher = publisher
        self.iconURL = iconURL
        self.categories = categories
        self.permissions = permissions
        self.networkHosts = networkHosts
        self.verifiedPublisher = verifiedPublisher
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, name, version, author, summary, packageURL, downloadURL
        case sha256, minimumSideCordVersion, repository, publisher, iconURL
        case categories, permissions, networkHosts, verifiedPublisher
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        summary = try container.decode(String.self, forKey: .summary)
        packageURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
            ?? container.decode(URL.self, forKey: .packageURL)
        sha256 = try container.decode(String.self, forKey: .sha256)
        minimumSideCordVersion = try container.decode(
            String.self,
            forKey: .minimumSideCordVersion
        )
        repository = try container.decodeIfPresent(URL.self, forKey: .repository)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        networkHosts = try container.decodeIfPresent([String].self, forKey: .networkHosts) ?? []
        verifiedPublisher = try container.decodeIfPresent(
            Bool.self,
            forKey: .verifiedPublisher
        ) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(author, forKey: .author)
        try container.encode(summary, forKey: .summary)
        try container.encode(packageURL, forKey: .downloadURL)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(minimumSideCordVersion, forKey: .minimumSideCordVersion)
        try container.encodeIfPresent(repository, forKey: .repository)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(iconURL, forKey: .iconURL)
        try container.encode(categories, forKey: .categories)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(networkHosts, forKey: .networkHosts)
        try container.encode(verifiedPublisher, forKey: .verifiedPublisher)
    }
}

struct SideCordMarketplaceBlock: Codable, Equatable, Sendable {
    let identifier: String
    let versions: [String]
    let reason: String

    init(identifier: String, versions: [String] = [], reason: String) {
        self.identifier = identifier
        self.versions = versions
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, versions, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        versions = try container.decodeIfPresent([String].self, forKey: .versions) ?? []
        reason = try container.decode(String.self, forKey: .reason)
    }
}

struct SignedSideCordCatalogEnvelope: Codable, Equatable, Sendable {
    let payload: String
    let signature: String
}

struct SideCordMarketplaceInstallPlan: Equatable, Sendable {
    let entry: SideCordMarketplaceEntry
    let packageData: Data
    let package: SideCordPluginPackage
    let installedVersion: String?
    let addedPermissions: [String]
    let addedNetworkHosts: [String]

    var isUpdate: Bool { installedVersion != nil }

    var confirmationSummary: String {
        let permissionList = isUpdate ? addedPermissions : package.manifest.catalogPermissionLabels
        let hostList = isUpdate ? addedNetworkHosts : package.manifest.permissions.networkHosts
        var details: [String] = []
        if !permissionList.isEmpty {
            details.append("Permissions: \(permissionList.joined(separator: ", "))")
        }
        if !hostList.isEmpty {
            details.append("Network hosts: \(hostList.joined(separator: ", "))")
        }
        if details.isEmpty {
            details.append(isUpdate ? "This update adds no permissions or network hosts." : "This plugin requests no special permissions.")
        }
        return details.joined(separator: "\n")
    }
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
    case catalogPackageMismatch
    case blockedPlugin(String)
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
        case .catalogPackageMismatch:
            "The downloaded package metadata does not match its signed catalog entry."
        case let .blockedPlugin(reason): "This plugin version is blocked: \(reason)"
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
        ), (1 ... 2).contains(catalog.schemaVersion),
        catalog.plugins.count <= 500,
        Set(catalog.plugins.map(\.identifier)).count == catalog.plugins.count,
        catalog.plugins.allSatisfy({ isValid($0, schemaVersion: catalog.schemaVersion) }),
        catalog.blocklist.count <= 500,
        Set(catalog.blocklist.map { "\($0.identifier)\u{0}\($0.versions.sorted())" }).count
            == catalog.blocklist.count,
        catalog.blocklist.allSatisfy(isValid)
        else {
            throw SideCordPluginError.invalidCatalog
        }
        return catalog
    }

    private static func isValid(
        _ entry: SideCordMarketplaceEntry,
        schemaVersion: Int
    ) -> Bool {
        let identifierIsValid = entry.identifier.range(
            of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)+$"#,
            options: .regularExpression
        ) != nil
        let versionIsValid = isSemanticVersion(entry.version)
        let minimumVersionIsValid = isSemanticVersion(entry.minimumSideCordVersion)
        let hashIsValid = entry.sha256.range(
            of: #"^[a-f0-9]{64}$"#,
            options: .regularExpression
        ) != nil
        let categoriesAreValid = entry.categories.count <= 12
            && Set(entry.categories).count == entry.categories.count
            && entry.categories.allSatisfy {
                $0.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil
            }
        let validPermissionNames = Set(
            SideCordPluginCapability.allCases.map(\.rawValue)
                + ["persistentWebsiteData", "backgroundAudio"]
        )
        let permissionsAreValid = entry.permissions.count <= validPermissionNames.count
            && Set(entry.permissions).count == entry.permissions.count
            && entry.permissions.allSatisfy(validPermissionNames.contains)
        let hostsAreValid = entry.networkHosts.count <= SideCordPluginManager.maximumWebPanelHosts
            && Set(entry.networkHosts).count == entry.networkHosts.count
            && entry.networkHosts.allSatisfy(SideCordPluginManager.isValidExactHost)

        guard identifierIsValid, versionIsValid, minimumVersionIsValid, hashIsValid,
              !entry.name.isEmpty, entry.name.count <= 80,
              !entry.summary.isEmpty, entry.summary.count <= 280,
              isSafeHTTPSURL(entry.packageURL), categoriesAreValid,
              permissionsAreValid, hostsAreValid,
              entry.iconURL.map(isSafeHTTPSURL) ?? true
        else { return false }

        guard schemaVersion >= 2 else { return true }
        guard let repository = entry.repository,
              let publisher = entry.publisher,
              let identity = githubRepositoryIdentity(repository),
              identity.owner.caseInsensitiveCompare(publisher) == .orderedSame,
              entry.packageURL.host(percentEncoded: false)?.lowercased() == "github.com",
              entry.packageURL.path.hasPrefix("/\(identity.owner)/\(identity.repository)/releases/download/")
        else { return false }
        return true
    }

    private static func isValid(_ block: SideCordMarketplaceBlock) -> Bool {
        block.identifier.range(
            of: #"^[a-z0-9]+(?:[.-][a-z0-9]+)+$"#,
            options: .regularExpression
        ) != nil
            && block.versions.count <= 100
            && Set(block.versions).count == block.versions.count
            && block.versions.allSatisfy(isSemanticVersion)
            && !block.reason.isEmpty
            && block.reason.count <= 240
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(
            of: #"^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isSafeHTTPSURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.user == nil
            && url.password == nil
            && url.port == nil
            && url.host(percentEncoded: false) != nil
    }

    private static func githubRepositoryIdentity(
        _ url: URL
    ) -> (owner: String, repository: String)? {
        guard isSafeHTTPSURL(url),
              url.host(percentEncoded: false)?.lowercased() == "github.com",
              url.query == nil,
              url.fragment == nil
        else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2 else { return nil }
        let repository = components[1].hasSuffix(".git")
            ? String(components[1].dropLast(4))
            : components[1]
        guard !components[0].isEmpty, !repository.isEmpty else { return nil }
        return (components[0], repository)
    }
}

@MainActor
final class SideCordPluginManager: ObservableObject {
    nonisolated static let maximumPackageSize = 1_000_000
    nonisolated static let maximumWebPanelCSSSize = 65_536
    nonisolated static let maximumWebPanelHosts = 16
    nonisolated static let maximumDocumentLayoutSlots = 8
    nonisolated static let maximumDocumentLayoutSelectors = 8
    nonisolated static let maximumDocumentLayoutSelectorLength = 256

    @Published private(set) var installed: [InstalledSideCordPlugin] = []
    @Published private(set) var enabledIdentifiers: Set<String> = []
    @Published private(set) var catalog: SideCordMarketplaceCatalog?
    @Published private(set) var catalogIsCached = false
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
        loadCachedMarketplace()
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
        if enabled {
            if installed.first(where: { $0.id == identifier })?
                .manifest.contributions.webPanels.isEmpty == false {
                let otherWebPanelPluginIDs = installed.compactMap { plugin in
                    plugin.id != identifier && !plugin.manifest.contributions.webPanels.isEmpty
                        ? plugin.id
                        : nil
                }
                enabledIdentifiers.subtract(otherWebPanelPluginIDs)
            }
            enabledIdentifiers.insert(identifier)
        }
        else { enabledIdentifiers.remove(identifier) }
        persistEnabledIdentifiers()
        objectWillChange.send()
    }

    @discardableResult
    func install(
        data: Data,
        source: SideCordPluginSource,
        marketplaceMetadata: SideCordInstalledMarketplaceMetadata? = nil
    ) throws -> InstalledSideCordPlugin {
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
            installedAt: Date(),
            marketplaceMetadata: marketplaceMetadata
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
            let verifiedCatalog = try SideCordCatalogVerifier.verify(
                envelopeData: data,
                publicKey: marketplaceConfiguration.publicKey
            )
            try cacheMarketplaceEnvelope(data)
            applyMarketplaceCatalog(verifiedCatalog, isCached: false)
            marketplaceError = nil
        } catch {
            marketplaceError = catalog == nil
                ? error.localizedDescription
                : "Couldn’t refresh the library. Showing the last verified catalog."
        }
    }

    func availableUpdate(
        for plugin: InstalledSideCordPlugin
    ) -> SideCordMarketplaceEntry? {
        catalog?.plugins.first { entry in
            entry.identifier == plugin.id
                && Self.isVersion(entry.version, newerThan: plugin.manifest.version)
                && blockReason(for: entry) == nil
        }
    }

    func isInstalled(_ entry: SideCordMarketplaceEntry) -> Bool {
        installed.contains { $0.id == entry.identifier }
    }

    func prepareMarketplaceInstallation(
        _ entry: SideCordMarketplaceEntry
    ) async throws -> SideCordMarketplaceInstallPlan {
        guard marketplaceConfiguration != nil else {
            throw SideCordPluginError.marketplaceNotConfigured
        }
        guard catalog?.plugins.contains(entry) == true else {
            throw SideCordPluginError.invalidCatalog
        }
        if let reason = blockReason(for: entry) {
            throw SideCordPluginError.blockedPlugin(reason)
        }
        guard entry.packageURL.scheme == "https" else {
            throw SideCordPluginError.invalidCatalog
        }
        let (data, response) = try await URLSession.shared.data(from: entry.packageURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SideCordPluginError.invalidCatalog
        }
        return try prepareMarketplaceInstallation(entry, packageData: data)
    }

    func prepareMarketplaceInstallation(
        _ entry: SideCordMarketplaceEntry,
        packageData data: Data
    ) throws -> SideCordMarketplaceInstallPlan {
        guard catalog?.plugins.contains(entry) == true else {
            throw SideCordPluginError.invalidCatalog
        }
        if let reason = blockReason(for: entry) {
            throw SideCordPluginError.blockedPlugin(reason)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256 else {
            throw SideCordPluginError.invalidPackageHash
        }
        guard data.count <= Self.maximumPackageSize,
              let package = try? JSONDecoder.sideCord.decode(
                  SideCordPluginPackage.self,
                  from: data
              )
        else { throw SideCordPluginError.invalidJSON }
        try validate(package)

        let manifest = package.manifest
        guard manifest.identifier == entry.identifier,
              manifest.version == entry.version,
              manifest.minimumSideCordVersion == entry.minimumSideCordVersion
        else { throw SideCordPluginError.catalogPackageMismatch }
        if catalog?.schemaVersion ?? 1 >= 2 {
            guard manifest.catalogPermissionLabels == entry.permissions.sorted(),
                  manifest.permissions.networkHosts.sorted() == entry.networkHosts.sorted()
            else { throw SideCordPluginError.catalogPackageMismatch }
        }

        let existing = installed.first { $0.id == entry.identifier }
        if let existing,
           !Self.isVersion(entry.version, newerThan: existing.manifest.version) {
            throw SideCordPluginError.catalogPackageMismatch
        }
        let oldPermissions = Set(existing?.manifest.catalogPermissionLabels ?? [])
        let oldHosts = Set(existing?.manifest.permissions.networkHosts ?? [])
        return SideCordMarketplaceInstallPlan(
            entry: entry,
            packageData: data,
            package: package,
            installedVersion: existing?.manifest.version,
            addedPermissions: Set(manifest.catalogPermissionLabels)
                .subtracting(oldPermissions)
                .sorted(),
            addedNetworkHosts: Set(manifest.permissions.networkHosts)
                .subtracting(oldHosts)
                .sorted()
        )
    }

    @discardableResult
    func commitMarketplaceInstallation(
        _ plan: SideCordMarketplaceInstallPlan
    ) throws -> InstalledSideCordPlugin {
        guard catalog?.plugins.contains(plan.entry) == true else {
            throw SideCordPluginError.invalidCatalog
        }
        if let reason = blockReason(for: plan.entry) {
            throw SideCordPluginError.blockedPlugin(reason)
        }
        let repository = plan.entry.repository
        let publisher = plan.entry.publisher
        guard let repository, let publisher else {
            if catalog?.schemaVersion ?? 1 >= 2 {
                throw SideCordPluginError.catalogPackageMismatch
            }
            return try install(data: plan.packageData, source: .marketplace)
        }
        return try install(
            data: plan.packageData,
            source: .marketplace,
            marketplaceMetadata: SideCordInstalledMarketplaceMetadata(
                repository: repository,
                publisher: publisher,
                verifiedPublisher: plan.entry.verifiedPublisher
            )
        )
    }

    func installMarketplaceEntry(_ entry: SideCordMarketplaceEntry) async throws {
        let plan = try await prepareMarketplaceInstallation(entry)
        _ = try commitMarketplaceInstallation(plan)
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
        guard (1 ... 3).contains(manifest.schemaVersion) else {
            throw SideCordPluginError.unsupportedSchema
        }
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
            + manifest.contributions.webPanels.map(\.id)
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
        if !manifest.contributions.webPanels.isEmpty { actualCapabilities.insert(.webPanel) }
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
        try validateWebPanels(in: manifest)
    }

    private func validateWebPanels(in manifest: SideCordPluginManifest) throws {
        let panels = manifest.contributions.webPanels
        if manifest.schemaVersion == 1 {
            guard panels.isEmpty,
                  !manifest.capabilities.contains(.webPanel),
                  manifest.permissions == .none
            else { throw SideCordPluginError.unsupportedSchema }
            return
        }

        guard panels.count <= 1 else {
            throw SideCordPluginError.invalidManifest(
                "A plugin can contribute at most one web panel."
            )
        }

        let permissionHosts = manifest.permissions.networkHosts
        guard permissionHosts.count <= Self.maximumWebPanelHosts,
              Set(permissionHosts).count == permissionHosts.count,
              permissionHosts.allSatisfy(Self.isValidExactHost)
        else {
            throw SideCordPluginError.invalidManifest(
                "Network permissions must contain at most 16 unique, exact hostnames."
            )
        }

        guard !panels.isEmpty || manifest.permissions == .none else {
            throw SideCordPluginError.invalidManifest(
                "Web-panel permissions require a web-panel contribution."
            )
        }

        for panel in panels {
            guard !panel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  panel.name.count <= 80,
                  panel.placement == .bottom
            else {
                throw SideCordPluginError.invalidManifest(
                    "Web-panel names and placements must be valid."
                )
            }

            guard Self.isSafeWebPanelURL(panel.initialURL),
                  let initialHost = Self.normalizedExactHost(panel.initialURL)
            else {
                throw SideCordPluginError.invalidManifest(
                    "Web panels require an HTTPS initial URL without credentials, ports, IP addresses, or custom schemes."
                )
            }

            let allowedHosts = panel.allowedNavigationHosts
            guard !allowedHosts.isEmpty,
                  allowedHosts.count <= Self.maximumWebPanelHosts,
                  Set(allowedHosts).count == allowedHosts.count,
                  allowedHosts.allSatisfy(Self.isValidExactHost),
                  allowedHosts.contains(initialHost),
                  allowedHosts.allSatisfy(permissionHosts.contains)
            else {
                throw SideCordPluginError.invalidManifest(
                    "Every allowed navigation host must be exact, include the initial host, and appear in network permissions."
                )
            }

            let heights = [panel.preferredHeight, panel.minimumHeight, panel.maximumHeight]
                .compactMap { $0 }
            guard heights.allSatisfy({ $0.isFinite && $0 > 0 }),
                  panel.minimumHeight.map({ minimum in
                      panel.maximumHeight.map { minimum <= $0 } ?? true
                  }) ?? true
            else {
                throw SideCordPluginError.invalidManifest(
                    "Web-panel heights must be positive, finite, and ordered."
                )
            }

            if let css = panel.customCSS {
                guard css.utf8.count <= Self.maximumWebPanelCSSSize,
                      DiscordCSSComposer.validationError(for: css) == nil
                else { throw SideCordPluginError.unsafeStyleSheet(panel.name) }
            }

            try validateDocumentLayouts(
                panel.documentLayouts,
                schemaVersion: manifest.schemaVersion,
                allowedHosts: allowedHosts
            )
        }
    }

    private func validateDocumentLayouts(
        _ layouts: [SideCordPluginDocumentLayout],
        schemaVersion: Int,
        allowedHosts: [String]
    ) throws {
        guard layouts.isEmpty || schemaVersion >= 3 else {
            throw SideCordPluginError.unsupportedSchema
        }
        guard layouts.count <= Self.maximumWebPanelHosts,
              Set(layouts.map(\.host)).count == layouts.count
        else {
            throw SideCordPluginError.invalidManifest(
                "Document layouts must use unique declared hosts."
            )
        }

        for layout in layouts {
            guard allowedHosts.contains(layout.host),
                  Self.isConservativeDocumentSelector(layout.mountSelector),
                  !layout.slots.isEmpty,
                  layout.slots.count <= Self.maximumDocumentLayoutSlots,
                  Set(layout.slots.map(\.id)).count == layout.slots.count
            else {
                throw SideCordPluginError.invalidManifest(
                    "Document layouts contain an invalid host, mount selector, or slot list."
                )
            }

            for slot in layout.slots {
                guard slot.id.range(
                    of: #"^[a-z][a-z0-9-]{0,39}$"#,
                    options: .regularExpression
                ) != nil,
                !slot.selectors.isEmpty,
                slot.selectors.count <= Self.maximumDocumentLayoutSelectors,
                Set(slot.selectors).count == slot.selectors.count,
                slot.selectors.allSatisfy(Self.isConservativeDocumentSelector)
                else {
                    throw SideCordPluginError.invalidManifest(
                        "Document-layout slots require unique identifiers and safe selectors."
                    )
                }
            }
        }
    }

    nonisolated static func isConservativeDocumentSelector(_ selector: String) -> Bool {
        guard !selector.isEmpty,
              selector.count <= maximumDocumentLayoutSelectorLength,
              selector == selector.trimmingCharacters(in: .whitespacesAndNewlines),
              !selector.contains("  "),
              selector.range(
                of: #"^[A-Za-z0-9_.#\[\]='\" -]+(?: > [A-Za-z0-9_.#\[\]='\" -]+)*$"#,
                options: .regularExpression
              ) != nil
        else { return false }

        var bracketDepth = 0
        var quote: Character?
        for character in selector {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" {
                bracketDepth += 1
            } else if character == "]" {
                bracketDepth -= 1
                if bracketDepth < 0 { return false }
            }
        }
        return quote == nil && bracketDepth == 0
    }

    nonisolated static func isSafeWebPanelURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              normalizedExactHost(url) != nil
        else { return false }
        return true
    }

    nonisolated static func normalizedExactHost(_ url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), isValidExactHost(host) else {
            return nil
        }
        return host
    }

    nonisolated static func isValidExactHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              host.count <= 253,
              host == host.lowercased(),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("*"),
              !isIPAddress(host)
        else { return false }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            label.range(
                of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
        }
    }

    func blockReason(for entry: SideCordMarketplaceEntry) -> String? {
        blockReason(identifier: entry.identifier, version: entry.version)
    }

    private func blockReason(identifier: String, version: String) -> String? {
        catalog?.blocklist.first { block in
            block.identifier == identifier
                && (block.versions.isEmpty || block.versions.contains(version))
        }?.reason
    }

    private func loadCachedMarketplace() {
        guard let marketplaceConfiguration,
              let data = try? Data(contentsOf: marketplaceCacheURL),
              let cached = try? SideCordCatalogVerifier.verify(
                  envelopeData: data,
                  publicKey: marketplaceConfiguration.publicKey
              )
        else { return }
        applyMarketplaceCatalog(cached, isCached: true)
    }

    private func cacheMarketplaceEnvelope(_ data: Data) throws {
        try fileManager.createDirectory(
            at: marketplaceCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: marketplaceCacheURL, options: .atomic)
    }

    private func applyMarketplaceCatalog(
        _ nextCatalog: SideCordMarketplaceCatalog,
        isCached: Bool
    ) {
        catalog = nextCatalog
        catalogIsCached = isCached
        let blockedInstalledIdentifiers = installed.compactMap { plugin in
            nextCatalog.blocklist.contains { block in
                block.identifier == plugin.id
                    && (block.versions.isEmpty || block.versions.contains(plugin.manifest.version))
            } ? plugin.id : nil
        }
        if !blockedInstalledIdentifiers.isEmpty {
            enabledIdentifiers.subtract(blockedInstalledIdentifiers)
            persistEnabledIdentifiers()
        }
    }

    nonisolated private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return host.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1
                || inet_pton(AF_INET6, pointer, &ipv6) == 1
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
    private var marketplaceCacheURL: URL {
        rootURL
            .appendingPathComponent("Marketplace", isDirectory: true)
            .appendingPathComponent("catalog-envelope.json")
    }

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
            ?? "2.5.0"
    }

    nonisolated static func isVersion(
        _ candidate: String,
        newerThan installed: String
    ) -> Bool {
        guard let candidateVersion = semanticVersion(candidate),
              let installedVersion = semanticVersion(installed)
        else { return false }
        return compareVersion(candidateVersion, installedVersion) == .orderedDescending
    }

    private struct SemanticVersion {
        let core: [Int]
        let prerelease: [Substring]?
    }

    nonisolated private static func semanticVersion(_ value: String) -> SemanticVersion? {
        let versionParts = value.split(separator: "-", maxSplits: 1)
        let parts = versionParts[0].split(separator: ".")
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        let prerelease: [Substring]?
        if versionParts.count == 2 {
            let identifiers = versionParts[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            prerelease = identifiers
        } else {
            prerelease = nil
        }
        return SemanticVersion(core: numbers, prerelease: prerelease)
    }

    nonisolated private static func compareVersion(
        _ left: SemanticVersion,
        _ right: SemanticVersion
    ) -> ComparisonResult {
        for (lhs, rhs) in zip(left.core, right.core) {
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
        }
        switch (left.prerelease, right.prerelease) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (.some(lhs), .some(rhs)):
            for index in 0..<min(lhs.count, rhs.count) {
                let leftIdentifier = lhs[index]
                let rightIdentifier = rhs[index]
                if leftIdentifier == rightIdentifier { continue }
                switch (Int(leftIdentifier), Int(rightIdentifier)) {
                case let (.some(leftNumber), .some(rightNumber)):
                    return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
                case (.some, nil):
                    return .orderedAscending
                case (nil, .some):
                    return .orderedDescending
                case (nil, nil):
                    return leftIdentifier.lexicographicallyPrecedes(rightIdentifier)
                        ? .orderedAscending
                        : .orderedDescending
                }
            }
            if lhs.count == rhs.count { return .orderedSame }
            return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
        }
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
