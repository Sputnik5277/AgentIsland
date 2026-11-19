import AppKit
import SwiftUI
import Foundation

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Native AppKit Visual Effect View (True Apple System Backdrop Blur)
struct AppleGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.wantsLayer = true
        return v
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Models & State
enum IslandMode: Equatable {
    case compact
    case notification(String, String)
    case expanded
    
    static func == (lhs: IslandMode, rhs: IslandMode) -> Bool {
        switch (lhs, rhs) {
        case (.compact, .compact): return true
        case (.expanded, .expanded): return true
        case let (.notification(t1, s1), .notification(t2, s2)): return t1 == t2 && s1 == s2
        default: return false
        }
    }
}

class AgentMonitor: ObservableObject {
    @Published var agyPending: Int = 0
    @Published var almaPending: Int = 0
    @Published var pingPending: Int = 0
    
    @Published var funnelOnline: Bool = true
    @Published var syncthingOnline: Bool = false
    
    @Published var currentMode: IslandMode = .compact
    @Published var pulse: Bool = false
    @Published var isDarkMode: Bool = false
    @Published var sweepFeedback: String? = nil
    
    var onModeChange: ((IslandMode) -> Void)?
    
    private var lastKnownTotalPending: Int = -1
    private var timer: Timer?
    private var breathTimer: Timer?
    
    let rootPath = "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs"
    let handoffScript = "/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts/handoff.py"
    
    init() {
        checkAppearance()
        refreshAll()
        startTimers()
    }
    
    func checkAppearance() {
        let dark = NSApplication.shared.effectiveAppearance.name.rawValue.lowercased().contains("dark")
        DispatchQueue.main.async {
            if self.isDarkMode != dark {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isDarkMode = dark
                }
            }
        }
    }
    
    func setMode(_ mode: IslandMode) {
        DispatchQueue.main.async {
            self.currentMode = mode
            self.onModeChange?(mode)
        }
    }
    
    func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAppearance()
            self?.refreshAll()
        }
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pulse.toggle()
            }
        }
    }
    
    func refreshAll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let agy = self.runInboxCount(box: "agy")
            let alma = self.runInboxCount(box: "alma")
            let ping = self.runInboxCount(box: "ping")
            
            let fOnline = self.checkPort(host: "127.0.0.1", port: 8081)
            let sOnline = self.checkPort(host: "127.0.0.1", port: 8384)
            
            DispatchQueue.main.async {
                let prevTotal = self.lastKnownTotalPending
                self.agyPending = agy
                self.almaPending = alma
                self.pingPending = ping
                self.funnelOnline = fOnline
                self.syncthingOnline = sOnline
                
                let currentTotal = agy + alma + ping
                if prevTotal >= 0 && currentTotal > prevTotal {
                    self.triggerNotification(title: "📩 多 Agent 新待办到达", subtitle: "Ping: \(ping) | AGY: \(agy) | Alma: \(alma)")
                }
                self.lastKnownTotalPending = currentTotal
            }
        }
    }
    
    func triggerSweepAll() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Sweep ack for ping, agy, alma
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = ["-c", """
import json, os, glob
root = "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs"
for box in ["ping", "agy", "alma"]:
    ack_file = os.path.join(root, ".ack", f"{box}.json")
    os.makedirs(os.path.dirname(ack_file), exist_ok=True)
    acked = {}
    if os.path.exists(ack_file):
        try: acked = json.load(open(ack_file))
        except: pass
    box_dir = os.path.join(root, box)
    if os.path.exists(box_dir):
        for f in os.listdir(box_dir):
            if f.endswith(".md") and not f.startswith(".") and not "-reply" in f:
                if f not in acked:
                    acked[f] = "一键全网收口: " + str(os.path.getmtime(os.path.join(box_dir, f)))
    with open(ack_file, "w") as out:
        json.dump(acked, out, ensure_ascii=False, indent=2)
print("SWEEP_OK")
"""]
            let pipe = Pipe()
            p.standardOutput = pipe
            do {
                try p.run()
                p.waitUntilExit()
            } catch {}
            
            DispatchQueue.main.async {
                withAnimation(.spring()) {
                    self.sweepFeedback = "⚡ 全网收口完成！待办归零"
                }
                self.refreshAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        self.sweepFeedback = nil
                    }
                }
            }
        }
    }
    
    func triggerNotification(title: String, subtitle: String) {
        setMode(.notification(title, subtitle))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self = self else { return }
            if case .notification = self.currentMode {
                self.setMode(.compact)
            }
        }
    }
    
    private func runInboxCount(box: String) -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [handoffScript, "inbox", box]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let out = String(data: data, encoding: .utf8) {
                if let match = out.range(of: #"共 (\d+) 条"#, options: .regularExpression) {
                    let sub = out[match]
                    let digits = sub.filter { "0123456789".contains($0) }
                    return Int(digits) ?? 0
                }
            }
        } catch {
            return 0
        }
        return 0
    }
    
    private func checkPort(host: String, port: Int32) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, "\(port)", &hints, &res) != 0 { return false }
        defer { freeaddrinfo(res) }
        guard let info = res?.pointee else { return false }
        let sock = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
        if sock < 0 { return false }
        defer { close(sock) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return connect(sock, info.ai_addr, info.ai_addrlen) == 0
    }
}

