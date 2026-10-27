import ChatCore
import SwiftUI

/// Loads a chat by ID (decrypting it if it isn't open) and shows it.
struct ChatScreen: View {
    let chatID: UUID
    @Environment(SessionStore.self) private var store
    @State private var session: ChatSession?
    @State private var missing = false

    var body: some View {
        Group {
            if let session {
                ChatView(session: session)
            } else if missing {
                ContentUnavailableView(
                    "Can't open this chat",
                    systemImage: "lock",
                    description: Text("It may be encrypted with a key this device doesn't have yet.")
                )
            } else {
                ProgressView()
            }
        }
        .task(id: chatID) {
            session = store.session(for: chatID)
            missing = session == nil
        }
    }
}

struct ChatView: View {
    @Bindable var session: ChatSession
    @Environment(SessionStore.self) private var store
    @Environment(ModelCatalog.self) private var catalog
    @Environment(\.closeChat) private var closeChat

    @State private var speech = SpeechOutput()
    @State private var showSettings = false
    @State private var showVoice = false
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var nearBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if session.messages.isEmpty {
                        EmptyChatView(session: session)
                    }
                    ForEach(session.messages) { message in
                        MessageRow(message: message, isLast: message.id == session.messages.last?.id, session: session, speech: speech)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 120
            } action: { _, isNear in
                nearBottom = isNear
            }
            .onChange(of: session.messages.count) {
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.messages.last?.text) {
                if nearBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(session: session) { showVoice = true }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .dropDestination(for: URL.self) { urls, _ in
            Task { await session.attach(urls: urls) }
            return true
        }
        .navigationTitle(session.title.isEmpty ? session.personaName : session.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .primaryAction) { menu }
        }
        .onChange(of: session.settings) {
            // The settings sheet saves once when it closes rather than on every slider tick.
            if !showSettings { session.headerChanged() }
        }
        .sheet(isPresented: $showSettings, onDismiss: { session.headerChanged() }) {
            ChatSettingsSheet(session: session)
        }
        .voiceModePresentation(isPresented: $showVoice) {
            VoiceModeView(session: session)
        }
        .alert("Rename chat", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Save") {
                session.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                session.headerChanged()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteChat(session.id)
                closeChat()
            }
        } message: {
            Text("It will be removed from all your devices.")
        }
        .onDisappear { speech.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PersonaAvatar(symbol: session.personaSymbol, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.personaName)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if session.isIncognito { return "Incognito · not saved" }
        return session.title.isEmpty ? session.settings.model : session.title
    }

    private var menu: some View {
        Menu {
            Picker("Model", selection: $session.settings.model) {
                ForEach(catalog.options(including: session.settings.model), id: \.self) { Text($0).tag($0) }
            }
            Toggle("Thinking", systemImage: "brain", isOn: $session.settings.thinking)
            Button("Chat settings…", systemImage: "slider.horizontal.3") { showSettings = true }
            if !session.isIncognito {
                Divider()
                Button("Rename…", systemImage: "pencil") {
                    renameText = session.title
                    renaming = true
                }
                .disabled(!session.isPersisted)
                Button("Delete chat", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .disabled(!session.isPersisted)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }
}

private struct EmptyChatView: View {
    let session: ChatSession

    var body: some View {
        VStack(spacing: 14) {
            PersonaAvatar(symbol: session.personaSymbol, size: 72)
            Text(session.personaName)
                .font(.title2.weight(.semibold))
            Text(session.isIncognito ? "Incognito. Nothing here is saved." : "How can I help?")
                .foregroundStyle(.secondary)
            if !session.systemPrompt.isEmpty {
                Text(session.systemPrompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(maxWidth: 420)
                    .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    /// Full-screen on iPhone and iPad, a sheet on Mac.
    @ViewBuilder
    func voiceModePresentation<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented) {
            content().frame(minWidth: 420, minHeight: 560)
        }
        #endif
    }
}
