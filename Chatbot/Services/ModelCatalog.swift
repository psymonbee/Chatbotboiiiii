import Foundation
import Observation

/// The models this API key can use, fetched from `/models` so new ones appear without an update,
/// plus which of them have turned out not to accept images.
@MainActor
@Observable
final class ModelCatalog {
    static let fallback = ["deepseek-flash", "deepseek-v4-pro"]

    private(set) var models: [String]
    private(set) var noImageModels: Set<String>
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    init() {
        let defaults = UserDefaults.standard
        models = defaults.stringArray(forKey: "models") ?? Self.fallback
        noImageModels = Set(defaults.stringArray(forKey: "noImageModels") ?? [])
    }

    func refresh(apiKey: String?) async {
        guard let apiKey, !apiKey.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let list = try await DeepSeekClient(apiKey: apiKey).models()
            if !list.isEmpty {
                models = list.sorted()
                UserDefaults.standard.set(models, forKey: "models")
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The list for a picker, always including the current choice.
    func options(including current: String) -> [String] {
        models.contains(current) ? models : [current] + models
    }

    func acceptsImages(_ model: String) -> Bool {
        !noImageModels.contains(model)
    }

    /// Called when the API rejects an image for this model.
    func markNoImages(_ model: String) {
        noImageModels.insert(model)
        UserDefaults.standard.set(Array(noImageModels), forKey: "noImageModels")
    }

    func resetImageChecks() {
        noImageModels = []
        UserDefaults.standard.removeObject(forKey: "noImageModels")
    }
}
