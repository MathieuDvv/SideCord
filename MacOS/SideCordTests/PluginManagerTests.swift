import CryptoKit
import XCTest
@testable import SideCord

final class PluginManagerTests: XCTestCase {
    func testMarketplaceVersionComparisonFollowsPrereleasePrecedence() {
        XCTAssertTrue(SideCordPluginManager.isVersion("1.2.4", newerThan: "1.2.4-beta.2"))
        XCTAssertTrue(SideCordPluginManager.isVersion("1.2.4-beta.11", newerThan: "1.2.4-beta.2"))
        XCTAssertTrue(SideCordPluginManager.isVersion("1.2.4-rc.1", newerThan: "1.2.4-beta.11"))
        XCTAssertFalse(SideCordPluginManager.isVersion("1.2.4-beta.2", newerThan: "1.2.4"))
        XCTAssertFalse(SideCordPluginManager.isVersion("1.2.4", newerThan: "1.2.4"))
    }

    private var temporaryRoot: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        suiteName = "SideCordPluginTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @MainActor
    func testPluginLifecycleInstallsDisabledAndRestoresBackup() throws {
        let manager = makeManager()
        let first = package(version: "1.0.0", css: ".fixture { color: red; }")
        let second = package(version: "1.1.0", css: ".fixture { color: blue; }")

        try manager.install(data: encode(first), source: .local)
        XCTAssertEqual(manager.installed.map(\.manifest.version), ["1.0.0"])
        XCTAssertFalse(manager.isEnabled(manager.installed[0]))
        XCTAssertTrue(manager.combinedStyleSheet.isEmpty)

        manager.setEnabled(true, identifier: first.manifest.identifier)
        XCTAssertEqual(manager.combinedStyleSheet, ".fixture { color: red; }")

        try manager.install(data: encode(second), source: .marketplace)
        XCTAssertEqual(manager.installed.map(\.manifest.version), ["1.1.0"])
        XCTAssertEqual(manager.combinedStyleSheet, ".fixture { color: blue; }")

        try manager.rollback(identifier: first.manifest.identifier)
        XCTAssertEqual(manager.installed.map(\.manifest.version), ["1.0.0"])
        XCTAssertEqual(manager.combinedStyleSheet, ".fixture { color: red; }")

        try manager.uninstall(identifier: first.manifest.identifier)
        XCTAssertTrue(manager.installed.isEmpty)
        XCTAssertTrue(manager.enabledIdentifiers.isEmpty)
    }

    @MainActor
    func testSchemaV1PackageWithoutPermissionsStillDecodesAndInstalls() throws {
        let data = Data(
            """
            {
              "manifest": {
                "schemaVersion": 1,
                "identifier": "com.sidecord.legacy",
                "name": "Legacy",
                "version": "1.0.0",
                "author": "SideCord Tests",
                "description": "A schema v1 package.",
                "minimumSideCordVersion": "2.0.0",
                "capabilities": ["styleSheet"],
                "contributions": {
                  "styleSheets": [{
                    "id": "legacy-css",
                    "name": "Legacy CSS",
                    "css": ".legacy { color: red; }"
                  }]
                }
              }
            }
            """.utf8
        )

        let manager = makeManager()
        let installed = try manager.install(data: data, source: .local)

        XCTAssertEqual(installed.manifest.schemaVersion, 1)
        XCTAssertEqual(installed.manifest.permissions, .none)
        XCTAssertTrue(installed.manifest.contributions.webPanels.isEmpty)
    }

    @MainActor
    func testSchemaV2WebPanelDecodesAndValidates() throws {
        let data = Data(
            """
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
                  "webPanels": [{
                    "id": "youtube-music-player",
                    "name": "YouTube Music",
                    "placement": "bottom",
                    "initialURL": "https://music.youtube.com/",
                    "allowedNavigationHosts": ["music.youtube.com", "accounts.google.com"],
                    "preferredHeight": 190,
                    "minimumHeight": 140,
                    "maximumHeight": 300,
                    "userResizable": true,
                    "customCSS": "ytmusic-nav-bar { display: none !important; }"
                  }]
                }
              }
            }
            """.utf8
        )

        let manager = makeManager()
        let installed = try manager.install(data: data, source: .local)
        let panel = try XCTUnwrap(installed.manifest.contributions.webPanels.first)

        XCTAssertEqual(installed.manifest.schemaVersion, 2)
        XCTAssertEqual(panel.id, "youtube-music-player")
        XCTAssertEqual(panel.initialURL.absoluteString, "https://music.youtube.com/")
        XCTAssertEqual(installed.manifest.permissions.networkHosts.count, 2)
        XCTAssertTrue(installed.manifest.permissions.persistentWebsiteData)
        XCTAssertTrue(installed.manifest.permissions.backgroundAudio)
        XCTAssertTrue(panel.documentLayouts.isEmpty)
    }

