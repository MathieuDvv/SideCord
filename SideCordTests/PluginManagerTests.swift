import CryptoKit
import XCTest
@testable import SideCord

final class PluginManagerTests: XCTestCase {
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

    private func encode(_ package: SideCordPluginPackage) throws -> Data {
        try JSONEncoder().encode(package)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
