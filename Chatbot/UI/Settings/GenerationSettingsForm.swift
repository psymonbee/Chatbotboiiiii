import ChatCore
import SwiftUI

/// Model and sampling controls, shared by the persona editor and per-chat settings.
struct GenerationSettingsSections: View {
    @Binding var settings: GenerationSettings
    @Environment(ModelCatalog.self) private var catalog

    var body: some View {
        Section {
            Picker("Model", selection: $settings.model) {
                ForEach(catalog.options(including: settings.model), id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            Toggle("Thinking", isOn: $settings.thinking)
            if settings.thinking {
                Picker("Reasoning effort", selection: $settings.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Model")
        } footer: {
            if settings.thinking {
                Text("The model reasons before answering and you can read its thinking. Temperature has no effect while thinking is on.")
            }
        }

        Section {
            OptionalSlider(title: "Temperature", value: $settings.temperature, range: GenerationSettings.temperatureRange, defaultValue: 1, step: 0.05)
                .disabled(settings.thinking)
            OptionalSlider(title: "Top P", value: $settings.topP, range: GenerationSettings.topPRange, defaultValue: 1, step: 0.01)
            OptionalNumber(title: "Max tokens", value: $settings.maxTokens, range: GenerationSettings.maxTokensRange, defaultValue: 8192)
        } header: {
            Text("Sampling")
        } footer: {
            Text("Lower temperature is more focused, higher is more varied. DeepSeek suggests 0 for code and maths, 1.3 for conversation and 1.5 for creative writing.")
        }

        Section {
            Toggle("JSON output", isOn: $settings.jsonMode)
            TextField("Stop sequences, comma-separated", text: stopSequences)
                .autocorrectionDisabled()
        } header: {
            Text("Output")
        }
    }

    private var stopSequences: Binding<String> {
        Binding(
            get: { settings.stopSequences.joined(separator: ", ") },
            set: { text in
                settings.stopSequences = text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

/// A setting that is either left to the API ("Default") or set to a custom value.
struct OptionalSlider: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? defaultValue) : nil })) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value.map { String(format: "%.2f", $0) } ?? "Default")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let current = value {
                Slider(value: Binding(get: { current }, set: { value = $0 }), in: range, step: step)
            }
        }
    }
}

struct OptionalNumber: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let defaultValue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? defaultValue) : nil })) {
                HStack {
                    Text(title)
                    Spacer()
                    if value == nil {
                        Text("Default").foregroundStyle(.secondary)
                    }
                }
            }
            if value != nil {
                TextField(
                    title,
                    value: Binding(
                        get: { value ?? defaultValue },
                        set: { value = min(max($0, range.lowerBound), range.upperBound) }
                    ),
                    format: .number
                )
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            }
        }
    }
}
