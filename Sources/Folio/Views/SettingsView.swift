import SwiftUI

/// Preferences window (⌘,). Appearance settings applied live across the app.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("Reading font", selection: $settings.readingFont) {
                    ForEach(ReadingFont.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Reading") {
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $settings.bodyFontSize, in: 13...24, step: 1)
                        Text("\(Int(settings.bodyFontSize)) pt").monospacedDigit().frame(width: 46, alignment: .trailing)
                    }
                }
                LabeledContent("Line width") {
                    HStack {
                        Slider(value: $settings.readableWidth, in: 560...980, step: 20)
                        Text("\(Int(settings.readableWidth))").monospacedDigit().frame(width: 46, alignment: .trailing)
                    }
                }
                Toggle("Show inline title", isOn: $settings.showInlineTitle)
                Text("The big page title above a note. The tab already shows the name; turning this off hides the title (rename via the file's context menu instead).")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Text rendering", selection: $settings.fontSmoothing) {
                    ForEach(FontSmoothing.allCases) { Text($0.label).tag($0) }
                }
                Text("Smooth/Smoother darken letter stems the way browsers do — fuller, softer text. Takes effect after relaunching Folio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        // The Settings window is its own scene, so the theme applied to the main
        // window doesn't reach it — mirror the color scheme and the theme's pane
        // tint here (a Paper-warm app with a stark system-gray Settings reads as
        // someone else's window).
        .scrollContentBackground(.hidden)
        .background(settings.paneBackground ?? Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.colorScheme)
    }
}
