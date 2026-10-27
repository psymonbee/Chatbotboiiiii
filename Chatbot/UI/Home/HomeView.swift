import SwiftData
import SwiftUI

enum Route: Hashable {
    case chat(UUID)
    case history
}

/// iPhone: home screen in a navigation stack.
struct PhoneRoot: View {
    @Environment(SessionStore.self) private var store
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                open: { path.append(.chat($0)) },
                showHistory: { path.append(.history) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .chat(let id):
                    ChatScreen(chatID: id)
                        .environment(\.closeChat, { if !path.isEmpty { path.removeLast() } })
                case .history:
                    HistoryList { path.append(.chat($0)) }
                }
            }
        }
        .onChange(of: path) { old, new in
            for case .chat(let id) in old where !new.contains(.chat(id)) {
                store.release(id)
            }
        }
    }
}

struct HomeView: View {
    var open: (UUID) -> Void
    var showHistory: () -> Void

    @Environment(Vault.self) private var vault
    @Environment(SessionStore.self) private var store
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chats: [ChatRecord]
    @Query(sort: \PersonaRecord.sortOrder) private var personaRecords: [PersonaRecord]

    @State private var search = ""
    @State private var showSettings = false
    @State private var editor: PersonaEditorTarget?
    @State private var pendingDelete: UUID?

    private let recentLimit = 8

    var body: some View {
        let summaries = ChatSummary.make(chats, store: store, search: search)
        let personas = PersonaItem.make(personaRecords, store: store)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Text("Create, explore,\nbe inspired")
                    .font(Theme.display)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6)
                SearchField(text: $search)
                if !vault.hasAPIKey {
                    APIKeyBanner { showSettings = true }
                }
                if search.isEmpty {
                    personaCarousel(personas)
                }
                history(summaries)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { GlowBackground() }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editor) { PersonaEditor(target: $0) }
        .confirmationDialog("Delete this chat?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { store.deleteChat(id) }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.gradient))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25)))
            }
            .accessibilityLabel("Settings")
            Spacer()
            Button {
                start(nil, incognito: true)
            } label: {
                Image(systemName: "eye.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.black))
            }
            .accessibilityLabel("New incognito chat")
            Button {
                start(nil, incognito: false)
            } label: {
                Text("New chat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(Capsule().fill(.black))
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private func personaCarousel(_ personas: [PersonaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(personas) { item in
                    Button {
                        start(item.payload, incognito: false)
                    } label: {
                        PersonaCard(persona: item.payload)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("New chat", systemImage: "square.and.pencil") { start(item.payload, incognito: false) }
                        Button("New incognito chat", systemImage: "eye.slash") { start(item.payload, incognito: true) }
                        Button("Edit", systemImage: "pencil") { editor = .edit(item.id, item.payload) }
                        Button("Make default", systemImage: "star") { store.makeDefault(item.id) }
                    }
                }
                Button {
                    editor = .new
                } label: {
                    NewPersonaCard()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func history(_ summaries: [ChatSummary]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("History")
                    .font(.title3.weight(.semibold))
                Spacer()
                if summaries.count > recentLimit, search.isEmpty {
                    Button("See all", action: showHistory)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .buttonStyle(.plain)
                }
            }
            if summaries.isEmpty {
                Text(search.isEmpty ? "Your chats will appear here." : "No chats match “\(search)”.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(search.isEmpty ? Array(summaries.prefix(recentLimit)) : summaries) { summary in
                Button {
                    open(summary.id)
                } label: {
                    ChatRow(summary: summary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = summary.id }
                }
            }
        }
        .padding(.top, 6)
    }

    private func start(_ persona: PersonaPayload?, incognito: Bool) {
        let session = store.newChat(persona: persona ?? store.defaultPersona(), incognito: incognito)
        open(session.id)
    }
}

/// Every chat, with search and swipe to delete.
struct HistoryList: View {
    var open: (UUID) -> Void

    @Environment(SessionStore.self) private var store
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chats: [ChatRecord]
    @State private var search = ""

    var body: some View {
        let summaries = ChatSummary.make(chats, store: store, search: search)
        List {
            ForEach(summaries) { summary in
                Button {
                    open(summary.id)
                } label: {
                    ChatRow(summary: summary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { store.deleteChat(summary.id) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $search)
        .navigationTitle("History")
        .overlay {
            if chats.isEmpty {
                ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}
