import ChatCore
import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    var role: MessageRole
    var text = ""
    var reasoning = ""
    var thinkingSeconds: Double?
    var attachments: [Attachment] = []
    var model: String?
    var usage: Usage?
    /// Shown in place of a reply; never saved.
    var error: String?
    var isStreaming = false
    var stopped = false
    var createdAt = Date.now

    var payload: MessagePayload {
        MessagePayload(
            role: role,
            text: text,
            reasoning: reasoning.isEmpty ? nil : reasoning,
            thinkingSeconds: thinkingSeconds,
            model: model,
            usage: usage,
            stopped: stopped ? true : nil
        )
    }

    var turn: ChatTurn {
        ChatTurn(
            role: role == .user ? .user : .assistant,
            text: text,
            images: attachments.filter { $0.kind == .image }.map { ChatTurn.Image(mimeType: $0.mimeType, data: $0.data) },
            documents: attachments.filter { $0.kind == .document }.map { ChatTurn.Document(name: $0.filename, text: $0.text) }
        )
    }
}

/// One open conversation, decrypted in memory. Writes through to SwiftData unless incognito.
@MainActor
@Observable
final class ChatSession: Identifiable {
    let id: UUID
    let isIncognito: Bool
    var title: String
    var personaName: String
    var personaSymbol: String
    var systemPrompt: String
    var settings: GenerationSettings
    private(set) var messages: [ChatMessage]
    private(set) var isGenerating = false
    private(set) var isPersisted: Bool

    var draft = ""
    var pendingAttachments: [Attachment] = []
    var attachmentError: String?

    private unowned let store: SessionStore
    @ObservationIgnored private var nextOrder: Int
    @ObservationIgnored private var generationTask: Task<Void, Never>?

    init(id: UUID, store: SessionStore, header: ChatHeader, messages: [ChatMessage], incognito: Bool, persisted: Bool, nextOrder: Int) {
        self.id = id
        self.store = store
        self.isIncognito = incognito
        self.title = header.title
        self.personaName = header.personaName
        self.personaSymbol = header.personaSymbol
        self.systemPrompt = header.systemPrompt
        self.settings = header.settings
        self.messages = messages
        self.isPersisted = persisted
        self.nextOrder = nextOrder
    }

    var header: ChatHeader {
        ChatHeader(title: title, personaName: personaName, personaSymbol: personaSymbol, systemPrompt: systemPrompt, settings: settings)
    }

    var acceptsImages: Bool { store.catalog.acceptsImages(settings.model) }

    var canSend: Bool {
        !isGenerating && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    // MARK: - Sending

    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = ChatMessage(id: UUID(), role: .user, text: text, attachments: pendingAttachments)
        draft = ""
        pendingAttachments = []
        attachmentError = nil
        if title.isEmpty {
            title = ChatTitle.make(from: text.isEmpty ? (message.attachments.first?.filename ?? "Attachment") : text)
        }
        messages.append(message)
        persist(message)
        generate()
    }

    func send(text: String) {
        draft = text
        send()
    }

    /// Replaces the last reply (or a failed one) with a new one.
    func regenerate() {
        guard !isGenerating else { return }
        if let last = messages.last, last.role == .assistant {
            messages.removeLast()
            store.deleteMessage(last.id)
        }
        guard messages.last?.role == .user else { return }
        generate()
    }

    func stop() {
        generationTask?.cancel()
    }

    /// Waits for the reply in progress, if any.
    func waitForReply() async {
        await generationTask?.value
    }

    func delete(_ message: ChatMessage) {
        guard !isGenerating else { return }
        messages.removeAll { $0.id == message.id }
        store.deleteMessage(message.id)
    }

    /// Saves title, prompt and settings after they're edited.
    func headerChanged() {
        store.saveHeader(of: self)
    }

    // MARK: - Attachments

