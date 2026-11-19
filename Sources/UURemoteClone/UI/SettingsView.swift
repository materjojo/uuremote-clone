import SwiftUI

struct SettingsView: View {
    @AppStorage("autoStart") private var autoStart = false
    @AppStorage("virtualDisplay") private var virtualDisplay = false
    @AppStorage("closeToMenuBar") private var closeToMenuBar = true
    @AppStorage("allowSameAccount") private var allowSameAccount = false
    @AppStorage("frameLimit") private var frameLimit = 60.0
    @AppStorage("useH265") private var useH265 = true
    @AppStorage("useReliableTransport") private var useReliable = true
    @AppStorage("virtualDisplay") private var virtualDisplayEnabled = false
    @State private var unattended = UnattendedManager.shared.isEnabled
    @State private var category = 0
    @State private var notice: String?

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
                    Toggle("H.265 编码（VideoToolbox）", isOn: $useH265)
                    Toggle("弱网增强（KCP + RS-FEC）", isOn: $useReliable)
                    Toggle("无人值守（开机自启）", isOn: $unattended)
                        .onChange(of: unattended) { enabled in
                            do {
                                if enabled { try UnattendedManager.shared.enable() }
                                else { UnattendedManager.shared.disable() }
                                notice = enabled ? "已安装 LaunchAgent" : "已移除 LaunchAgent"
                            } catch {
                                notice = error.localizedDescription
                                unattended = UnattendedManager.shared.isEnabled
                            }
                        }
                    HStack {
                        Text("虚拟屏")
                        Spacer()
                        Button("创建测试") {
                            let vd = VirtualDisplayController()
                            if let id = vd.create(width: 1920, height: 1080) {
                                notice = "虚拟屏已创建 displayID=\(id)"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { vd.destroy() }
                            } else {
                                notice = "当前环境不支持 CGVirtualDisplay"
                            }
                        }
                    }
                    if let notice {
                        Text(notice).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
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
