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
struct TaskItem: Identifiable, Hashable {
    var id: String { file }
    let file: String
    let from: String
    let to: String
    let date: String
    let title: String
}

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

enum ThemeMode: String {
    case auto = "auto"
    case light = "light"
    case dark = "dark"
}

enum AccentPreset: String, CaseIterable {
    case blue = "007AFF"
    case purple = "9053F8"
    case yellow = "EAB308"
    case green = "22C55E"
    case red = "EF4444"
    
    var name: String {
        switch self {
        case .blue: return "🔵 经典蓝 (Apple Blue)"
        case .purple: return "🟣 极光紫 (Context Purple)"
        case .yellow: return "🟡 琥珀黄 (Warm Amber)"
        case .green: return "🟢 薄荷绿 (Fresh Green)"
        case .red: return "🔴 珊瑚红 (Coral Red)"
        }
    }
}

class AgentMonitor: ObservableObject {
    @Published var themeMode: ThemeMode = .auto
    @Published var accentHex: String = "007AFF"
    @Published var agyPending: Int = 0
    @Published var almaPending: Int = 0
    @Published var pingPending: Int = 0
    
    @Published var agyTasks: [TaskItem] = []
    @Published var almaTasks: [TaskItem] = []
    @Published var pingTasks: [TaskItem] = []
    
    @Published var funnelOnline: Bool = true
    @Published var nutstoreOnline: Bool = true
    @Published var tailscaleOnline: Bool = true
    
    @Published var currentMode: IslandMode = .compact
    @Published var selectedDrawerAgent: String? = nil
    @Published var pulse: Bool = false
    @Published var isDarkMode: Bool = false
    @Published var reconcileFeedback: String? = nil
    
    @Published var tokenTotal: String = "3.46B"
    @Published var tokenCacheRate: String = "94%"
    @Published var tokenTopModel: String = "Flash"
    
    var onModeChange: ((IslandMode) -> Void)?
    var onDrawerChange: (() -> Void)?
    
    private var lastKnownTotalPending: Int = -1
    private var timer: Timer?
    private var breathTimer: Timer?
    private var lastToggleTime: Date = Date.distantPast
    