    @MainActor
    func testSchemaV3DocumentLayoutDecodesAndValidates() throws {
        let manager = makeManager()
        let package = webPanelPackage(
            schemaVersion: 3,
            documentLayouts: [
                SideCordPluginDocumentLayout(
                    host: "music.youtube.com",
                    mountSelector: "ytmusic-app",
                    slots: [
                        SideCordPluginDocumentLayoutSlot(
                            id: "content",
                            selectors: ["ytmusic-browse-response", "ytmusic-search-page"],
                            selection: .firstVisible
                        ),
                        SideCordPluginDocumentLayoutSlot(
                            id: "player",
                            selectors: ["ytmusic-player-bar"],
                            strategy: .preserve
                        )
                    ]
                )
            ]
        )

        let installed = try manager.install(data: encode(package), source: .local)
        let layout = try XCTUnwrap(
            installed.manifest.contributions.webPanels.first?.documentLayouts.first
        )

        XCTAssertEqual(installed.manifest.schemaVersion, 3)
        XCTAssertEqual(layout.host, "music.youtube.com")
        XCTAssertEqual(layout.slots.map(\.id), ["content", "player"])
        XCTAssertEqual(layout.slots.first?.selection, .firstVisible)
        XCTAssertEqual(layout.slots.first?.strategy, .move)
        XCTAssertEqual(layout.slots.last?.strategy, .preserve)
    }

    @MainActor
    func testWebPanelValidationRejectsUnsafeURLsHostsAndHeights() throws {
        let manager = makeManager()
        let invalidPackages = [
            webPanelPackage(initialURL: "http://music.youtube.com/"),
            webPanelPackage(initialURL: "https://user@music.youtube.com/"),
            webPanelPackage(initialURL: "https://music.youtube.com:8443/"),
            webPanelPackage(
                initialURL: "https://127.0.0.1/",
                allowedHosts: ["127.0.0.1"],
                permissionHosts: ["127.0.0.1"]
            ),
            webPanelPackage(
                allowedHosts: ["music.youtube.com", "*.google.com"],
                permissionHosts: ["music.youtube.com", "*.google.com"]
            ),
            webPanelPackage(
                allowedHosts: ["music.youtube.com", "accounts.google.com"],
                permissionHosts: ["music.youtube.com"]
            ),
            webPanelPackage(preferredHeight: -1),
            webPanelPackage(minimumHeight: 300, maximumHeight: 140)
        ]

        for package in invalidPackages {
            XCTAssertThrowsError(try manager.validate(package), String(describing: package)) {
                guard case SideCordPluginError.invalidManifest = $0 else {
                    return XCTFail("Unexpected error: \($0)")
                }
            }
        }
    }

    @MainActor
    func testWebPanelValidationRejectsCapabilityPermissionAndCSSMismatches() throws {
        let manager = makeManager()
        let missingCapability = webPanelPackage(capabilities: [])
        let schemaOne = webPanelPackage(schemaVersion: 1)
        let permissionsWithoutPanel = SideCordPluginPackage(manifest: SideCordPluginManifest(
            schemaVersion: 2,
            identifier: "com.sidecord.permissions-only",
            name: "Permissions Only",
            version: "1.0.0",
            author: "SideCord Tests",
            description: "Invalid permissions.",
            minimumSideCordVersion: "2.3.0",
            capabilities: [],
            permissions: SideCordPluginPermissions(networkHosts: ["example.com"]),
            contributions: SideCordPluginContributions()
        ))
        let unsafeCSS = webPanelPackage(
            customCSS: ".player { background: url(https://example.com/a.png); }"
        )

        XCTAssertThrowsError(try manager.validate(missingCapability))
        XCTAssertThrowsError(try manager.validate(schemaOne)) { error in
            XCTAssertEqual(error as? SideCordPluginError, .unsupportedSchema)
        }
        XCTAssertThrowsError(try manager.validate(permissionsWithoutPanel))
        XCTAssertThrowsError(try manager.validate(unsafeCSS)) { error in
            XCTAssertEqual(error as? SideCordPluginError, .unsafeStyleSheet("Web Panel"))
        }
    }

