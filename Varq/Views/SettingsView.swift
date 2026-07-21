import SwiftUI

struct SettingsView: View {
    @AppStorage("appAppearanceOverride") private var appearanceOverride: String = "system"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal])

            Form {
                Picker("Appearance", selection: $appearanceOverride) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceOverride) { _, newValue in
                    switch newValue {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    default: NSApp.appearance = nil
                    }
                }

                Section {
                    Text("Changes take effect immediately across the app.")
                        .font(VarqTypography.ui(.caption))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding()
        }
        .frame(width: 320, height: 160)
        .background(Color.varqParchment)
    }
}