    func canToggle() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastToggleTime) < 0.35 {
            return false
        }
        lastToggleTime = now
        return true
    }
    
    func setDrawerAgent(_ agent: String?) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                self.selectedDrawerAgent = agent
            }
            self.onDrawerChange?()
        }
    }
    
    let rootPath = "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs"
    let handoffScript = "/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts/handoff.py"
    
    init() {
        if let savedTheme = UserDefaults.standard.string(forKey: "agent_island_theme_mode"),
           let tm = ThemeMode(rawValue: savedTheme) {
            self.themeMode = tm
        }
        if let savedAccent = UserDefaults.standard.string(forKey: "agent_island_accent_hex") {
            self.accentHex = savedAccent
        }
        checkAppearance()
        refreshAll()
        startTimers()
    }
    
    func checkAppearance() {
        let dark: Bool
        switch themeMode {
        case .auto:
            dark = NSApplication.shared.effectiveAppearance.name.rawValue.lowercased().contains("dark")
        case .light:
            dark = false
        case .dark:
            dark = true
        }
        DispatchQueue.main.async {
            if self.isDarkMode != dark {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isDarkMode = dark
                }
            }
        }
    }
    
    func setThemeMode(_ mode: ThemeMode) {
        DispatchQueue.main.async {
            self.themeMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "agent_island_theme_mode")
            let isDark: Bool
            switch mode {
            case .auto:
                isDark = NSApplication.shared.effectiveAppearance.name.rawValue.lowercased().contains("dark")
            case .light:
                isDark = false
            case .dark:
                isDark = true
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isDarkMode = isDark
            }
            self.objectWillChange.send()
        }
    }
    
    func setAccentHex(_ hex: String) {
        DispatchQueue.main.async {
            self.accentHex = hex
            UserDefaults.standard.set(hex, forKey: "agent_island_accent_hex")
            self.objectWillChange.send()
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
            
            let data = self.fetchInboxesJSON()
            let fOnline = self.checkPort(host: "127.0.0.1", port: 8081)
            let nOnline = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier?.lowercased().contains("nutstore") == true ||
                $0.localizedName?.contains("坚果云") == true ||
                $0.localizedName?.lowercased().contains("nutstore") == true
            }
            let tOnline = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier?.contains("tailscale") == true || $0.localizedName?.lowercased().contains("tailscale") == true
            }
            
            DispatchQueue.main.async {
                let pingArr = data["ping"] ?? []
                let agyArr = data["agy"] ?? []
                let almaArr = data["alma"] ?? []
                
                self.pingTasks = pingArr
                self.agyTasks = agyArr
                self.almaTasks = almaArr
                
                self.pingPending = pingArr.count
                self.agyPending = agyArr.count
                self.almaPending = almaArr.count
                
                self.funnelOnline = fOnline
                self.nutstoreOnline = nOnline
                self.tailscaleOnline = tOnline
                
                if let telem = data["__telemetry__"]?.first {
                    self.tokenTotal = telem.file
                    self.tokenCacheRate = telem.title
                    self.tokenTopModel = telem.from
                }
                
                let currentTotal = pingArr.count + agyArr.count + almaArr.count
                let prevTotal = self.lastKnownTotalPending
                if prevTotal >= 0 && currentTotal > prevTotal {
                    self.triggerNotification(title: "📩 多 Agent 新待办到达", subtitle: "Ping: \(pingArr.count) | AGY: \(agyArr.count) | Alma: \(almaArr.count)")
                }
                self.lastKnownTotalPending = currentTotal
            }
        }
    }
    
    func triggerVerifyAndReconcile() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = ["-c", """
import os, sys, json, re
from pathlib import Path

ROOT = Path("/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs")
ACK_DIR = ROOT / ".ack"
REPLY_RE = re.compile(r"-reply\\d*\\.md$", re.IGNORECASE)
boxes = ["ping", "agy", "alma"]

reply_map = {}
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    for p in b_dir.iterdir():
        if p.is_file() and REPLY_RE.search(p.name):
            base = re.sub(r"-reply\\d*\\.md$", ".md", p.name, flags=re.IGNORECASE)
            reply_map[base] = f"{b}/{p.name}"
            try:
                txt = p.read_text(encoding="utf-8", errors="replace")
                for line in txt.splitlines():
                    if line.strip().startswith("reply_to:"):
                        rt = line.split(":", 1)[1].strip()
                        if rt and rt != "none":
                            reply_map[Path(rt).name] = f"{b}/{p.name}"
            except Exception:
                pass

reconciled = 0
for box in boxes:
    box_dir = ROOT / box
    if not box_dir.is_dir(): continue
    ack_file = ACK_DIR / f"{box}.json"
    acked = {}
    if ack_file.exists():
        try: acked = json.loads(ack_file.read_text(encoding="utf-8"))
        except Exception: pass
    all_files = [p for p in box_dir.iterdir() if p.is_file() and p.name.endswith(".md")]
    for p in all_files:
        if REPLY_RE.search(p.name): continue
        if p.name in acked: continue
        if p.name in reply_map:
            acked[p.name] = f"reconciled: 已见回信 {reply_map[p.name]}"
            reconciled += 1
    ack_file.write_text(json.dumps(acked, ensure_ascii=False, indent=2), encoding="utf-8")

# 3 天冷热归档触发（自动归档超 72h 且已结案的老单）
archived = 0
try:
    sys.path.insert(0, '/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts')
    import handoff
    arch_res = handoff.archive_stale_files(keep_days=3)
    archived = sum(arch_res.values())
except Exception:
    pass

print(f"RECONCILE_DONE:{reconciled}:{archived}")
"""]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outputData, encoding: .utf8) ?? ""
            var arcCount = 0
            if let m = outStr.components(separatedBy: "RECONCILE_DONE:").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = m.components(separatedBy: ":")
                if parts.count >= 2 {
                    arcCount = Int(parts[1]) ?? 0
                }
            }
            
            self.refreshAll()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let total = self.pingPending + self.agyPending + self.almaPending
                withAnimation(.spring()) {
                    if arcCount > 0 {
                        self.reconcileFeedback = "✅ 核验完成：自动归档 \(arcCount) 笔老单"
                    } else if total == 0 {
                        self.reconcileFeedback = "✅ 全网已闭环（0 待办）"
                    } else {
                        self.reconcileFeedback = "🔍 全网核验完成：仍有 \(total) 项真待办推进中"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    withAnimation { self.reconcileFeedback = nil }
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
    
    private func fetchInboxesJSON() -> [String: [TaskItem]] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", """
import sys, json, os, re
from pathlib import Path
sys.path.insert(0, '/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts')
import handoff

boxes = ['ping', 'agy', 'alma']
ROOT = handoff.HANDOFFS_ROOT

# Phase 1: Global reply index across all boxes (prevents cross-box blindspots)
global_replied = set()
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    for p in b_dir.iterdir():
        if not p.is_file() or handoff.is_ignored_file(p): continue
        if handoff.REPLY_RE.search(p.name) or p.name.startswith('cancel-'):
            base = handoff.re.sub(r'-reply\\d*\\.md$', '.md', p.name, flags=handoff.re.IGNORECASE)
            global_replied.add(base)
            global_replied.add(p.stem)
            try:
                meta, _ = handoff.parse_frontmatter(p.read_text(encoding='utf-8', errors='replace'))
                rt = str(meta.get('reply_to', '')).strip()
                if rt and rt != 'none':
                    global_replied.add(Path(rt).name)
                rel = meta.get('related', [])
                if isinstance(rel, list):
                    for item in rel:
                        global_replied.add(Path(str(item)).name)
            except Exception:
                pass

# Phase 2: Per-box pending extraction
res = {}
for box in boxes:
    inbox_dir = ROOT / box
    if not inbox_dir.is_dir():
        res[box] = []
        continue
    acked_names = handoff.load_ack(box)
    all_md = [p for p in inbox_dir.iterdir() if p.is_file() and not handoff.is_ignored_file(p)]
    items = []
    for p in all_md:
        if handoff.REPLY_RE.search(p.name) or p.name.startswith('cancel-'):
            continue
        if p.name in acked_names:
            continue
        if p.name in global_replied or p.stem in global_replied:
            continue
        try:
            text = p.read_text(encoding='utf-8', errors='replace')
            meta, body = handoff.parse_frontmatter(text)
            status = str(meta.get('status', '')).strip()
            if any(k in status for k in ('已完成', '作废', '已关闭', '已核销', '参考')):
                continue
            frm = str(meta.get('from', '')).strip().lower()
            if frm == box:
                continue
            items.append({
                'file': p.name,
                'from': str(meta.get('from', '未知')),
                'to': str(meta.get('to', box)),
                'date': str(meta.get('date', '-')),
                'title': handoff.first_heading(body) or p.stem,
                'mtime': p.stat().st_mtime
            })
        except Exception:
            pass
    items.sort(key=lambda x: x['mtime'], reverse=True)
    res[box] = items

# Deep Telemetry from token_usage_archive_v2 (Context & Quota Ledger)
telem_total = '--'
telem_cache = '--'
telem_model = 'Flash'
try:
    tp = Path('/Users/l/.gemini/antigravity/token_usage_archive_v2.json')
    if tp.exists():
        td = json.loads(tp.read_text(encoding='utf-8'))
        m = td.get('costEstimateCurrentMonth', {})
        cats = m.get('byCategory', {})
        tot = cats.get('inputTokens', 0) + cats.get('cacheTokens', 0) + cats.get('outputTokens', 0)
        c_rate = (cats.get('cacheTokens', 0) / tot * 100) if tot > 0 else 0
        def _fmt(n):
            if n >= 1000000000: return f"{n/1000000000:.2f}B"
            if n >= 1000000: return f"{n/1000000:.1f}M"
            if n >= 1000: return f"{n/1000:.1f}K"
            return str(n)
        top_m = sorted(m.get('byModel', {}).items(), key=lambda x: x[1].get('tokens', 0), reverse=True)
        t_name = top_m[0][0].replace('gemini-', '').replace('claude-', '') if top_m else 'Flash'
        telem_total = _fmt(tot)
        telem_cache = f"{c_rate:.0f}%"
        telem_model = t_name
except Exception:
    pass

res['__telemetry__'] = [{'file': telem_total, 'title': telem_cache, 'from': telem_model, 'to': 'self', 'date': '-', 'mtime': 0}]

print(json.dumps(res, ensure_ascii=False))
"""]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] {
                var output: [String: [TaskItem]] = [:]
                for (box, arr) in root {
                    output[box] = arr.compactMap { d in
                        guard let file = d["file"] as? String,
                              let from = d["from"] as? String,
                              let to = d["to"] as? String,
                              let date = d["date"] as? String,
                              let title = d["title"] as? String else { return nil }
                        return TaskItem(file: file, from: from, to: to, date: date, title: title)
                    }
                }
                return output
            }
        } catch {}
        return [:]
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
    
    var accentColor: Color {
        Color(hex: monitor.accentHex)
    }
    
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
                
                // Layer 2: Solid Obsidian & Ceramic Glass Tint (深浅色双模原生适配，对标 context-viewer)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        monitor.currentMode == .compact
                            ? (monitor.isDarkMode
                                ? Color.black.opacity(0.90)
                                : Color(hex: "FFFFFF").opacity(0.92))
                            : (monitor.isDarkMode
                                ? Color(hex: "080B12").opacity(0.88)
                                : Color.white.opacity(0.92))
                    )
                
                // Layer 3: Razor Specular Border (深浅色自适应金属高反差切面)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: monitor.isDarkMode ? Color.white.opacity(0.65) : Color.white.opacity(0.98), location: 0.0),
                                .init(color: monitor.isDarkMode ? Color.white.opacity(0.20) : Color.black.opacity(0.08), location: 0.45),
                                .init(color: monitor.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.14), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
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
                if monitor.currentMode == .compact {
                    guard monitor.canToggle() else { return }
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
            if let agent = monitor.selectedDrawerAgent {
                agentTaskDrawerView(agent: agent)
            } else {
                controlCenterExpandedView
            }
        }
    }
    
    // MARK: - Compact Mode (Matches UURemoteService Status Pill Exactly)
    var compactView: some View {
        HStack(spacing: 6) {
            // Blue/Green Status Badge Icon
            ZStack {
                Circle()
                    .fill(allHealthy ? accentColor : Color(hex: "FF9500"))
                    .frame(width: 15, height: 15)
                    .shadow(color: (allHealthy ? accentColor : Color(hex: "FF9500")).opacity(0.4), radius: 2)
                
                Image(systemName: allHealthy ? "cpu.fill" : "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("3 Agents")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(primaryTextColor)
            
            Text("•")
                .foregroundColor(secondaryTextColor)
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
                            .fill(accentColor)
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
                if let fb = monitor.reconcileFeedback {
                    Text(fb)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(totalPending == 0 ? Color(hex: "059669") : Color(hex: "D97706"))
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
                        iconBg: accentColor,
                        title: "白 / AGY",
                        subtitle: monitor.agyPending == 0 ? "空闲就绪" : "\(monitor.agyPending) 待办",
                        hasPending: monitor.agyPending > 0
                    ) {
                        monitor.setDrawerAgent("agy")
                    }
                    controlCenterPill(
                        icon: "bolt.fill",
                        iconBg: Color(hex: "FF9500"),
                        title: "Alma",
                        subtitle: monitor.almaPending == 0 ? "空闲巡检" : "\(monitor.almaPending) 待办",
                        hasPending: monitor.almaPending > 0
                    ) {
                        monitor.setDrawerAgent("alma")
                    }
                    controlCenterPill(
                        icon: "cloud.fill",
                        iconBg: Color(hex: "5856D6"),
                        title: "Ping (VM)",
                        subtitle: monitor.pingPending == 0 ? "空闲就绪" : "\(monitor.pingPending) 待办",
                        hasPending: monitor.pingPending > 0
                    ) {
                        monitor.setDrawerAgent("ping")
                    }
                }
                .frame(width: 175)
                
                // Right Column: Hero Squircle Card (Like the "未在播放" card in Control Center)
                VStack(spacing: 8) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(totalPending > 0 ? Color(hex: "D97706") : Color(hex: "059669"))
                                .frame(width: 22, height: 22)
                            Image(systemName: totalPending > 0 ? "hourglass" : "checkmark.shield.fill")
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
                    
                    // Deep Telemetry Badge (Antigravity Context & Ledger)
                    HStack(spacing: 5) {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.hexagongrid.fill")
                                .font(.system(size: 8))
                                .foregroundColor(accentColor)
                            Text(monitor.tokenTotal)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(primaryTextColor)
                        }
                        Text("·")
                            .font(.system(size: 8.5))
                            .foregroundColor(secondaryTextColor.opacity(0.4))
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7.5))
                                .foregroundColor(Color(hex: "34C759"))
                            Text("Cache \(monitor.tokenCacheRate)")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundColor(secondaryTextColor)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    
                    Spacer()
                    
                    // Big Action Button: Verify & Reconcile & Archive
                    Button(action: {
                        monitor.triggerVerifyAndReconcile()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 10, weight: .bold))
                            Text("🔍 全网核验与归档")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: totalPending > 0
                                            ? [Color(hex: "D97706"), Color(hex: "B45309")]
                                            : [Color(hex: "059669"), Color(hex: "047857")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: (totalPending > 0 ? Color(hex: "D97706") : Color(hex: "059669")).opacity(0.35), radius: 3, y: 1.5)
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
                actionSquircle(icon: "bubble.left.and.bubble.right.fill", label: "交流台账") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/交流.md"))
                }
            }
            .padding(.horizontal, 12)
            
            // Section 3: Sliders & Channels Row (Like Display / Sound bars in Control Center)
            HStack(spacing: 12) {
                channelItem(name: "Funnel 64M", isOk: monitor.funnelOnline) {
                    if monitor.funnelOnline {
                        if let u = URL(string: "https://lmac-mini.tail463092.ts.net/v1/health") {
                            NSWorkspace.shared.open(u)
                        }
                    } else {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                        p.arguments = ["kickstart", "-k", "gui/\(getuid())/com.lin.funnel-server"]
                        try? p.run()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            monitor.refreshAll()
                        }
                    }
                }
                channelItem(name: "坚果云", isOk: monitor.nutstoreOnline) {
                    if monitor.nutstoreOnline {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files"))
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Nutstore.app"))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            monitor.refreshAll()
                        }
                    }
                }
                channelItem(name: "Tailscale", isOk: monitor.tailscaleOnline) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
                }
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
    func controlCenterPill(icon: String, iconBg: Color, title: String, subtitle: String, hasPending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                        .foregroundColor(hasPending ? Color(hex: "D97706") : secondaryTextColor)
                }
                Spacer()
                if hasPending {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(Color(hex: "D97706"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(squircleCardBackground)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
    
    // Action Squircle
    func actionSquircle(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor)
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
    
    func channelItem(name: String, isOk: Bool, action: (() -> Void)? = nil) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOk ? Color(hex: "10B981") : Color(hex: "EF4444"))
                    .frame(width: 6, height: 6)
                    .shadow(color: (isOk ? Color(hex: "10B981") : Color(hex: "EF4444")).opacity(0.5), radius: 1.5)
                Text(name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(isOk ? secondaryTextColor : Color(hex: "EF4444"))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func agentDisplayName(_ agent: String) -> String {
        switch agent {
        case "agy": return "白 / AGY"
        case "alma": return "Alma"
        case "ping": return "Ping (VM)"
        default: return agent
        }
    }
    
    func agentTasks(_ agent: String) -> [TaskItem] {
        switch agent {
        case "agy": return monitor.agyTasks
        case "alma": return monitor.almaTasks
        case "ping": return monitor.pingTasks
        default: return []
        }
    }
    
    func agentTaskDrawerView(agent: String) -> some View {
        let tasks = agentTasks(agent)
        return VStack(spacing: 8) {
            // Header Row
            HStack {
                Button(action: {
                    monitor.setDrawerAgent(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("返回")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(accentColor.opacity(monitor.isDarkMode ? 0.20 : 0.12))
                    )
                }
                .buttonStyle(PressableScaleButtonStyle())
                
                Spacer()
                
                Text("\(agentDisplayName(agent)) · \(tasks.count) 项真待办")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(monitor.rootPath)/\(agent)"))
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 8.5))
                        Text("访达")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(secondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 10)
            .padding(.horizontal, 14)
            
            // Task List or Empty State
            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color(hex: "10B981"))
                    Text("无待办事项 · 处于就绪状态")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Text("所有历史单均已合规回信结案")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 5) {
                        ForEach(tasks) { task in
                            HStack(spacing: 7) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: "FF9500").opacity(0.18))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(Color(hex: "D97706"))
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(primaryTextColor)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text("\(task.from) → \(task.to)")
                                            .font(.system(size: 8.5, weight: .medium))
                                            .foregroundColor(secondaryTextColor)
                                        Text("•")
                                            .font(.system(size: 7))
                                            .foregroundColor(secondaryTextColor.opacity(0.6))
                                        Text(task.date)
                                            .font(.system(size: 8.5, weight: .medium))
                                            .foregroundColor(secondaryTextColor)
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    let path = "\(monitor.rootPath)/\(agent)/\(task.file)"
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                }) {
                                    Text("查看单据")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            Capsule()
                                                .fill(accentColor.opacity(monitor.isDarkMode ? 0.20 : 0.10))
                                        )
                                }
                                .buttonStyle(PressableScaleButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(squircleCardBackground)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 200)
            }
            
            // Bottom Guidance Line
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 7.5))
                    .foregroundColor(Color(hex: "D97706"))
                Text("露露掌握最高裁决权 · 见真实回信与产物方可收口")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(secondaryTextColor.opacity(0.85))
            }
            .padding(.bottom, 6)
        }
    }
    
    var squircleCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                monitor.isDarkMode
                    ? Color.white.opacity(0.16)
                    : Color.white.opacity(0.88)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        monitor.isDarkMode
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.95),
                        lineWidth: 0.9
                    )
            )
            .shadow(
                color: Color.black.opacity(monitor.isDarkMode ? 0.28 : 0.06),
                radius: 2.5,
                y: 1.2
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
        monitor.isDarkMode ? Color(hex: "9E9EA5") : Color(hex: "515156")
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
        case .expanded:
            return monitor.selectedDrawerAgent != nil ? 386 : 356
        }
    }
    
    var contentHeight: CGFloat {
        switch monitor.currentMode {
        case .compact: return 28
        case .notification: return 34
        case .expanded:
            return monitor.selectedDrawerAgent != nil ? 310 : 238
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
        return monitor.funnelOnline && monitor.nutstoreOnline && monitor.tailscaleOnline && totalPending == 0
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

// MARK: - Custom Hosting View with First Mouse Acceptance
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var islandPanel: DynamicIslandPanel!
    var monitor = AgentMonitor()
    
    var globalClickMonitor: Any?
    var localClickMonitor: Any?
    
    var themeAutoItem: NSMenuItem?
    var themeLightItem: NSMenuItem?
    var themeDarkItem: NSMenuItem?
    var accentMenuItems: [String: NSMenuItem] = [:]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusItem()
        setupIslandPanel()
        setupAutoDismissMonitors()
        
        monitor.onModeChange = { [weak self] mode in
            self?.updatePanelFrame(for: mode)
        }
        
        monitor.onDrawerChange = { [weak self] in
            guard let self = self else { return }
            self.updatePanelFrame(for: self.monitor.currentMode)
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
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "🏝️ 打开/收起中控台", action: #selector(toggleIsland), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "🔍 全网核验与归档", action: #selector(reconcileAll), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "📁 打开 Spaces 产物库", action: #selector(openSpaces), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "📝 打开《交流.md》", action: #selector(openCommLog), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "🌐 检查 Funnel 健康状态", action: #selector(openFunnelHealth), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())
        
        // 1. 外观模式子菜单 (Appearance Submenu)
        let themeMenu = NSMenu()
        let aItem = NSMenuItem(title: "⚙️ 跟随系统", action: #selector(setThemeAuto), keyEquivalent: "")
        aItem.target = self
        let lItem = NSMenuItem(title: "☀️ 浅色模式", action: #selector(setThemeLight), keyEquivalent: "")
        lItem.target = self
        let dItem = NSMenuItem(title: "🌙 深色模式", action: #selector(setThemeDark), keyEquivalent: "")
        dItem.target = self
        themeMenu.addItem(aItem)
        themeMenu.addItem(lItem)
        themeMenu.addItem(dItem)
        themeAutoItem = aItem
        themeLightItem = lItem
        themeDarkItem = dItem
        
        let themeParent = NSMenuItem(title: "🌓 外观模式", action: nil, keyEquivalent: "")
        themeParent.submenu = themeMenu
        menu.addItem(themeParent)
        
        // 2. 主题强调色子菜单 (Accent Color Submenu)
        let accentMenu = NSMenu()
        accentMenuItems.removeAll()
        for preset in AccentPreset.allCases {
            let it = NSMenuItem(title: preset.name, action: #selector(setAccentPresetAction(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = preset.rawValue
            accentMenu.addItem(it)
            accentMenuItems[preset.rawValue] = it
        }
        let accentParent = NSMenuItem(title: "🎨 主题强调色", action: nil, keyEquivalent: "")
        accentParent.submenu = accentMenu
        menu.addItem(accentParent)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "🚪 退出 AgentIsland", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        
        updateMenuCheckmarks()
    }
    
    func setupIslandPanel() {
        let initialRect = NSRect(x: 0, y: 0, width: 200, height: 48)
        islandPanel = DynamicIslandPanel(contentRect: initialRect)
        
        let hostingView = FirstMouseHostingView(rootView: DynamicIslandView(monitor: monitor))
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
            if monitor.selectedDrawerAgent != nil {
                windowWidth = 416
                windowHeight = 340
            } else {
                windowWidth = 390
                windowHeight = 265
            }
        }
        
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2.0
        let y = screenFrame.origin.y + screenFrame.height - windowHeight
        
        let targetRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        islandPanel.setFrame(targetRect, display: true, animate: false)
        
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
    
    @objc func reconcileAll() {
        monitor.triggerVerifyAndReconcile()
    }
    
    @objc func openSpaces() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"))
    }
    
    @objc func openCommLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/交流.md"))
    }
    
    @objc func openFunnelHealth() {
        if let u = URL(string: "https://lmac-mini.tail463092.ts.net/v1/health") {
            NSWorkspace.shared.open(u)
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        updateMenuCheckmarks()
    }
    
    func updateMenuCheckmarks() {
        themeAutoItem?.state = monitor.themeMode == .auto ? .on : .off
        themeLightItem?.state = monitor.themeMode == .light ? .on : .off
        themeDarkItem?.state = monitor.themeMode == .dark ? .on : .off
        
        for (hex, it) in accentMenuItems {
            it.state = monitor.accentHex == hex ? .on : .off
        }
    }
    
    @objc func setThemeAuto() {
        monitor.setThemeMode(.auto)
        updateMenuCheckmarks()
    }
    
    @objc func setThemeLight() {
        monitor.setThemeMode(.light)
        updateMenuCheckmarks()
    }
    
    @objc func setThemeDark() {
        monitor.setThemeMode(.dark)
        updateMenuCheckmarks()
    }
    
    @objc func setAccentPresetAction(_ sender: NSMenuItem) {
        if let hex = sender.representedObject as? String {
            monitor.setAccentHex(hex)
            updateMenuCheckmarks()
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
