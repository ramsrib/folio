import SwiftUI

/// ⌘, — Settings as an in-window overlay in the palette chrome (not a separate
/// Settings window): it inherits the theme for free, the global Esc dismisses
/// it, and ⌘W can never close a tab hiding *behind* it. All changes apply live.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
                Text("Settings").font(.title3.weight(.semibold))
                Spacer()
                Button { ui.showSettings = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }
            .padding(16)
            Divider()
            form
        }
        .frame(width: 500, height: 500)
        .paletteSurface()
        .onExitCommand { ui.showSettings = false }
    }

    private var form: some View {
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
                .disabled(settings.fullWidth)
                Toggle("Full width", isOn: $settings.fullWidth)
                Text("Let the note fill the pane instead of sitting in a measured column. Wider lines are harder to read, but there's less to scroll.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Line breaks", selection: $settings.lineBreaks) {
                    ForEach(LineBreakMode.allCases) { Text($0.label).tag($0) }
                }
                Text(settings.lineBreaks.help)
                    .font(.caption).foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)   // let the palette surface show through
    }
}