// MARK: - Pressable Button Style
struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Dynamic Island View (Apple Control Center 1:1 Layout)
struct DynamicIslandView: View {
    @ObservedObject var monitor: AgentMonitor
    
    var body: some View {
        ZStack {
            Color.clear
            
            // The Frosted Capsule or Control Center Panel
            ZStack {
                // Layer 1: Apple Native Visual Effect Blur (Auto Light / Dark)
                AppleGlassBackground(
                    material: monitor.isDarkMode ? .hudWindow : .popover,
                    blendingMode: .behindWindow
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                
                // Layer 2: Adaptive Glass Tint
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        monitor.isDarkMode
                            ? Color(hex: "0A1526").opacity(0.40)
                            : Color.white.opacity(0.35)
                    )
                
                // Layer 3: Razor Specular Border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(monitor.isDarkMode ? 0.55 : 0.88), location: 0.0),
                                .init(color: Color.white.opacity(monitor.isDarkMode ? 0.18 : 0.45), location: 0.45),
                                .init(color: Color.white.opacity(monitor.isDarkMode ? 0.08 : 0.20), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
                
                // Content View
                contentForCurrentMode
            }
            .frame(width: contentWidth, height: contentHeight)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: monitor.currentMode)
            .animation(.easeInOut(duration: 0.25), value: monitor.isDarkMode)
            // Soft Unclipped Ambient Shadow
            .shadow(
                color: Color.black.opacity(monitor.isDarkMode ? 0.45 : 0.16),
                radius: monitor.isDarkMode ? 12 : 8,
                x: 0,
                y: monitor.isDarkMode ? 5 : 3
            )
            .shadow(
                color: Color.black.opacity(monitor.isDarkMode ? 0.20 : 0.05),
                radius: 1.5,
                x: 0,
                y: 1
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if monitor.currentMode == .expanded {
                    monitor.setMode(.compact)
                } else {
                    monitor.setMode(.expanded)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    var contentForCurrentMode: some View {
        switch monitor.currentMode {
        case .compact:
            compactView
        case .notification(let title, let subtitle):
            notificationView(title: title, subtitle: subtitle)
        case .expanded:
            controlCenterExpandedView
        }
    }
    
    // MARK: - Compact Mode (Matches UURemoteService Status Pill Exactly)
    var compactView: some View {
        HStack(spacing: 6) {
            // Blue/Green Status Badge Icon
            ZStack {
                Circle()
                    .fill(allHealthy ? Color(hex: "007AFF") : Color(hex: "FF9500"))
                    .frame(width: 15, height: 15)
                    .shadow(color: (allHealthy ? Color(hex: "007AFF") : Color(hex: "FF9500")).opacity(0.4), radius: 2)
                
                Image(systemName: allHealthy ? "cpu.fill" : "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("3 Agents")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(primaryTextColor)
            
            Text("•")
                .foregroundColor(secondaryTextColor.opacity(0.8))
                .font(.system(size: 9))
            
            Text(statusSummary)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(statusTextColor)
        }
        .padding(.horizontal, 10)
    }
    
    func notificationView(title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF9500"))
                    .frame(width: 18, height: 18)
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 9, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }
    
    // MARK: - Apple Control Center 1:1 Layout (参考用户发来的控制中心截图)
    var controlCenterExpandedView: some View {
        VStack(spacing: 10) {
            // Header Row
            HStack {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "007AFF"))
                            .frame(width: 17, height: 17)
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.white)
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    Text("Agent 控制中心")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                }
                Spacer()
                
                // Status hint
                if let fb = monitor.sweepFeedback {
                    Text(fb)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "059669"))
                        .transition(.scale)
                } else {
                    Text("点外部或 Esc 收起")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(secondaryTextColor.opacity(0.8))
                }
                
                Button(action: {
                    monitor.setMode(.compact)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                        .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            
            // Section 1: Top 2-Column Grid (Like Wi-Fi / Bluetooth + Now Playing Card in Control Center)
            HStack(spacing: 9) {
                // Left Column: 3 Stacked Agent Squircle Capsules
                VStack(spacing: 6) {
                    controlCenterPill(
                        icon: "apple.terminal.fill",
                        iconBg: Color(hex: "007AFF"),
                        title: "白 / AGY",
                        subtitle: monitor.agyPending == 0 ? "空闲就绪" : "\(monitor.agyPending) 待办"
                    )
                    controlCenterPill(
                        icon: "bolt.fill",
                        iconBg: Color(hex: "FF9500"),
                        title: "Alma",
                        subtitle: monitor.almaPending == 0 ? "空闲巡检" : "\(monitor.almaPending) 待办"
                    )
                    controlCenterPill(
                        icon: "cloud.fill",
                        iconBg: Color(hex: "5856D6"),
                        title: "Ping (VM)",
                        subtitle: monitor.pingPending == 0 ? "空闲就绪" : "\(monitor.pingPending) 待办"
                    )
                }
                .frame(width: 175)
                
                // Right Column: Hero Squircle Card (Like the "未在播放" card in Control Center)
                VStack(spacing: 8) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "FF9500"))
                                .frame(width: 22, height: 22)
                            Image(systemName: "bolt.badge.clock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("全网待办")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Text("\(totalPending) 项")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(totalPending == 0 ? Color(hex: "059669") : Color(hex: "D97706"))
                        }
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Big One-Click Sweep Action Button
                    Button(action: {
                        monitor.triggerSweepAll()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("一键全网收口")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "007AFF"), Color(hex: "0051C7")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color(hex: "007AFF").opacity(0.35), radius: 3, y: 1.5)
                        )
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(squircleCardBackground)
            }
            .frame(height: 122)
            .padding(.horizontal, 12)
            
            // Section 2: Quick Action Squircles (Like Focus Mode / AirDrop row in Control Center)
            HStack(spacing: 8) {
                actionSquircle(icon: "photo.on.rectangle", label: "全景图 v28") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces/zi-yan-mcp-quan-jing-tu.html"))
                }
                actionSquircle(icon: "folder.fill", label: "Spaces 库") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"))
                }
                actionSquircle(icon: "arrow.triangle.2.circlepath", label: "Syncthing") {
                    if let u = URL(string: "http://127.0.0.1:8384") { NSWorkspace.shared.open(u) }
                }
            }
            .padding(.horizontal, 12)
            
