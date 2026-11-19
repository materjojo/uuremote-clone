import SwiftUI

enum Theme {
    static let accent = Color(red: 0.36, green: 0.85, blue: 0.42)
    static let sidebar = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let card = Color(red: 0.13, green: 0.14, blue: 0.16)
    static let cardHover = Color(red: 0.17, green: 0.18, blue: 0.21)
    static let textSecondary = Color(white: 0.62)
}

/// 文案与官方 Localizable.strings 的键一一对应（已抽取 1976 条，此处为主流程子集）
enum L10n {
    static let appName = "网易UU远程"
    static let devices = "设备"
    static let files = "文件传输"
    static let terminal = "终端"
    static let settings = "设置"
    static let connect = "远程控制"
    static let addDevice = "如何添加设备"
    static let online = "在线"
    static let offline = "离线"
    static let thisDevice = "本机"
    static let logout = "退出登录"
    static let checkUpdate = "检查更新"
    static let about = "关于"
    static let feedback = "帮助与反馈"

    enum Control {
        static let screen = "显示屏"
        static let fullScreen = "全屏"
        static let exitFullScreen = "缩小"
        static let windowSetting = "窗口设置"
        static let quality = "画质"
        static let mouse = "鼠标"
        static let keyboard = "键盘"
        static let sound = "播放被控端声音"
        static let netInfo = "常驻显示网络状态"
        static let fileTransfer = "文件传输"
        static let opacity = "不透明度"
        static let frameLimit = "帧率上限"
        static let resolution = "分辨率"
    }

    enum Quality {
        static let fast = "流畅"
        static let general = "均衡"
        static let hd = "高清"
        static let bluray = "蓝光"
        static let auto = "自动"
        static let custom = "自定义"
    }

    enum Setting {
        static let general = "常规"
        static let security = "安全"
        static let autoStart = "开机自启动"
        static let virtualDisplay = "自动创建虚拟屏"
        static let closeWindow = "关闭窗口时"
        static let hideToMenuBar = "隐藏到菜单栏"
        static let quit = "退出主程序"
        static let receiveDir = "移动设备传输文件存储路径"
        static let allowSameAccount = "允许同账号控制本设备"
        static let systemPermission = "系统权限未完整配置，无法使用全部远程功能。"
        static let configure = "立即配置"
    }
}
