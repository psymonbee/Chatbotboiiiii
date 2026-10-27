import SwiftUI

/// Talk to the chat: listens, sends when you pause (or tap the mic), reads the reply aloud,
/// then listens again. Messages land in the same chat.
struct VoiceModeView: View {
    let session: ChatSession
    @Environment(\.dismiss) private var dismiss

    @State private var input = SpeechInput()
    @State private var output = SpeechOutput()
    @State private var phase: Phase = .starting

    enum Phase: Equatable {
        case starting, listening, thinking, speaking
        case unavailable(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            ParticleBlob(level: blobLevel, energy: blobEnergy)
                .frame(width: 280, height: 280)
            Text(caption)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(captionIsPlaceholder ? .secondary : .primary)
                .lineLimit(6)
                .padding(.horizontal, 32)
                .frame(minHeight: 140, alignment: .top)
                .padding(.top, 20)
                .animation(.default, value: caption)
            Spacer()
            controls
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task { await begin() }
        // Send after a short pause in speech.
        .task(id: input.transcript) {
            let heard = input.transcript
            guard phase == .listening, !heard.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, phase == .listening, input.transcript == heard else { return }
            await submit()
        }
        // Recognition can end on its own (long silence, time limit).
        .onChange(of: input.status) { _, status in
            guard phase == .listening else { return }
            switch status {
            case .idle:
                if input.transcript.isEmpty { input.start() } else { Task { await submit() } }
            case .unavailable(let message):
                phase = .unavailable(message)
            case .listening:
                break
            }
        }
        .onDisappear {
            input.stop()
            output.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PersonaAvatar(symbol: session.personaSymbol, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.personaName).font(.headline)
                Text(session.title.isEmpty ? "Voice" : session.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var controls: some View {
        HStack(spacing: 56) {
            Button {
                restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Start over")

            Button {
                Task { await mainAction() }
            } label: {
                Image(systemName: mainSymbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Theme.gradient))
                    .shadow(color: Theme.magenta.opacity(0.6), radius: 18)
            }
            .accessibilityLabel(mainLabel)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - State

    private var caption: String {
        switch phase {
        case .starting: "…"
        case .listening: input.transcript.isEmpty ? "Listening…" : input.transcript
        case .thinking: "Thinking…"
        case .speaking: lastReply.isEmpty ? "…" : lastReply
        case .unavailable(let message): message
        }
    }

    private var captionIsPlaceholder: Bool {
        switch phase {
        case .listening: input.transcript.isEmpty
        case .speaking: false
        default: true
        }
    }

    private var blobLevel: Double {
        phase == .listening ? input.level : 0
    }

    private var blobEnergy: Double {
        switch phase {
        case .thinking: 1.0
        case .speaking: 0.75
        case .listening: 0.45
        default: 0.25
        }
    }

    private var mainSymbol: String {
        switch phase {
        case .listening: input.transcript.isEmpty ? "mic.fill" : "arrow.up"
        case .thinking, .speaking: "stop.fill"
        default: "mic.fill"
        }
    }

    private var mainLabel: String {
        switch phase {
        case .listening: "Send"
        case .thinking, .speaking: "Stop"
        default: "Listen"
        }
    }

    private var lastReply: String {
        guard let last = session.messages.last, last.role == .assistant else { return "" }
        return last.error ?? last.text
    }

    // MARK: - Actions

    private func begin() async {
        guard await input.requestAccess() else {
            if case .unavailable(let message) = input.status { phase = .unavailable(message) }
            return
        }
        listen()
    }

    private func listen() {
        output.stop()
        phase = .listening
        input.start()
    }

    private func restart() {
        session.stop()
        listen()
    }

    private func mainAction() async {
        switch phase {
        case .listening:
            if input.transcript.isEmpty { input.start() } else { await submit() }
        case .thinking:
            session.stop()
            listen()
        case .speaking:
            listen()
        case .starting, .unavailable:
            await begin()
        }
    }

    private func submit() async {
        let text = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .listening, !text.isEmpty, !session.isGenerating else { return }
        phase = .thinking
        input.stop()
        session.send(text: text)
        await session.waitForReply()
        guard phase == .thinking else { return }

        guard let reply = session.messages.last, reply.role == .assistant, reply.error == nil, !reply.text.isEmpty else {
            phase = .speaking // shows the error text; tap the mic to carry on
            return
        }
        phase = .speaking
        output.speak(reply.text, id: reply.id) {
            if phase == .speaking { listen() }
        }
    }
}
