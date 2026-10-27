import Foundation
import ChatCore

// The decrypted contents of each record. Each payload is encoded and sealed as a
// whole, so CloudKit never sees a title, prompt, message or file.
//
// Any field added later must be Optional so payloads saved by older builds still decode.

enum MessageRole: String, Codable {
    case user, assistant
}

enum AttachmentKind: String, Codable {
    case image, document
}

struct PersonaPayload: Codable, Hashable {
    var name: String
    var symbol: String
    var prompt: String
    var settings: GenerationSettings
}

struct ChatHeader: Codable, Hashable {
    var title: String
    var personaName: String
    var personaSymbol: String
    var systemPrompt: String
    var settings: GenerationSettings
}

struct MessagePayload: Codable {
    var role: MessageRole
    var text: String
    var reasoning: String?
    var thinkingSeconds: Double?
    var model: String?
    var usage: Usage?
    var stopped: Bool?
}

struct AttachmentPayload: Codable {
    var kind: AttachmentKind
    var filename: String
    var mimeType: String
    /// Image bytes, already downscaled and re-encoded.
    var data: Data?
    /// Text pulled out of a document.
    var text: String?
}

extension PersonaPayload {
    static let blank = PersonaPayload(
        name: "Assistant",
        symbol: "sparkle",
        prompt: "You are a helpful assistant. Be clear, direct and accurate.",
        settings: GenerationSettings()
    )

    /// Created once, on the first device, alongside the encryption key.
    static let starters: [PersonaPayload] = [
        .blank,
        PersonaPayload(
            name: "Text writer",
            symbol: "pencil.line",
            prompt: "You are a skilled writer and editor. Match the tone the user asks for, write clearly and vividly, and keep it concise unless asked otherwise.",
            settings: GenerationSettings(thinking: false, temperature: 1.5)
        ),
        PersonaPayload(
            name: "Code tutor",
            symbol: "chevron.left.forwardslash.chevron.right",
            prompt: "You are a patient programming tutor. Explain step by step, show short runnable examples, and point out common mistakes.",
            settings: GenerationSettings(thinking: true, reasoningEffort: .high)
        ),
    ]

    static let symbols = [
        "sparkle", "pencil.line", "chevron.left.forwardslash.chevron.right", "brain.head.profile",
        "graduationcap", "lightbulb", "globe.europe.africa", "book", "chart.bar", "theatermasks",
        "leaf", "heart", "briefcase", "fork.knife", "dumbbell", "music.note", "paintpalette", "magnifyingglass",
    ]
}
