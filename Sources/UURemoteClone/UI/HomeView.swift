import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch app.route {
            case .devices: DeviceGridView()
            case .files: FileTransferView()
            case .terminal: TerminalView()
            case .settings: SettingsView()
            }
        }
        .background(Theme.sidebar)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(L10n.appName).font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 22)

            ForEach(AppState.Route.allCases) { item in
                Button {
                    app.route = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(app.route == item ? Color.white.opacity(0.08) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()

            Divider().opacity(0.2)
            VStack(alignment: .leading, spacing: 10) {
                Button(L10n.feedback) {}
                Button(L10n.checkUpdate) {}
                Button(L10n.about) {}
                Button(L10n.logout) {}
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .padding(18)
        }
        .frame(minWidth: 190)
    }
}

struct DeviceGridView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var hovered: String?
    @State private var notice: String?

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("我的设备").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button {
                } label: {
                    Label(L10n.addDevice, systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }

            if app.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(app.devices) { device in
                            DeviceCard(device: device, hovered: hovered == device.id,
                                       onWake: { wake(device) })
                                .onHover { hovered = $0 ? device.id : nil }
                                .onTapGesture {
                                    app.connect(device)
                                    openWindow(id: "remote")
                                }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(.system(size: 12))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
            }
        }
    }

    private func wake(_ device: DeviceInfo) {
        Task {
            do {
                let info = try await APIClient.shared.wakeOnLANInfo(deviceID: device.deviceID)
                guard let mac = info?.usableMAC else {
                    await MainActor.run { notice = "未获取到该设备的 MAC 地址" }
                    return
                }
                let ok = WakeOnLAN.send(mac: mac,
                                        broadcast: info?.ip ?? "255.255.255.255",
                                        ports: [UInt16(info?.port ?? 9), 7])
                await MainActor.run { notice = ok ? "已发送唤醒魔术包" : "魔术包发送失败" }
            } catch {
                await MainActor.run { notice = error.localizedDescription }
            }
        }
    }
}

struct DeviceCard: View {
    let device: DeviceInfo
    let hovered: Bool
    var onWake: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: device.platform == "mac" ? "laptopcomputer" : "pc")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(device.online ? Theme.accent : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(device.online ? L10n.online : L10n.offline)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName).font(.system(size: 15, weight: .medium))
                Text(device.versionName ?? "").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            HStack {
                ForEach(device.tags ?? [], id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                Spacer()
                if !device.online, device.supportWOL == true, let onWake {
                    Button("远程开机", action: onWake)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(L10n.connect)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(device.online ? Theme.accent : Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .background(hovered ? Theme.cardHover : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

struct FileTransferView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 36))
            Text(L10n.files).font(.system(size: 18, weight: .medium))
            Text("连接后可在远控窗口中拖拽文件").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
    }
}

struct TerminalView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal").font(.system(size: 36))
            Text(L10n.terminal).font(.system(size: 18, weight: .medium))
            Text("通过 tmux 会话管理被控端终端").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.075, blue: 0.09))
    }
}
