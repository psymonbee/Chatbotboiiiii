import ChatCore
import SwiftUI

enum PersonaEditorTarget: Identifiable {
    case new
    case edit(UUID, PersonaPayload)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id, _): id.uuidString
        }
    }
}

/// A persona is a reusable system prompt plus model settings. New chats copy it.
struct PersonaEditor: View {
    let target: PersonaEditorTarget
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonaPayload
    @State private var confirmDelete = false

    init(target: PersonaEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _draft = State(initialValue: PersonaPayload(name: "", symbol: "sparkle", prompt: "", settings: GenerationSettings()))
        case .edit(_, let payload):
            _draft = State(initialValue: payload)
        }
    }

    private var editingID: UUID? {
        if case .edit(let id, _) = target { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Text writer", text: $draft.name)
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(PersonaPayload.symbols, id: \.self) { symbol in
                            Button {
                                draft.symbol = symbol
                            } label: {
                                PersonaAvatar(symbol: symbol, size: 40)
                                    .overlay(Circle().strokeBorder(Theme.magenta, lineWidth: draft.symbol == symbol ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextEditor(text: $draft.prompt)
                        .frame(minHeight: 160)
                        .font(.body)
                } header: {
                    Text("System prompt")
                } footer: {
                    Text("Sent at the start of every chat that uses this persona. Leave it empty for none.")
                }
                GenerationSettingsSections(settings: $draft.settings)
                if let id = editingID {
                    Section {
                        Button("Delete persona", role: .destructive) { confirmDelete = true }
                    }
                    .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            store.deletePersona(id)
                            dismiss()
                        }
                    } message: {
                        Text("Existing chats keep their copy of its prompt.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingID == nil ? "New persona" : "Edit persona")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var payload = draft
                        payload.name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.savePersona(payload, id: editingID)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}

/// Per-chat prompt and settings. Changing them affects this chat only.
struct ChatSettingsSheet: View {
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $session.systemPrompt)
                        .frame(minHeight: 140)
                } header: {
                    Text("System prompt")
                } footer: {
                    Text("Applies to the next message you send in this chat.")
                }
                GenerationSettingsSections(settings: $session.settings)
            }
            .formStyle(.grouped)
            .navigationTitle("Chat settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
