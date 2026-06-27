import SwiftUI

/// Appearance settings — theme, reading font, and text size — mirroring the
/// macOS Settings, applied live via the shared AppSettings.
struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Reading") {
                    Picker("Font", selection: $settings.readingFont) {
                        ForEach(ReadingFont.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Text size: \(Int(settings.bodyFontSize))",
                            value: $settings.bodyFontSize, in: 12...28, step: 1)
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