            // Section 3: Sliders & Channels Row (Like Display / Sound bars in Control Center)
            HStack(spacing: 12) {
                channelItem(name: "Funnel", isOk: monitor.funnelOnline)
                channelItem(name: "Syncthing", isOk: monitor.syncthingOnline)
                channelItem(name: "Tailscale", isOk: true)
                Spacer()
                
                Button(action: {
                    monitor.refreshAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        Text("刷新")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(secondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
    
    // Squircle Capsule (Wi-Fi/Bluetooth style)
    func controlCenterPill(icon: String, iconBg: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(primaryTextColor)
                Text(subtitle)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(squircleCardBackground)
    }
    
    // Action Squircle
    func actionSquircle(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "007AFF"))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(squircleCardBackground)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
    
    func channelItem(name: String, isOk: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOk ? Color(hex: "10B981") : Color(hex: "EF4444"))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(secondaryTextColor)
        }
    }
    
    var squircleCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                monitor.isDarkMode
                    ? Color.white.opacity(0.12)
                    : Color.white.opacity(0.70)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        monitor.isDarkMode
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.85),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(monitor.isDarkMode ? 0.20 : 0.04),
                radius: 2,
                y: 1
            )
    }
    
    var totalPending: Int {
        monitor.agyPending + monitor.almaPending + monitor.pingPending
    }
    
    // Dynamic Typography Colors
    var primaryTextColor: Color {
        monitor.isDarkMode ? Color.white : Color(hex: "1D1D1F")
    }
    
    var secondaryTextColor: Color {
        monitor.isDarkMode ? Color(hex: "86868B") : Color(hex: "6E6E73")
    }
    
    var statusTextColor: Color {
        let total = totalPending
        if total == 0 {
            return Color(hex: "059669")
        } else {
            return Color(hex: "D97706")
        }
    }
    
    var contentWidth: CGFloat {
        switch monitor.currentMode {
        case .compact: return 165
        case .notification: return 320
        case .expanded: return 356
        }
    }
    
    var contentHeight: CGFloat {
        switch monitor.currentMode {
        case .compact: return 28
        case .notification: return 34
        case .expanded: return 238
        }
    }
    
    var cornerRadius: CGFloat {
        switch monitor.currentMode {
        case .compact: return 14
        case .notification: return 17
        case .expanded: return 18
        }
    }
    
    var allHealthy: Bool {
        return monitor.funnelOnline && (monitor.agyPending == 0)
    }
    
    var statusSummary: String {
        let total = totalPending
        if total == 0 {
            return "全空闲"
        } else {
            return "\(total) 待办"
        }
    }
}

