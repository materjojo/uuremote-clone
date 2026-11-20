import SwiftUI
import AppKit

struct PeerHostPanel: View {
    @ObservedObject var host: PeerHost
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("接收远程连接", systemImage: "display")
                Spacer()
                Button(host.running ? "停止接收" : "开启接收") {
                    if host.running { host.stop() } else { host.start() }
                }
            }
            if !host.running {
                TextField("自建信令服务地址", text: $host.server)
                    .textFieldStyle(.roundedBorder)
                Text("两端使用同一信令服务。公网使用 HTTPS；局域网或已连接的 Tailscale 可使用私网地址。")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Text(host.status).font(.caption).foregroundStyle(Theme.textSecondary)
            if !host.invitation.isEmpty {
                Button("复制本机配对码") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(host.invitation, forType: .string)
                }
            }
        }.padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