    @MainActor
    func testDocumentLayoutValidationRejectsOldSchemasHostsAndUnsafeSelectors() throws {
        let manager = makeManager()
        let validLayout = SideCordPluginDocumentLayout(
            host: "music.youtube.com",
            mountSelector: "ytmusic-app",
            slots: [
                SideCordPluginDocumentLayoutSlot(
                    id: "player",
                    selectors: ["ytmusic-player-bar"]
                )
            ]
        )
        let wrongHost = SideCordPluginDocumentLayout(
            host: "accounts.google.com",
            mountSelector: "ytmusic-app",
            slots: validLayout.slots
        )
        let unsafeSelector = SideCordPluginDocumentLayout(
            host: "music.youtube.com",
            mountSelector: "ytmusic-app, script",
            slots: validLayout.slots
        )

        XCTAssertThrowsError(try manager.validate(webPanelPackage(
            schemaVersion: 2,
            documentLayouts: [validLayout]
        ))) { error in
            XCTAssertEqual(error as? SideCordPluginError, .unsupportedSchema)
        }
        XCTAssertThrowsError(try manager.validate(webPanelPackage(
            schemaVersion: 3,
            documentLayouts: [wrongHost]
        )))
        XCTAssertThrowsError(try manager.validate(webPanelPackage(
            schemaVersion: 3,
            documentLayouts: [unsafeSelector]
        )))
        XCTAssertTrue(SideCordPluginManager.isConservativeDocumentSelector(
            "ytmusic-app > ytmusic-nav-bar"
        ))
        XCTAssertFalse(SideCordPluginManager.isConservativeDocumentSelector(
            "ytmusic-app:has(script)"
        ))
    }

    @MainActor
    func testOnlyOneWebPanelPluginCanBeEnabled() throws {
        let manager = makeManager()
        try manager.install(
            data: encode(webPanelPackage(identifier: "com.sidecord.panel-one")),
            source: .local
        )
        try manager.install(
            data: encode(webPanelPackage(identifier: "com.sidecord.panel-two")),
            source: .local
        )

        manager.setEnabled(true, identifier: "com.sidecord.panel-one")
        XCTAssertEqual(manager.enabledIdentifiers, ["com.sidecord.panel-one"])

        manager.setEnabled(true, identifier: "com.sidecord.panel-two")
        XCTAssertEqual(manager.enabledIdentifiers, ["com.sidecord.panel-two"])
    }

    @MainActor
    func testPluginValidationRejectsCapabilitiesAndUnsafeCSS() throws {
        let manager = makeManager()
        var mismatched = package(version: "1.0.0", css: ".fixture { color: red; }")
        mismatched = SideCordPluginPackage(manifest: SideCordPluginManifest(
            schemaVersion: mismatched.manifest.schemaVersion,
            identifier: mismatched.manifest.identifier,
            name: mismatched.manifest.name,
            version: mismatched.manifest.version,
            author: mismatched.manifest.author,
            description: mismatched.manifest.description,
            minimumSideCordVersion: mismatched.manifest.minimumSideCordVersion,
            capabilities: [],
            contributions: mismatched.manifest.contributions
        ))
        XCTAssertThrowsError(try manager.validate(mismatched)) { error in
            guard case SideCordPluginError.invalidManifest = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let unsafe = package(
            version: "1.0.0",
            css: ".fixture { background: url(https://example.com/a.png); }"
        )
        XCTAssertThrowsError(try manager.validate(unsafe)) { error in
            XCTAssertEqual(error as? SideCordPluginError, .unsafeStyleSheet("Fixture CSS"))
        }
    }

    @MainActor
    func testSignedCatalogVerifierRejectsTampering() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = try JSONEncoder.iso8601.encode(SideCordMarketplaceCatalog(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plugins: []
        ))
        let signature = try privateKey.signature(for: payload)
        let envelope = SignedSideCordCatalogEnvelope(
            payload: payload.base64EncodedString(),
            signature: signature.base64EncodedString()
        )
        let envelopeData = try JSONEncoder().encode(envelope)

        let decoded = try SideCordCatalogVerifier.verify(
            envelopeData: envelopeData,
            publicKey: privateKey.publicKey.rawRepresentation
        )
        XCTAssertEqual(decoded.plugins, [])

        var tampered = payload
        tampered.append(0)
        let tamperedEnvelope = SignedSideCordCatalogEnvelope(
            payload: tampered.base64EncodedString(),
            signature: signature.base64EncodedString()
        )
        XCTAssertThrowsError(try SideCordCatalogVerifier.verify(
            envelopeData: JSONEncoder().encode(tamperedEnvelope),
            publicKey: privateKey.publicKey.rawRepresentation
        )) { error in
            XCTAssertEqual(error as? SideCordPluginError, .invalidSignature)
        }
    }