    func attach(urls: [URL]) async {
        for url in urls {
            do {
                let attachment = try await Task.detached { try AttachmentLoader.load(url: url) }.value
                add(attachment)
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    func attach(imageData: Data, filename: String) async {
        do {
            let attachment = try await Task.detached { try AttachmentLoader.image(data: imageData, filename: filename) }.value
            add(attachment)
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func add(_ attachment: Attachment) {
        if attachment.kind == .image, !acceptsImages {
            attachmentError = "\(settings.model) can't view images. Switch model in the ⋯ menu."
            return
        }
        attachmentError = nil
        pendingAttachments.append(attachment)
    }

    func removePending(_ attachment: Attachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Generation

    private func generate() {
        guard let apiKey = store.vault.apiKey, !apiKey.isEmpty else {
            messages.append(ChatMessage(id: UUID(), role: .assistant, error: "Add your DeepSeek API key in Settings first."))
            return
        }
        let settings = self.settings
        let allowImages = acceptsImages
        let turns = messages.filter { $0.error == nil }.map(\.turn)
        let request = RequestBuilder.request(settings: settings, systemPrompt: systemPrompt, turns: turns, allowImages: allowImages)
        let sentImages = allowImages && turns.contains { !$0.images.isEmpty }

        let replyID = UUID()
        messages.append(ChatMessage(id: replyID, role: .assistant, model: settings.model, isStreaming: true))
        isGenerating = true

        generationTask = Task { [weak self] in
            var text = ""
            var reasoning = ""
            var thinkingStarted: Date?
            var thinkingSeconds: Double?
            var usage: Usage?
            var failure: Error?
            var lastFlush = Date.distantPast

            do {
                for try await event in DeepSeekClient(apiKey: apiKey).stream(request) {
                    switch event {
                    case .reasoning(let chunk):
                        if thinkingStarted == nil { thinkingStarted = .now }
                        reasoning += chunk
                    case .content(let chunk):
                        if let started = thinkingStarted, thinkingSeconds == nil {
                            thinkingSeconds = Date.now.timeIntervalSince(started)
                        }
                        text += chunk
                    case .usage(let u):
                        usage = u
                    case .finished, .done:
                        break
                    }
                    // Redraw at most ~20 times a second rather than per token.
                    if Date.now.timeIntervalSince(lastFlush) > 0.05 {
                        lastFlush = .now
                        self?.update(replyID) {
                            $0.text = text
                            $0.reasoning = reasoning
                            $0.thinkingSeconds = thinkingSeconds
                        }
                    }
                }
            } catch {
                failure = error
            }

            if thinkingSeconds == nil, let started = thinkingStarted {
                thinkingSeconds = Date.now.timeIntervalSince(started)
            }
            let cancelled = Task.isCancelled || failure is CancellationError || (failure as? URLError)?.code == .cancelled
            self?.finish(
                replyID,
                text: text,
                reasoning: reasoning,
                thinkingSeconds: thinkingSeconds,
                usage: usage,
                failure: cancelled ? nil : failure,
                stopped: cancelled,
                model: settings.model,
                sentImages: sentImages
            )
        }
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func finish(
        _ id: UUID,
        text: String,
        reasoning: String,
        thinkingSeconds: Double?,
        usage: Usage?,
        failure: Error?,
        stopped: Bool,
        model: String,
        sentImages: Bool
    ) {
        isGenerating = false
        generationTask = nil

        var errorText = failure?.localizedDescription
        if sentImages, let failure = failure as? DeepSeekClient.ClientError, Self.isImageRejection(failure) {
            store.catalog.markNoImages(model)
            errorText = "\(model) doesn't accept images, so image attachments are now off for it. Tap Retry to send without the image, or switch model in the ⋯ menu."
        }

        if text.isEmpty, reasoning.isEmpty, errorText == nil {
            // Stopped before anything arrived.
            messages.removeAll { $0.id == id }
            return
        }
        update(id) {
            $0.text = text
            $0.reasoning = reasoning
            $0.thinkingSeconds = thinkingSeconds
            $0.usage = usage
            $0.error = errorText
            $0.stopped = stopped
            $0.isStreaming = false
        }
        if let message = messages.first(where: { $0.id == id }), !message.text.isEmpty {
            persist(message)
        }
    }

    private static func isImageRejection(_ error: DeepSeekClient.ClientError) -> Bool {
        guard let status = error.status, status == 400 || status == 422 else { return false }
        let message = (error.errorDescription ?? "").lowercased()
        return ["image", "vision", "multimodal", "modal"].contains { message.contains($0) }
    }

    // MARK: - Persistence

    private func persist(_ message: ChatMessage) {
        guard !isIncognito else { return }
        if store.save(message, order: nextOrder, in: self) {
            nextOrder += 1
            isPersisted = true
        }
    }
}
