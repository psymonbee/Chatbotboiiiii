import CryptoKit
import Foundation
import Observation
import Security

/// Holds the history encryption key and the DeepSeek API key, both in iCloud Keychain.
///
/// Every record is sealed with AES-GCM before SwiftData sees it. The key is created once,
/// on the first device, and reaches the others through iCloud Keychain. A second device
/// must wait for it rather than make its own; otherwise each device would write history
/// the other can't read.
@MainActor
@Observable
final class Vault {
    enum State: Equatable {
        case loading
        /// No key and no data: either the first device, or one whose iCloud data hasn't arrived.
        case needsSetup
        /// History exists (synced from elsewhere) but its key hasn't arrived yet.
        case waitingForKey
        case ready
    }

    enum VaultError: LocalizedError {
        case locked, wrongKey, corrupt

        var errorDescription: String? {
            switch self {
            case .locked: "The encryption key isn't available on this device yet."
            case .wrongKey: "This was encrypted with a different key."
            case .corrupt: "This data is damaged."
            }
        }
    }

    private static let historyKeyAccount = "history-key.v1"
    private static let apiKeyAccount = "deepseek-api-key"
    private static let formatVersion: UInt8 = 1

    private(set) var state: State = .loading
    private(set) var setupError: String?
    private(set) var keyID = ""
    private(set) var hasAPIKey = false
    @ObservationIgnored private var key: SymmetricKey?

    init() {
        hasAPIKey = Keychain.read(Self.apiKeyAccount) != nil
    }

    // MARK: - History key

    func bootstrap(hasExistingData: Bool) {
        if loadKey() { return }
        state = hasExistingData ? .waitingForKey : .needsSetup
    }

    /// Picks up the key if iCloud Keychain has delivered it. Also re-checks on app activation
    /// in case another device's key replaced this one.
    @discardableResult
    func loadKey() -> Bool {
        guard let data = Keychain.read(Self.historyKeyAccount), data.count == 32 else { return false }
        let k = SymmetricKey(data: data)
        key = k
        keyID = Self.fingerprint(k)
        state = .ready
        return true
    }

    /// First device only. If a key already exists (another device got there first), that one is used.
    @discardableResult
    func createKey() -> Bool {
        let k = SymmetricKey(size: .bits256)
        let status = Keychain.add(k.withUnsafeBytes { Data($0) }, account: Self.historyKeyAccount)
        switch status {
        case errSecSuccess:
            key = k
            keyID = Self.fingerprint(k)
            setupError = nil
            state = .ready
            return true
        case errSecDuplicateItem:
            return loadKey()
        default:
            // Never fall back to an unsaved key: history sealed with it would be lost on relaunch.
            setupError = "Couldn't save the encryption key to iCloud Keychain (error \(status)). Check that iCloud Keychain is on."
            return false
        }
    }

    /// Gives up on the old key. Anything sealed with it becomes unreadable.
    func replaceKey() {
        Keychain.delete(Self.historyKeyAccount)
        key = nil
        keyID = ""
        createKey()
    }

    func waitForSync() {
        state = .waitingForKey
    }

    // MARK: - Sealing

    func seal<T: Encodable>(_ value: T) throws -> Data {
        guard let key else { throw VaultError.locked }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let box = try AES.GCM.seal(try encoder.encode(value), using: key)
        guard let combined = box.combined else { throw VaultError.corrupt }
        return Data([Self.formatVersion]) + combined
    }

    func open<T: Decodable>(_ type: T.Type, from data: Data?, keyID recordKeyID: String) throws -> T {
        guard let key else { throw VaultError.locked }
        if !recordKeyID.isEmpty, recordKeyID != keyID { throw VaultError.wrongKey }
        guard let data, data.first == Self.formatVersion else { throw VaultError.corrupt }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst())
        let plain = try AES.GCM.open(box, using: key)
        return try PropertyListDecoder().decode(T.self, from: plain)
    }

    /// Short, human-comparable ID for the key ("A1B2-C3D4-E5F6"), stored on each record.
    static func fingerprint(_ key: SymmetricKey) -> String {
        let digest = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        return digest.prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    var displayKeyID: String {
        stride(from: 0, to: keyID.count, by: 4).map { i -> String in
            let start = keyID.index(keyID.startIndex, offsetBy: i)
            let end = keyID.index(start, offsetBy: 4, limitedBy: keyID.endIndex) ?? keyID.endIndex
            return String(keyID[start..<end])
        }.joined(separator: "-")
    }

    // MARK: - API key

    var apiKey: String? {
        Keychain.read(Self.apiKeyAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(Self.apiKeyAccount)
        } else {
            Keychain.write(Data(trimmed.utf8), account: Self.apiKeyAccount)
        }
        hasAPIKey = Keychain.read(Self.apiKeyAccount) != nil
    }

    /// The API key may have arrived from another device since launch.
    func refresh() {
        hasAPIKey = Keychain.read(Self.apiKeyAccount) != nil
        if state == .ready || state == .waitingForKey { loadKey() }
    }
}
