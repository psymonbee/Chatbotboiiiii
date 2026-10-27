import ChatCore
import Foundation
import Observation
import SwiftData

/// Opens, creates and saves chats and personas, sealing everything through the vault.
/// Chats stay in memory while open, so a reply keeps streaming if you navigate away.
@MainActor
@Observable
final class SessionStore {
    let container: ModelContainer
    let vault: Vault
    let catalog: ModelCatalog
    @ObservationIgnored private var sessions: [UUID: ChatSession] = [:]

    init(container: ModelContainer, vault: Vault, catalog: ModelCatalog) {
        self.container = container
        self.vault = vault
        self.catalog = catalog
    }

    private var context: ModelContext { container.mainContext }

    func hasAnyData() -> Bool {
        let chats = (try? context.fetchCount(FetchDescriptor<ChatRecord>())) ?? 0
        let personas = (try? context.fetchCount(FetchDescriptor<PersonaRecord>())) ?? 0
        return chats + personas > 0
    }

    // MARK: - Chats

    func newChat(persona: PersonaPayload?, incognito: Bool) -> ChatSession {
        let p = persona ?? .blank
        let header = ChatHeader(title: "", personaName: p.name, personaSymbol: p.symbol, systemPrompt: p.prompt, settings: p.settings)
        let session = ChatSession(id: UUID(), store: self, header: header, messages: [], incognito: incognito, persisted: false, nextOrder: 0)
        sessions[session.id] = session
        return session
    }

    func session(for id: UUID) -> ChatSession? {
        if let open = sessions[id] { return open }
        guard let record = chatRecord(id),
              let header = try? vault.open(ChatHeader.self, from: record.sealedHeader, keyID: record.keyID)
        else { return nil }

        let records = (record.messages ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let session = ChatSession(
            id: id,
            store: self,
            header: header,
            messages: records.map { decode($0) },
            incognito: false,
            persisted: true,
            nextOrder: (records.last?.sortOrder ?? -1) + 1
        )
        sessions[id] = session
        return session
    }

    /// Called when a chat is closed. Incognito and never-sent chats are dropped from memory
    /// (and an incognito reply in progress is stopped); saved chats stay while still streaming.
    func release(_ id: UUID) {
        guard let session = sessions[id] else { return }
        if session.isIncognito || !session.isPersisted {
            session.stop()
            sessions[id] = nil
        } else if !session.isGenerating {
            sessions[id] = nil
        }
    }

    @discardableResult
    func save(_ message: ChatMessage, order: Int, in session: ChatSession) -> Bool {
        do {
            let chat = chatRecord(session.id) ?? {
                let created = ChatRecord(uuid: session.id)
                context.insert(created)
                return created
            }()
            chat.keyID = vault.keyID
            chat.sealedHeader = try vault.seal(session.header)
            chat.updatedAt = .now

            let record = MessageRecord(uuid: message.id, sortOrder: order, keyID: vault.keyID, sealed: try vault.seal(message.payload))
            context.insert(record)
            record.chat = chat

            for (index, attachment) in message.attachments.enumerated() {
                let a = AttachmentRecord(uuid: attachment.id, sortOrder: index, keyID: vault.keyID, sealed: try vault.seal(attachment.payload))
                context.insert(a)
                a.message = record
            }
            try context.save()
            return true
        } catch {
            print("Couldn't save message: \(error)")
            return false
        }
    }

    func saveHeader(of session: ChatSession) {
        guard session.isPersisted, let chat = chatRecord(session.id) else { return }
        do {
            chat.keyID = vault.keyID
            chat.sealedHeader = try vault.seal(session.header)
            try context.save()
        } catch {
            print("Couldn't save chat header: \(error)")
        }
    }

    func deleteMessage(_ id: UUID) {
        var descriptor = FetchDescriptor<MessageRecord>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        try? context.save()
    }

    func deleteChat(_ id: UUID) {
        sessions[id]?.stop()
        sessions[id] = nil
        guard let record = chatRecord(id) else { return }
        context.delete(record)
        try? context.save()
    }

    private func chatRecord(_ id: UUID) -> ChatRecord? {
        var descriptor = FetchDescriptor<ChatRecord>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func decode(_ record: MessageRecord) -> ChatMessage {
        guard let p = try? vault.open(MessagePayload.self, from: record.sealed, keyID: record.keyID) else {
            return ChatMessage(id: record.uuid, role: .assistant, error: "This message can't be decrypted on this device.", createdAt: record.createdAt)
        }
        let attachments = (record.attachments ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { a -> Attachment? in
                guard let ap = try? vault.open(AttachmentPayload.self, from: a.sealed, keyID: a.keyID) else { return nil }
                return Attachment(id: a.uuid, kind: ap.kind, filename: ap.filename, mimeType: ap.mimeType, data: ap.data ?? Data(), text: ap.text ?? "")
            }
        return ChatMessage(
            id: record.uuid,
            role: p.role,
            text: p.text,
            reasoning: p.reasoning ?? "",
            thinkingSeconds: p.thinkingSeconds,
            attachments: attachments,
            model: p.model,
            usage: p.usage,
            stopped: p.stopped ?? false,
            createdAt: record.createdAt
        )
    }

    // MARK: - Personas

    func persona(_ record: PersonaRecord) -> PersonaPayload? {
        try? vault.open(PersonaPayload.self, from: record.sealed, keyID: record.keyID)
    }

    func header(_ record: ChatRecord) -> ChatHeader? {
        try? vault.open(ChatHeader.self, from: record.sealedHeader, keyID: record.keyID)
    }

    /// The persona new chats use by default: the first one that can be read.
    func defaultPersona() -> PersonaPayload {
        let descriptor = FetchDescriptor<PersonaRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let records = (try? context.fetch(descriptor)) ?? []
        return records.lazy.compactMap { self.persona($0) }.first ?? .blank
    }

    func savePersona(_ payload: PersonaPayload, id: UUID?) {
        do {
            let sealed = try vault.seal(payload)
            if let id, let record = personaRecord(id) {
                record.sealed = sealed
                record.keyID = vault.keyID
            } else {
                let last = (try? context.fetch(FetchDescriptor<PersonaRecord>()))?.map(\.sortOrder).max() ?? 0
                context.insert(PersonaRecord(sortOrder: last + 1, keyID: vault.keyID, sealed: sealed))
            }
            try context.save()
        } catch {
            print("Couldn't save persona: \(error)")
        }
    }

    func deletePersona(_ id: UUID) {
        guard let record = personaRecord(id) else { return }
        context.delete(record)
        try? context.save()
    }

    /// Makes a persona the default by moving it to the front.
    func makeDefault(_ id: UUID) {
        guard let record = personaRecord(id) else { return }
        let first = (try? context.fetch(FetchDescriptor<PersonaRecord>()))?.map(\.sortOrder).min() ?? 0
        record.sortOrder = first - 1
        try? context.save()
    }

    /// Runs once, on the device that created the key, so other devices don't add duplicates.
    func seedStarterPersonas() {
        guard ((try? context.fetchCount(FetchDescriptor<PersonaRecord>())) ?? 0) == 0 else { return }
        for (index, payload) in PersonaPayload.starters.enumerated() {
            guard let sealed = try? vault.seal(payload) else { continue }
            context.insert(PersonaRecord(sortOrder: Double(index), keyID: vault.keyID, sealed: sealed))
        }
        try? context.save()
    }

    private func personaRecord(_ id: UUID) -> PersonaRecord? {
        var descriptor = FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