    @MainActor
    func testCachedCatalogPlansPermissionAwareUpdateAndPreservesEnabledState() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let initial = package(version: "1.0.0", css: ".fixture { color: red; }")
        let update = webPanelPackage(
            schemaVersion: 2,
            identifier: initial.manifest.identifier,
            version: "1.1.0",
            permissionHosts: ["music.youtube.com", "accounts.google.com"],
            backgroundAudio: true,
            persistentWebsiteData: true
        )
        let updateData = try encode(update)
        let entry = marketplaceEntry(for: update, data: updateData)
        try writeCachedCatalog(
            SideCordMarketplaceCatalog(
                schemaVersion: 2,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                plugins: [entry]
            ),
            signedBy: privateKey
        )
        let manager = SideCordPluginManager(
            rootURL: temporaryRoot,
            defaults: defaults,
            marketplaceConfiguration: SideCordMarketplaceConfiguration(
                catalogURL: URL(string: "https://plugins.sidecord.app/catalog.json")!,
                publicKey: privateKey.publicKey.rawRepresentation
            )
        )
        _ = try manager.install(data: encode(initial), source: .local)
        manager.setEnabled(true, identifier: initial.manifest.identifier)

        let plan = try manager.prepareMarketplaceInstallation(entry, packageData: updateData)

        XCTAssertTrue(manager.catalogIsCached)
        XCTAssertTrue(plan.isUpdate)
        XCTAssertEqual(plan.installedVersion, "1.0.0")
        XCTAssertEqual(
            plan.addedPermissions,
            ["backgroundAudio", "persistentWebsiteData", "webPanel"]
        )
        XCTAssertEqual(plan.addedNetworkHosts, ["accounts.google.com", "music.youtube.com"])

