import ChatCore
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let isLast: Bool
    let session: ChatSession
    let speech: SpeechOutput

    var body: some View {
        switch message.role {
        case .user: userMessage
        case .assistant: assistantMessage
        }
    }

    // MARK: - User

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(88), spacing: 6), count: min(3, message.attachments.count)),
                        alignment: .trailing,
                        spacing: 6
                    ) {
                        ForEach(message.attachments) { AttachmentThumb(attachment: $0, size: 88) }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.bubble, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(message.text) }
            Button("Delete", systemImage: "trash", role: .destructive) { session.delete(message) }
                .disabled(session.isGenerating)
        }
    }

    // MARK: - Assistant

    private var waitingForFirstToken: Bool {
        message.isStreaming && message.text.isEmpty && message.reasoning.isEmpty
    }

    @ViewBuilder
    private var assistantMessage: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PersonaAvatar(symbol: session.personaSymbol, size: 24)
            if waitingForFirstToken {
                TypingIndicator().padding(.bottom, 8)
            } else {
                bubble
            }
            Spacer(minLength: 20)
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.reasoning.isEmpty {
                ThinkingSection(
                    reasoning: message.reasoning,
                    seconds: message.thinkingSeconds,
                    isLive: message.isStreaming && message.text.isEmpty
                )
            }
            if !message.text.isEmpty {
                MarkdownView(source: message.text)
            }
            if let error = message.error {
                errorView(error)
            }
            if !message.isStreaming, !message.text.isEmpty {
                Divider().overlay(Theme.hairline)
                actions
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(message.text) }
            Button("Delete", systemImage: "trash", role: .destructive) { session.delete(message) }
                .disabled(session.isGenerating)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Theme.pink)
            if isLast, !session.isGenerating {
                Button("Retry", systemImage: "arrow.clockwise") { session.regenerate() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.magenta)
                    .controlSize(.small)
            }
        }
    }

    @State private var copied = false

    private var actions: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: copied ? "checkmark" : "doc.on.doc", label: "Copy") {
                Clipboard.copy(message.text)
                copied = true
            }
            IconButton(
                systemImage: speech.speakingID == message.id ? "stop.fill" : "speaker.wave.2",
                label: speech.speakingID == message.id ? "Stop reading" : "Read aloud"
            ) {
                if speech.speakingID == message.id {
                    speech.stop()
                } else {
                    speech.speak(message.text, id: message.id)
                }
            }
            Spacer()
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if isLast, !session.isGenerating {
                IconButton(systemImage: "arrow.clockwise", label: "Regenerate") { session.regenerate() }
            }
        }
        .padding(.horizontal, -6)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private var footnote: String {
        var parts: [String] = []
        if message.stopped { parts.append("Stopped") }
        if let model = message.model { parts.append(model) }
        if let usage = message.usage {
            let total = usage.promptTokens + usage.completionTokens
            parts.append(total >= 1000 ? String(format: "%.1fk tokens", Double(total) / 1000) : "\(total) tokens")
        }
        return parts.joined(separator: " · ")
    }
}

struct ThinkingSection: View {
    let reasoning: String
    let seconds: Double?
    let isLive: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .symbolEffect(.pulse, isActive: isLive)
                    Text(label)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.hairline).frame(width: 2)
                    }
            }
        }
    }

    private var label: String {
        if isLive { return "Thinking…" }
        if let seconds { return "Thought for \(max(1, Int(seconds.rounded())))s" }
        return "Thoughts"
    }
}
