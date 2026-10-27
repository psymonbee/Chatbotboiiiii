import SwiftData
import SwiftUI

@main
struct ChatbotApp: App {
    private let container: ModelContainer
    @State private var vault: Vault
    @State private var catalog: ModelCatalog
    @State private var store: SessionStore

    init() {
        let container = Persistence.makeContainer()
        let vault = Vault()
        let catalog = ModelCatalog()
        self.container = container
        _vault = State(initialValue: vault)
        _catalog = State(initialValue: catalog)
        _store = State(initialValue: SessionStore(container: container, vault: vault, catalog: catalog))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .environment(catalog)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(vault)
                .environment(catalog)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .modelContainer(container)
        }
        #endif
    }
}

struct RootView: View {
    @Environment(Vault.self) private var vault
    @Environment(SessionStore.self) private var store
    @Environment(ModelCatalog.self) private var catalog
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("skippedAPIKeySetup") private var skippedAPIKeySetup = false

    var body: some View {
        Group {
            switch vault.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsSetup:
                WelcomeView()
            case .waitingForKey:
                WaitingForKeyView()
            case .ready:
                if !vault.hasAPIKey && !skippedAPIKeySetup {
                    APIKeySetupView { skippedAPIKeySetup = true }
                } else {
                    MainView()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            vault.bootstrap(hasExistingData: store.hasAnyData())
            await catalog.refresh(apiKey: vault.apiKey)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vault.refresh() }
        }
        .onChange(of: vault.hasAPIKey) { _, has in
            if has { Task { await catalog.refresh(apiKey: vault.apiKey) } }
        }
    }
}

/// Sidebar layout on Mac and iPad, stack on iPhone.
struct MainView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if sizeClass == .regular {
            SplitRoot()
        } else {
            PhoneRoot()
        }
        #else
        SplitRoot()
        #endif
    }
}
