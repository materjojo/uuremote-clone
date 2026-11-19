import SwiftUI

struct SettingsView: View {
    @AppStorage("autoStart") private var autoStart = false
    @AppStorage("virtualDisplay") private var virtualDisplay = false
    @AppStorage("closeToMenuBar") private var closeToMenuBar = true
    @AppStorage("allowSameAccount") private var allowSameAccount = false
    @AppStorage("frameLimit") private var frameLimit = 60.0
    @State private var category = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.settings).font(.system(size: 22, weight: .semibold))

            Picker("", selection: $category) {
                Text(L10n.Setting.general).tag(0)
                Text(L10n.Setting.security).tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            if category == 0 {
                Form {
                    Toggle(L10n.Setting.autoStart, isOn: $autoStart)
                    Toggle(L10n.Setting.virtualDisplay, isOn: $virtualDisplay)
                    Toggle(L10n.Setting.hideToMenuBar, isOn: $closeToMenuBar)
                    VStack(alignment: .leading) {
                        Text(L10n.Control.frameLimit)
                        Slider(value: $frameLimit, in: 15...144, step: 15)
                        Text("\(Int(frameLimit)) fps").font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .formStyle(.grouped)
            } else {
                Form {
                    Toggle(L10n.Setting.allowSameAccount, isOn: $allowSameAccount)
                    HStack {
                        Text(L10n.Setting.systemPermission)
                        Spacer()
                        Button(L10n.Setting.configure) {}
                    }
                }
                .formStyle(.grouped)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
    }
}
