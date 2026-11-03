import XCTest
@testable import OrbitalCore
import OrbitalAddons

#if canImport(Security)
import Security

/// TEC-5, TEC-6 · el llavero por secreto: solo la copia compartida de tu clave de Real-Debrid y la invitación del iPhone
/// viajan por iCloud; lo demás se queda en este aparato. Con un llavero de mentira (nada toca el de verdad).
private final class FakeKeychain: @unchecked Sendable {
    let lock = NSLock()
    var items: [String: (data: Data, attrs: [String: Any])] = [:]
    var queries: [[String: Any]] = []
    var refuseAdds = false, refuseUpdates = false

    var calls: KeychainCalls {
        KeychainCalls(
            copy: { q in self.lock.withLock {
                self.queries.append(q)
                guard let item = self.items[q[kSecAttrAccount as String] as! String] else { return (errSecItemNotFound, nil) }
                return (errSecSuccess, item.data)
            } },
            add: { q in self.lock.withLock {
                if self.refuseAdds { return errSecParam }
                self.items[q[kSecAttrAccount as String] as! String] = (q[kSecValueData as String] as! Data, q)
                return errSecSuccess
            } },
            update: { q, change in self.lock.withLock {
                let account = q[kSecAttrAccount as String] as! String
                guard let item = self.items[account] else { return errSecItemNotFound }
                if self.refuseUpdates { return errSecInteractionNotAllowed }
                self.items[account] = (change[kSecValueData as String] as! Data, item.attrs)
                return errSecSuccess
            } },
            delete: { q in self.lock.withLock {
                self.queries.append(q)
                return self.items.removeValue(forKey: q[kSecAttrAccount as String] as! String) == nil ? errSecItemNotFound : errSecSuccess
            } })
    }
}

final class SecretPolicyTests: XCTestCase {
    /// Si alguien agrega algo a lo que viaja por iCloud, esta prueba lo dice: la lista blanca es exactamente esta.
    func testOnlyTheSharedRealDebridCopyAndTheIPadInviteAreSynchronizable() {
        XCTAssertEqual(SecretKey.synchronizable, ["realdebrid_token.shared", "orbital_invite"])
        let local = [SecretKey.orbitalDeviceKey, SecretKey.orbitalToken, SecretKey.orbitalAddress, SecretKey.orbitalTVID, SecretKey.traktTokens,
                     SecretKey.traktClientID, SecretKey.traktClientSecret, SecretKey.oneDriveTokens, SecretKey.stremioAuth, SecretKey.ownAddons,
                     SecretKey.tmdbKey, SecretKey.sharedRealDebridSeen, AddonKeys.realDebridToken, AddonKeys.addonURL("torrentio")]
        for key in local {
            XCTAssertEqual(SecretKey.policy(key), .thisDevice, key)
            let a = KeychainSecrets.attributes(for: key)
            XCTAssertEqual(a[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, key)
            XCTAssertEqual(a[kSecAttrSynchronizable as String] as? Bool, false, key)
        }
        for key in SecretKey.synchronizable {
            let a = KeychainSecrets.attributes(for: key)
            XCTAssertEqual(a[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String, "sin ThisDeviceOnly: si no, errSecParam")
            XCTAssertEqual(a[kSecAttrSynchronizable as String] as? Bool, true, key)
        }
    }

    /// TEC-20 y TEC-39 · cada versión con su llavero (sin grupo compartido entre Ultra y Plus) y `orbital-ios://` (emparejar)
    /// solo en un target: hoy existe solo Ultra (`Orbital`). Cuando nazca Plus, esta prueba pide revisarlo.
    func testNoSharedKeychainGroupAndOnlyOneAppRegistersThePairingScheme() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let project = try String(contentsOf: url.appendingPathComponent("ios/App/project.yml"), encoding: .utf8)
        XCTAssertFalse(project.contains("keychain-access-groups"), "TEC-20 A: Ultra y Plus no comparten llavero")
        XCTAssertEqual(project.components(separatedBy: "CFBundleURLSchemes: [orbital-ios]").count - 1, 1, "TEC-39: solo Ultra abre orbital-ios://pair")
        XCTAssertEqual(project.components(separatedBy: "type: application").count - 1, 1, "nació otra app (¿Plus?): dale su propio esquema y llavero")
    }

    func testAddsCarryThePolicyAndSharedReadsUseSynchronizableAny() throws {
        let fake = FakeKeychain()
        let keychain = KeychainSecrets(service: "test", calls: fake.calls)
        XCTAssertTrue(keychain.store(SecretKey.orbitalDeviceKey, "od1.secret"))
        XCTAssertTrue(keychain.store(SecretKey.sharedRealDebrid, #"{"key":"K","from":"iphone"}"#))
        let local = try XCTUnwrap(fake.items[SecretKey.orbitalDeviceKey]).attrs
        XCTAssertEqual(local[kSecAttrSynchronizable as String] as? Bool, false)
        let shared = try XCTUnwrap(fake.items[SecretKey.sharedRealDebrid]).attrs
        XCTAssertEqual(shared[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
        _ = keychain.get(SecretKey.sharedRealDebrid)
        let read = try XCTUnwrap(fake.queries.last)
        XCTAssertEqual(read[kSecAttrSynchronizable as String] as? String, kSecAttrSynchronizableAny as String)
    }

    /// TEC-6 · lo compartido no se queda en memoria: lo que llega de iCloud después se ve sin cerrar la app.
    func testSharedItemsAreNeverCachedNotEvenAsMissing() {
        let fake = FakeKeychain()
        let keychain = KeychainSecrets(service: "test", calls: fake.calls)
        XCTAssertNil(keychain.get(SecretKey.sharedRealDebrid))
        fake.items[SecretKey.sharedRealDebrid] = (Data("llegó de iCloud".utf8), [:])
        XCTAssertEqual(keychain.get(SecretKey.sharedRealDebrid), "llegó de iCloud")
        XCTAssertNil(keychain.get(SecretKey.tmdbKey))
        fake.items[SecretKey.tmdbKey] = (Data("X".utf8), [:])
        XCTAssertNil(keychain.get(SecretKey.tmdbKey), "lo de este aparato sí se recuerda (leer en cada vista trababa la interfaz)")
    }

    /// TEC-5 · si el llavero se niega, la memoria no dice «guardado» y lo de antes se queda.
    func testFailedSaveNeverUpdatesTheCache() {
        let fake = FakeKeychain()
        let keychain = KeychainSecrets(service: "test", calls: fake.calls)
        XCTAssertTrue(keychain.store(SecretKey.traktTokens, "VIEJO"))
        fake.refuseUpdates = true
        XCTAssertFalse(keychain.store(SecretKey.traktTokens, "NUEVO"))
        XCTAssertEqual(keychain.get(SecretKey.traktTokens), "VIEJO")
        fake.refuseAdds = true
        XCTAssertFalse(keychain.store(SecretKey.oneDriveTokens, "X"))
        XCTAssertNil(keychain.get(SecretKey.oneDriveTokens))
    }
}
#endif
