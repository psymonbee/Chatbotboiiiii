import SwiftUI

/// First launch on a device with no key and no synced data.
struct WelcomeView: View {
    @Environment(Vault.self) private var vault
    @Environment(SessionStore.self) private var store
    @State private var confirmFirst = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 40)
                PersonaAvatar(symbol: "sparkle", size: 64)
                Text("Your own\nDeepSeek chat")
                    .font(Theme.display)
                VStack(alignment: .leading, spacing: 18) {
                    point("lock.fill", "History syncs between your iPhone and Mac through iCloud, encrypted with a key only your devices hold.")
                    point("sparkle", "Every chat starts empty. DeepSeek only sees the chat you're in.")
                    point("eye.slash", "Incognito chats are never saved anywhere.")
                }
                if let error = vault.setupError {
                    Text(error).font(.callout).foregroundStyle(Theme.pink)
                }
                VStack(spacing: 12) {
                    Button {
                        confirmFirst = true
                    } label: {
                        Text("Set up on this device")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Theme.gradient))
                    }
                    Button {
                        vault.waitForSync()
                    } label: {
                        Text("I already use it on another device")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(Capsule().strokeBorder(Theme.stroke))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background { GlowBackground() }
        .confirmationDialog("Is this the first device you're setting up?", isPresented: $confirmFirst, titleVisibility: .visible) {
            Button("Yes, create my encryption key") {
                if vault.createKey() { store.seedStarterPersonas() }
            }
        } message: {
            Text("Only do this once. Your other devices get the key from iCloud Keychain. A second key would split your history in two.")
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.icon)
                .frame(width: 24)
            Text(text)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// History has synced (or the user said they have another device) but the key hasn't arrived yet.
struct WaitingForKeyView: View {
    @Environment(Vault.self) private var vault
    @Environment(SessionStore.self) private var store
    @State private var confirmReplace = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Waiting for your key")
                .font(.title2.weight(.semibold))
            Text("Your encryption key is on its way from iCloud Keychain. This usually takes under a minute.\n\nCheck that iCloud Keychain (Passwords & Keychain) is on, and that this device uses the same Apple Account as your others.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Button("Check now") { vault.loadKey() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.magenta)
            Spacer()
            Button("Start over with a new key", role: .destructive) { confirmReplace = true }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GlowBackground(height: 300) }
        .task {
            while !Task.isCancelled, vault.state == .waitingForKey {
                if vault.loadKey() { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .confirmationDialog("Start over with a new key?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Create a new key", role: .destructive) {
                vault.replaceKey()
                store.seedStarterPersonas()
            }
        } message: {
            Text("Anything encrypted with your old key can no longer be read, on any device. Only do this if the old key is truly lost.")
        }
    }
}

/// Shown once after setup if no API key has arrived from another device.
struct APIKeySetupView: View {
    @Environment(Vault.self) private var vault
    var onSkip: () -> Void
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.icon)
            Text("Add your\nDeepSeek API key")
                .font(Theme.display)
            Text("It's stored in iCloud Keychain and syncs to your other devices, so you only paste it once.")
                .foregroundStyle(.secondary)
            HStack {
                SecureField("sk-…", text: $key)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                PasteButton(payloadType: String.self) { strings in
                    key = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            }
            Button {
                vault.setAPIKey(key)
            } label: {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Theme.gradient))
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            HStack {
                Link("Get a key at platform.deepseek.com", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                Spacer()
                Button("Skip", action: onSkip).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .font(.footnote)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GlowBackground() }
    }
}