        let installed = try manager.commitMarketplaceInstallation(plan)
        XCTAssertEqual(installed.manifest.version, "1.1.0")
        XCTAssertEqual(installed.marketplaceMetadata?.publisher, "MathieuDvv")
        XCTAssertTrue(manager.enabledIdentifiers.contains(initial.manifest.identifier))
    }

    @MainActor
    func testEmergencyBlocklistDisablesInstalledVersion() throws {
        let initialManager = makeManager()
        let plugin = package(version: "1.0.0", css: ".fixture { color: red; }")
        _ = try initialManager.install(data: encode(plugin), source: .marketplace)
        initialManager.setEnabled(true, identifier: plugin.manifest.identifier)

        let privateKey = Curve25519.Signing.PrivateKey()
        try writeCachedCatalog(
            SideCordMarketplaceCatalog(
                schemaVersion: 2,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                plugins: [],
                blocklist: [SideCordMarketplaceBlock(
                    identifier: plugin.manifest.identifier,
                    versions: [plugin.manifest.version],
                    reason: "Security incident"
                )]
            ),
            signedBy: privateKey
        )
        let reloaded = SideCordPluginManager(
            rootURL: temporaryRoot,
            defaults: defaults,
            marketplaceConfiguration: SideCordMarketplaceConfiguration(
                catalogURL: URL(string: "https://plugins.sidecord.app/catalog.json")!,
                publicKey: privateKey.publicKey.rawRepresentation
            )
        )

        XCTAssertEqual(reloaded.installed.count, 1)
        XCTAssertTrue(reloaded.enabledIdentifiers.isEmpty)
    }

    func testSchemaTwoCatalogRejectsPublisherMismatch() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let plugin = package(version: "1.0.0", css: ".fixture { color: red; }")
        let data = try encode(plugin)
        var entry = marketplaceEntry(for: plugin, data: data)
        entry = SideCordMarketplaceEntry(
            identifier: entry.identifier,
            name: entry.name,
            version: entry.version,
            author: entry.author,
            summary: entry.summary,
            packageURL: entry.packageURL,
            sha256: entry.sha256,
            minimumSideCordVersion: entry.minimumSideCordVersion,
            repository: entry.repository,
            publisher: "SomeoneElse",
            permissions: entry.permissions
        )
        let catalog = SideCordMarketplaceCatalog(
            schemaVersion: 2,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plugins: [entry]
        )
        let payload = try JSONEncoder.iso8601.encode(catalog)
        let envelope = SignedSideCordCatalogEnvelope(
            payload: payload.base64EncodedString(),
            signature: try privateKey.signature(for: payload).base64EncodedString()
        )

        XCTAssertThrowsError(try SideCordCatalogVerifier.verify(
            envelopeData: JSONEncoder().encode(envelope),
            publicKey: privateKey.publicKey.rawRepresentation
        )) { error in
            XCTAssertEqual(error as? SideCordPluginError, .invalidCatalog)
        }
    }

    @MainActor
    private func makeManager() -> SideCordPluginManager {
        SideCordPluginManager(
            rootURL: temporaryRoot,
            defaults: defaults,
            marketplaceConfiguration: nil
        )
    }

    private func package(version: String, css: String) -> SideCordPluginPackage {
        SideCordPluginPackage(manifest: SideCordPluginManifest(
            schemaVersion: 1,
            identifier: "com.sidecord.fixture",
            name: "Fixture",
            version: version,
            author: "SideCord Tests",
            description: "A declarative test package.",
            minimumSideCordVersion: "2.0.0",
            capabilities: [.styleSheet],
            contributions: SideCordPluginContributions(styleSheets: [
                SideCordPluginStyleSheet(
                    id: "fixture-css",
                    name: "Fixture CSS",
                    css: css
                )
            ])
        ))
    }

    private func webPanelPackage(
        schemaVersion: Int = 2,
        identifier: String = "com.sidecord.web-panel",
        version: String = "1.0.0",
        initialURL: String = "https://music.youtube.com/",
        allowedHosts: [String] = ["music.youtube.com"],
        permissionHosts: [String] = ["music.youtube.com"],
        preferredHeight: Double = 190,
        minimumHeight: Double? = 140,
        maximumHeight: Double? = 300,
        customCSS: String? = ".fixture { color: red; }",
        capabilities: [SideCordPluginCapability] = [.webPanel],
        backgroundAudio: Bool = true,
        persistentWebsiteData: Bool = true,
        documentLayouts: [SideCordPluginDocumentLayout] = []
    ) -> SideCordPluginPackage {
        SideCordPluginPackage(manifest: SideCordPluginManifest(
            schemaVersion: schemaVersion,
            identifier: identifier,
            name: "Web Panel Fixture",
            version: version,
            author: "SideCord Tests",
            description: "A declarative web-panel package.",
            minimumSideCordVersion: "2.3.0",
            capabilities: capabilities,
            permissions: SideCordPluginPermissions(
                networkHosts: permissionHosts,
                persistentWebsiteData: persistentWebsiteData,
                backgroundAudio: backgroundAudio
            ),
            contributions: SideCordPluginContributions(webPanels: [
                SideCordPluginWebPanel(
                    id: "web-panel",
                    name: "Web Panel",
                    placement: .bottom,
                    initialURL: URL(string: initialURL)!,
                    allowedNavigationHosts: allowedHosts,
                    preferredHeight: preferredHeight,
                    minimumHeight: minimumHeight,
                    maximumHeight: maximumHeight,
                    userResizable: true,
                    customCSS: customCSS,
                    documentLayouts: documentLayouts
                )
            ])
        ))
    }

    private func encode(_ package: SideCordPluginPackage) throws -> Data {
        try JSONEncoder().encode(package)
    }

    private func marketplaceEntry(
        for package: SideCordPluginPackage,
        data: Data
    ) -> SideCordMarketplaceEntry {
        let manifest = package.manifest
        return SideCordMarketplaceEntry(
            identifier: manifest.identifier,
            name: manifest.name,
            version: manifest.version,
            author: manifest.author,
            summary: manifest.description,
            packageURL: URL(
                string: "https://github.com/MathieuDvv/sidecord-plugin-fixture/releases/download/v\(manifest.version)/plugin.json"
            )!,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            minimumSideCordVersion: manifest.minimumSideCordVersion,
            repository: URL(string: "https://github.com/MathieuDvv/sidecord-plugin-fixture")!,
            publisher: "MathieuDvv",
            categories: ["testing"],
            permissions: manifest.catalogPermissionLabels,
            networkHosts: manifest.permissions.networkHosts
        )
    }

    private func writeCachedCatalog(
        _ catalog: SideCordMarketplaceCatalog,
        signedBy privateKey: Curve25519.Signing.PrivateKey
    ) throws {
        let payload = try JSONEncoder.iso8601.encode(catalog)
        let envelope = SignedSideCordCatalogEnvelope(
            payload: payload.base64EncodedString(),
            signature: try privateKey.signature(for: payload).base64EncodedString()
        )
        let directory = temporaryRoot.appendingPathComponent("Marketplace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(envelope).write(
            to: directory.appendingPathComponent("catalog-envelope.json"),
            options: .atomic
        )
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