// MARK: - AppKit Window Controller with Auto-Dismiss & Screen Tracking
class DynamicIslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false
        self.isExcludedFromWindowsMenu = true
        self.hidesOnDeactivate = false
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
    
    override func cancelOperation(_ sender: Any?) {
        // Esc key press
        NotificationCenter.default.post(name: NSNotification.Name("DismissIslandRequest"), object: nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var islandPanel: DynamicIslandPanel!
    var monitor = AgentMonitor()
    
    var globalClickMonitor: Any?
    var localClickMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        setupIslandPanel()
        setupAutoDismissMonitors()
        
        monitor.onModeChange = { [weak self] mode in
            self?.updatePanelFrame(for: mode)
        }
        
        // Listen to macOS System Appearance Theme Change (Light <-> Dark mode instantaneous switch)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.monitor.checkAppearance()
        }
        
        // Multi-Monitor Screen Change Listener
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePanelFrame(for: self?.monitor.currentMode ?? .compact)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DismissIslandRequest"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.monitor.setMode(.compact)
        }
    }
    
    // Auto-Dismiss on Blur (Click outside window to collapse)
    func setupAutoDismissMonitors() {
        // Global monitor: clicks outside app on desktop / other apps
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if self.monitor.currentMode == .expanded {
                let mouseLoc = NSEvent.mouseLocation
                if !self.islandPanel.frame.contains(mouseLoc) {
                    DispatchQueue.main.async {
                        self.monitor.setMode(.compact)
                    }
                }
            }
        }
        
        // Local monitor: clicks inside app
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if self.monitor.currentMode == .expanded {
                let mouseLoc = NSEvent.mouseLocation
                if !self.islandPanel.frame.contains(mouseLoc) {
                    DispatchQueue.main.async {
                        self.monitor.setMode(.compact)
                    }
                }
            }
            return event
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🏝️ 3A"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🏝️ 打开/收起中控台", action: #selector(toggleIsland), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "⚡ 一键全网收口", action: #selector(sweepAll), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "📁 打开 Spaces 产物库", action: #selector(openSpaces), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "🔄 打开 Syncthing Web", action: #selector(openSyncthing), keyEquivalent: "y"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "🚪 退出 AgentIsland", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    func setupIslandPanel() {
        let initialRect = NSRect(x: 0, y: 0, width: 200, height: 48)
        islandPanel = DynamicIslandPanel(contentRect: initialRect)
        
        let hostingView = NSHostingView(rootView: DynamicIslandView(monitor: monitor))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        islandPanel.contentView = hostingView
        
        updatePanelFrame(for: .compact)
        islandPanel.orderFrontRegardless()
    }
    
    func getActiveScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLoc, screen.frame, false) {
                return screen
            }
        }
        return NSScreen.main ?? (NSScreen.screens.first ?? NSScreen())
    }
    
    func updatePanelFrame(for mode: IslandMode) {
        let screen = getActiveScreen()
        let screenFrame = screen.frame
        
        let windowWidth: CGFloat
        let windowHeight: CGFloat
        
        switch mode {
        case .compact:
            windowWidth = 200
            windowHeight = 48
        case .notification:
            windowWidth = 360
            windowHeight = 54
        case .expanded:
            windowWidth = 390
            windowHeight = 265
        }
        
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2.0
        let y = screenFrame.origin.y + screenFrame.height - windowHeight
        
        let targetRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        islandPanel.setFrame(targetRect, display: true, animate: true)
        
        if mode == .expanded {
            islandPanel.makeKey()
        }
    }
    
    @objc func toggleIsland() {
        if monitor.currentMode == .expanded {
            monitor.setMode(.compact)
        } else {
            monitor.setMode(.expanded)
        }
        if !islandPanel.isVisible {
            updatePanelFrame(for: monitor.currentMode)
            islandPanel.orderFrontRegardless()
        }
    }
    
    @objc func sweepAll() {
        monitor.triggerSweepAll()
    }
    
    @objc func openSpaces() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"))
    }
    
    @objc func openSyncthing() {
        if let u = URL(string: "http://127.0.0.1:8384") {
            NSWorkspace.shared.open(u)
        }
    }
    
    @objc func quitApp() {
        if let g = globalClickMonitor { NSEvent.removeMonitor(g) }
        if let l = localClickMonitor { NSEvent.removeMonitor(l) }
        NSApp.terminate(nil)
    }
}

// MARK: - Main Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
