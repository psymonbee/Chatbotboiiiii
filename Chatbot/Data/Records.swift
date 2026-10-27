import Foundation
import SwiftData

// What SwiftData stores and CloudKit syncs. Content only ever lives in `sealed`,
// which is AES-GCM ciphertext; the rest is ordering metadata.
//
// CloudKit rules: every property optional or defaulted, no unique constraints,
// optional relationships with inverses, and after the schema reaches production
// changes must be additive.

@Model
final class PersonaRecord {
    var uuid: UUID = UUID()
    var createdAt: Date = Date.now
    var sortOrder: Double = 0
    var keyID: String = ""
    var sealed: Data?

    init(uuid: UUID = UUID(), sortOrder: Double, keyID: String, sealed: Data) {
        self.uuid = uuid
        self.sortOrder = sortOrder
        self.keyID = keyID
        self.sealed = sealed
    }
}

@Model
final class ChatRecord {
    var uuid: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var keyID: String = ""
    var sealedHeader: Data?

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.chat)
    var messages: [MessageRecord]? = []

    init(uuid: UUID) {
        self.uuid = uuid
    }
}

@Model
final class MessageRecord {
    var uuid: UUID = UUID()
    var createdAt: Date = Date.now
    var sortOrder: Int = 0
    var keyID: String = ""
    @Attribute(.externalStorage) var sealed: Data?
    var chat: ChatRecord?

    @Relationship(deleteRule: .cascade, inverse: \AttachmentRecord.message)
    var attachments: [AttachmentRecord]? = []

    init(uuid: UUID, sortOrder: Int, keyID: String, sealed: Data) {
        self.uuid = uuid
        self.sortOrder = sortOrder
        self.keyID = keyID
        self.sealed = sealed
    }
}

@Model
final class AttachmentRecord {
    var uuid: UUID = UUID()
    var sortOrder: Int = 0
    var keyID: String = ""
    @Attribute(.externalStorage) var sealed: Data?
    var message: MessageRecord?

    init(uuid: UUID, sortOrder: Int, keyID: String, sealed: Data) {
        self.uuid = uuid
        self.sortOrder = sortOrder
        self.keyID = keyID
        self.sealed = sealed
    }
}

enum Persistence {
    static let schema = Schema([PersonaRecord.self, ChatRecord.self, MessageRecord.self, AttachmentRecord.self])

    /// Syncs through the iCloud container named in the entitlements. Falls back to a
    /// local-only store if CloudKit can't be set up (e.g. no iCloud account).
    @MainActor
    static func makeContainer() -> ModelContainer {
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("CloudKit store unavailable, using local storage: \(error)")
        }
        do {
            let local = ModelConfiguration("Local", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open storage: \(error)")
        }
    }
}
