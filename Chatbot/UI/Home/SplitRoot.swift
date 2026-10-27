import SwiftData
import SwiftUI

/// Mac and iPad: personas and history in a sidebar, the chat beside it.
struct SplitRoot: View {
    @Environment(Vault.self) private var vault
    @Environment(SessionStore.self) private var store
    @Query(sort: \ChatRecord.updatedAt, order: .reverse) private var chats: [ChatRecord]
    @Query(sort: \PersonaRecord.sortOrder) private var personaRecords: [PersonaRecord]

    @State private var selection: UUID?
    @State private var search = ""
    @State private var editor: PersonaEditorTarget?
    @State private var showSettings = false

    var body: some View {
        let summaries = ChatSummary.make(chats, store: store, search: search)
        let personas = PersonaItem.make(personaRecords, store: store)

        NavigationSplitView {
            List(selection: $selection) {
                if search.isEmpty {
                    Section("Personas") {
                        ForEach(personas) { item in
                            Button {
                                start(item.payload, incognito: false)
                            } label: {
                                Label {
                                    Text(item.payload.name)
                                } icon: {
                                    PersonaAvatar(symbol: item.payload.symbol, size: 24)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("New incognito chat", systemImage: "eye.slash") { start(item.payload, incognito: true) }
                                Button("Edit", systemImage: "pencil") { editor = .edit(item.id, item.payload) }
                                Button("Make default", systemImage: "star") { store.makeDefault(item.id) }
                            }
                        }
                        Button {
                            editor = .new
                        } label: {
                            Label("New persona", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("History") {
                    ForEach(summaries) { summary in
                        ChatRow(summary: summary, showsChevron: false)
                            .tag(summary.id)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(summary.id) }
                            }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar)
            .navigationTitle("Chats")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New incognito chat", systemImage: "eye.slash") { start(nil, incognito: true) }
                    Button("New chat", systemImage: "square.and.pencil") { start(nil, incognito: false) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                #endif
            }
        } detail: {
            if let selection {
                NavigationStack {
                    ChatScreen(chatID: selection)
                        .id(selection)
                        .environment(\.closeChat, { self.selection = nil })
                }
            } else {
                SplitWelcome(personas: personas, needsKey: !vault.hasAPIKey) { persona in
                    start(persona, incognito: false)
                } openSettings: {
                    showSettings = true
                }
            }
        }
        .onChange(of: selection) { old, _ in
            if let old { store.release(old) }
        }
        .sheet(item: $editor) { PersonaEditor(target: $0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func start(_ persona: PersonaPayload?, incognito: Bool) {
        let session = store.newChat(persona: persona ?? store.defaultPersona(), incognito: incognito)
        selection = session.id
    }

    private func delete(_ id: UUID) {
        if selection == id { selection = nil }
        store.deleteChat(id)
    }
}

/// The empty detail pane: the home screen's glow, title and persona cards.
private struct SplitWelcome: View {
    let personas: [PersonaItem]
    let needsKey: Bool
    var start: (PersonaPayload) -> Void
    var openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Create, explore,\nbe inspired")
                    .font(Theme.display)
                if needsKey {
                    APIKeyBanner(action: openSettings)
                        .frame(maxWidth: 460)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(personas) { item in
                        Button {
                            start(item.payload)
                        } label: {
                            PersonaCard(persona: item.payload)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { GlowBackground() }
    }
}
