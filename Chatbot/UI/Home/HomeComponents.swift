import SwiftData
import SwiftUI

/// A chat in the history list, decrypted for display. `header` is nil if this device can't read it.
struct ChatSummary: Identifiable {
    let id: UUID
    let header: ChatHeader?
    let updatedAt: Date

    @MainActor
    static func make(_ records: [ChatRecord], store: SessionStore, search: String) -> [ChatSummary] {
        let all = records.map { ChatSummary(id: $0.uuid, header: store.header($0), updatedAt: $0.updatedAt) }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { summary in
            guard let h = summary.header else { return false }
            return h.title.localizedCaseInsensitiveContains(query) || h.personaName.localizedCaseInsensitiveContains(query)
        }
    }
}

struct PersonaItem: Identifiable {
    let id: UUID
    let payload: PersonaPayload

    @MainActor
    static func make(_ records: [PersonaRecord], store: SessionStore) -> [PersonaItem] {
        records.compactMap { record in
            store.persona(record).map { PersonaItem(id: record.uuid, payload: $0) }
        }
    }
}

struct ChatRow: View {
    let summary: ChatSummary
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            PersonaAvatar(symbol: summary.header?.personaSymbol ?? "lock.fill", size: showsChevron ? 36 : 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.header?.personaName ?? "Locked chat")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard let header = summary.header else { return "Encrypted with a key this device doesn't have" }
        return header.title.isEmpty ? "New chat" : header.title
    }
}

/// The tall outlined cards ("AI text writer ↗") that start a chat with a persona.
struct PersonaCard: View {
    let persona: PersonaPayload

    var body: some View {
        VStack(alignment: .leading) {
            Text(persona.name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .foregroundStyle(.white)
            Spacer(minLength: 12)
            HStack {
                PersonaAvatar(symbol: persona.symbol, size: 30)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(width: 142, height: 168, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct NewPersonaCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
            Text("New persona")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 142, height: 168)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.stroke.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct APIKeyBanner: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(Theme.icon)
                Text("Add your DeepSeek API key to start chatting")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .padding(14)
            .background(Theme.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
