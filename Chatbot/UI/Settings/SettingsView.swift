import ChatCore
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(Vault.self) private var vault
    @Environment(ModelCatalog.self) private var catalog
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PersonaRecord.sortOrder) private var personaRecords: [PersonaRecord]

    @State private var keyDraft = ""
    @State private var balance: String?
    @State private var balanceError: String?
    @State private var editor: PersonaEditorTarget?
    @State private var confirmRemoveKey = false

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                personaSection
                modelSection
                privacySection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Also needed on Mac, where Settings opens as a sheet from the API key banner.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await refresh() }
            .sheet(item: $editor) { PersonaEditor(target: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    // MARK: - Sections

    private var apiSection: some View {
        Section {
            if vault.hasAPIKey {
                LabeledContent("API key", value: "Saved")
                LabeledContent("Balance") {
                    if let balance {
                        Text(balance)
                    } else if let balanceError {
                        Text(balanceError).foregroundStyle(Theme.pink)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            HStack {
                SecureField(vault.hasAPIKey ? "Replace API key" : "Paste your API key", text: $keyDraft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                PasteButton(payloadType: String.self) { strings in
                    keyDraft = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            }
            if !keyDraft.isEmpty {
                Button("Save API key") {
                    vault.setAPIKey(keyDraft)
                    keyDraft = ""
                    Task { await refresh() }
                }
            }
            if vault.hasAPIKey {
                Button("Remove API key", role: .destructive) { confirmRemoveKey = true }
                    .confirmationDialog("Remove the API key from all your devices?", isPresented: $confirmRemoveKey, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            vault.setAPIKey("")
                            balance = nil
                        }
                    }
            }
            Link("Get an API key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
        } header: {
            Text("DeepSeek")
        } footer: {
            Text("Kept in iCloud Keychain, which syncs it end-to-end encrypted to your other devices. It's only ever sent to api.deepseek.com.")
        }
    }

    private var personaSection: some View {
        Section {
            ForEach(personaRecords) { record in
                if let persona = store.persona(record) {
                    Button {
                        editor = .edit(record.uuid, persona)
                    } label: {
                        HStack(spacing: 12) {
                            PersonaAvatar(symbol: persona.symbol, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.name).foregroundStyle(.primary)
                                Text(persona.settings.model).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if record.uuid == personaRecords.first?.uuid {
                                Text("Default").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Make default", systemImage: "star") { store.makeDefault(record.uuid) }
                        Button("Delete", systemImage: "trash", role: .destructive) { store.deletePersona(record.uuid) }
                    }
                }
            }
            Button("New persona", systemImage: "plus") { editor = .new }
        } header: {
            Text("Personas")
        } footer: {
            Text("A persona is a system prompt plus model settings. New chats copy it, so editing one never changes old chats. The first is used for quick new chats; long-press to change it.")
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(catalog.models, id: \.self) { model in
                HStack {
                    Text(model).monospaced()
                    Spacer()
                    if !catalog.acceptsImages(model) {
                        Text("No images").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button(catalog.isRefreshing ? "Refreshing…" : "Refresh model list") {
                Task { await catalog.refresh(apiKey: vault.apiKey) }
            }
            .disabled(catalog.isRefreshing || !vault.hasAPIKey)
            if !catalog.noImageModels.isEmpty {
                Button("Re-check image support") { catalog.resetImageChecks() }
            }
        } header: {
            Text("Models")
        } footer: {
            if let error = catalog.lastError {
                Text(error)
            } else {
                Text("Fetched from DeepSeek, so new models show up here without an app update.")
            }
        }
    }

    private var privacySection: some View {
        Section {
            LabeledContent("History key", value: vault.keyID.isEmpty ? "Not set up" : vault.displayKeyID)
                .monospaced()
        } header: {
            Text("Privacy")
        } footer: {
            Text("Chats, prompts and files are encrypted on this device before they sync through iCloud. The key lives in iCloud Keychain, so Apple only stores ciphertext. Each device should show the same history key. Every request to DeepSeek contains only the current chat.")
        }
    }

    private func refresh() async {
        guard let key = vault.apiKey else { return }
        balanceError = nil
        do {
            balance = try await DeepSeekClient(apiKey: key).balance().formatted
        } catch {
            balanceError = error.localizedDescription
        }
        await catalog.refresh(apiKey: key)
    }
}
