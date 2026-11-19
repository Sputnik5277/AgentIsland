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
    var stage: String = "dispatched" // dispatched, accepted, submitted, confirmed
    var statusText: String = "待接单"
    var artifacts: String = ""
    var eta: String = ""
    var highlights: String = ""
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

    @Published var pendingConfirms: [TaskItem] = []
    @Published var totalDispatched: Int = 0
    @Published var totalAccepted: Int = 0
    @Published var totalSubmitted: Int = 0
    @Published var activeConfirmIndex: Int = 0
    
    @Published var agyTasks: [TaskItem] = []
    @Published var almaTasks: [TaskItem] = []
    @Published var pingTasks: [TaskItem] = []
    
    @Published var agyDoneTasks: [TaskItem] = []
    @Published var almaDoneTasks: [TaskItem] = []
    @Published var pingDoneTasks: [TaskItem] = []
    
    @Published var funnelOnline: Bool = true
    @Published var nutstoreOnline: Bool = true
    @Published var tailscaleOnline: Bool = true
    
    @Published var currentMode: IslandMode = .compact
    @Published var selectedDrawerAgent: String? = nil {
        didSet { self.onDrawerChange?() }
    }
    @Published var showTopology: Bool = false {
        didSet { self.onDrawerChange?() }
    }
    @Published var expandedTaskId: String? = nil
    
    func toggleTaskExpanded(_ id: String) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.20)) {
                if self.expandedTaskId == id {
                    self.expandedTaskId = nil
                } else {
                    self.expandedTaskId = id
                }
            }
            self.onDrawerChange?()
        }
    }
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
                let confirms = data["pending_confirms"] ?? []
                
                self.pingTasks = pingArr
                self.agyTasks = agyArr
                self.almaTasks = almaArr
                self.pendingConfirms = confirms
                
                self.pingDoneTasks = data["ping_done"] ?? []
                self.agyDoneTasks = data["agy_done"] ?? []
                self.almaDoneTasks = data["alma_done"] ?? []
                
                self.pingPending = pingArr.count
                self.agyPending = agyArr.count
                self.almaPending = almaArr.count
                
                let allActive = pingArr + agyArr + almaArr
                self.totalSubmitted = confirms.count
                self.totalAccepted = allActive.filter { $0.stage == "accepted" }.count
                self.totalDispatched = allActive.filter { $0.stage == "dispatched" }.count
                
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
    
    func confirmTask(file: String, dispatcher: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [
                self.handoffScript,
                "confirm",
                "--from", dispatcher,
                "--to-file", file,
                "--verdict", "灵动岛一键验收结案"
            ]
            try? p.run()
            p.waitUntilExit()
            self.refreshAll()
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



all_acked_bases = set()
for b in boxes + ['lulu']:
    for k in handoff.load_ack(b).keys():
        b_stem = k.replace('.md', '').split('-reply')[0].split('-audit')[0].split('-submit')[0]
        all_acked_bases.add(b_stem)

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

# Phase 2: Per-box pending extraction (Meituan 4-stage tracking)
res = {}
total_dispatched = 0
total_accepted = 0

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
            if any(k in status for k in ('已完成', '作废', '已关闭', '已核销', '参考', '已结案')):
                continue
            frm = str(meta.get('from', '')).strip().lower()
            if frm == box:
                continue

            base_stem = p.stem
            accept_file = p.parent / f"{base_stem}-accept.md"
            stage = "dispatched"
            status_text = "待接单"
            eta = ""
            if accept_file.exists():
                stage = "accepted"
                status_text = "履约中"
                total_accepted += 1
                try:
                    a_meta, a_body = handoff.parse_frontmatter(accept_file.read_text(encoding='utf-8', errors='replace'))
                    eta = str(a_meta.get('eta', '履约推进中'))
                except Exception: pass
            else:
                total_dispatched += 1

            items.append({
                'file': p.name,
                'from': str(meta.get('from', '未知')),
                'to': str(meta.get('to', box)),
                'date': str(meta.get('date', '-')),
                'title': handoff.first_heading(body) or p.stem,
                'mtime': p.stat().st_mtime,
                'stage': stage,
                'statusText': status_text,
                'artifacts': '',
                'eta': eta,
                'highlights': handoff.extract_highlights(text)
            })
        except Exception:
            pass
    items.sort(key=lambda x: x['mtime'], reverse=True)
    res[box] = items

# Phase 3: Pending Confirmations (发起方闭环核验中)
raw_confirms = []
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    for p in b_dir.iterdir():
        if not p.is_file() or handoff.is_ignored_file(p): continue
        if not handoff.REPLY_RE.search(p.name): continue
        try:
            txt = p.read_text(encoding='utf-8', errors='replace')
            meta, body = handoff.parse_frontmatter(txt)
            status = str(meta.get('status', '')).strip()
            if status != '待确认': continue
            to_agent = str(meta.get('to', '')).strip().lower()
            b_stem = p.name.replace('.md', '').split('-reply')[0].split('-audit')[0].split('-submit')[0]
            if b_stem in all_acked_bases: continue
            acked = handoff.load_ack(to_agent)
            if p.name in acked or b_stem in acked: continue
            raw_confirms.append({
                'file': f'{b}/{p.name}',
                'base': b_stem,
                'from': str(meta.get('from', '未知')),
                'to': to_agent,
                'date': str(meta.get('date', '-')),
                'title': handoff.first_heading(body) or p.stem,
                'mtime': p.stat().st_mtime,
                'stage': 'submitted',
                'statusText': '发起方核验中',
                'artifacts': str(meta.get('artifacts', '')),
                'eta': '发起方验收中',
                'highlights': handoff.extract_highlights(txt)
            })
        except Exception: pass

latest_by_base = {}
for item in raw_confirms:
    b_key = item['base']
    if b_key not in latest_by_base or item['mtime'] > latest_by_base[b_key]['mtime']:
        latest_by_base[b_key] = item

res['pending_confirms'] = sorted(latest_by_base.values(), key=lambda x: x['mtime'], reverse=True)

# Phase 4: Extract recent completed replies (Done Feed, only confirmed)
for box in boxes:
    inbox_dir = ROOT / box
    if not inbox_dir.is_dir(): continue
    all_md = [p for p in inbox_dir.iterdir() if p.is_file() and not handoff.is_ignored_file(p)]
    done_items = []
    for p in all_md:
        if handoff.REPLY_RE.search(p.name):
            try:
                txt = p.read_text(encoding='utf-8', errors='replace')
                meta, body = handoff.parse_frontmatter(txt)
                status = str(meta.get('status', '')).strip()
                if status == '待确认':
                    continue # 关键拦截：待确认单据严禁混入已办结流！
                title = handoff.first_heading(body) or p.stem
                done_items.append({
                    'file': p.name,
                    'from': str(meta.get('from', '未知')),
                    'to': str(meta.get('to', box)),
                    'date': str(meta.get('date', '-')),
                    'title': title,
                    'mtime': p.stat().st_mtime,
                    'stage': 'confirmed',
                    'statusText': '已结案',
                    'artifacts': str(meta.get('artifacts', '')),
                    'eta': '',
                    'highlights': handoff.extract_highlights(txt)
                })
            except Exception:
                pass
    done_items.sort(key=lambda x: x['mtime'], reverse=True)
    res[box + '_done'] = done_items[:3]

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
                        let stage = (d["stage"] as? String) ?? "dispatched"
                        let statusText = (d["statusText"] as? String) ?? "待接单"
                        let artifacts = (d["artifacts"] as? String) ?? ""
                        let eta = (d["eta"] as? String) ?? ""
                        let highlights = (d["highlights"] as? String) ?? ""
                        return TaskItem(file: file, from: from, to: to, date: date, title: title, stage: stage, statusText: statusText, artifacts: artifacts, eta: eta, highlights: highlights)
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
                
                // Layer 2: Solid Obsidian & Ceramic Glass Tint (深浅色双模原生适配，防HDR溢色强化)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        monitor.currentMode == .compact
                            ? (monitor.isDarkMode
                                ? Color.black.opacity(0.94)
                                : Color(hex: "FFFFFF").opacity(0.95))
                            : (monitor.isDarkMode
                                ? Color(hex: "080B12").opacity(0.95)
                                : Color.white.opacity(0.94))
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
            // Blue/Green/Purple Status Badge Icon
            ZStack {
                Circle()
                    .fill(compactBadgeColor)
                    .frame(width: 15, height: 15)
                    .shadow(color: compactBadgeColor.opacity(0.4), radius: 2)
                
                Image(systemName: compactBadgeIcon)
                    .font(.system(size: 7.5, weight: .bold))
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
    
    // MARK: - AgentIsland & Multi-Agent 架构控制中心 (苹果原厂大字阶与四层空间调度)
    var controlCenterExpandedView: some View {
        VStack(spacing: 8) {
            // Layer 1: Header Row (14pt 大标题 + 链路图切换 + 关闭/Esc)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.white)
                        .font(.system(size: 11, weight: .bold))
                }
                Text("AgentIsland 控制中心")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                
                // 顶部视图模式切换：工单流 vs 架构链路图
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.showTopology = false
                        }
                    }) {
                        Text("📋 调度工单")
                            .font(.system(size: 10.5, weight: !monitor.showTopology ? .bold : .medium, design: .rounded))
                            .foregroundColor(!monitor.showTopology ? Color.white : secondaryTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(!monitor.showTopology ? accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.showTopology = true
                        }
                    }) {
                        Text("🌐 全网链路图")
                            .font(.system(size: 10.5, weight: monitor.showTopology ? .bold : .medium, design: .rounded))
                            .foregroundColor(monitor.showTopology ? Color.white : secondaryTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(monitor.showTopology ? accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(2)
                .background(
                    Capsule().fill(monitor.isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                )
                
                Spacer()
                
                // Status hint / reconcile feedback
                if let fb = monitor.reconcileFeedback {
                    Text(fb)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(totalPending == 0 ? Color(hex: "059669") : Color(hex: "D97706"))
                        .transition(.scale)
                } else {
                    Text("Esc 收起")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(secondaryTextColor.opacity(0.8))
                }
                
                Button(action: {
                    monitor.setMode(.compact)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            
            // Layer 2: 黄金展示区 (工单流 vs 架构链路图)
            if monitor.showTopology {
                // 真正的全网四层立体架构全透明链路图
                architectureTopologyView
            } else {
                if !monitor.pendingConfirms.isEmpty {
                    liveDispatchHeroCardView
                        .padding(.horizontal, 14)
                } else {
                    autoloopReadyHeroCardView
                        .padding(.horizontal, 14)
                }
                
                // Layer 3: 三 Agent 实名横向并列卡 (3 Balanced Columns)
                HStack(spacing: 10) {
                    agentBalanceCard(
                        icon: "apple.terminal.fill",
                        iconBg: accentColor,
                        title: "白 / AGY",
                        subtitle: monitor.agyPending == 0 ? "前台就绪" : "\(monitor.agyPending) 项待办",
                        hasPending: monitor.agyPending > 0
                    ) {
                        monitor.setDrawerAgent("agy")
                    }
                    
                    agentBalanceCard(
                        icon: "bolt.fill",
                        iconBg: Color(hex: "FF9500"),
                        title: "Alma",
                        subtitle: monitor.almaPending == 0 ? "中台巡检" : "\(monitor.almaPending) 项待办",
                        hasPending: monitor.almaPending > 0
                    ) {
                        monitor.setDrawerAgent("alma")
                    }
                    
                    agentBalanceCard(
                        icon: "cloud.fill",
                        iconBg: Color(hex: "5856D6"),
                        title: "Ping (VM)",
                        subtitle: monitor.pingPending == 0 ? "云端总控" : "\(monitor.pingPending) 项待办",
                        hasPending: monitor.pingPending > 0
                    ) {
                        monitor.setDrawerAgent("ping")
                    }
                }
                .padding(.horizontal, 14)
            }
            
            // Layer 4: 底部收拢通道与资产入口 (Slim Footer)
            HStack(spacing: 10) {
                // 通道指示灯
                HStack(spacing: 8) {
                    channelItem(name: "Funnel 64M", isOk: monitor.funnelOnline) {
                        if monitor.funnelOnline {
                            if let u = URL(string: "https://lmac-mini.tail463092.ts.net/v1/health") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                    }
                    channelItem(name: "坚果云", isOk: monitor.nutstoreOnline) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files"))
                    }
                    channelItem(name: "Tailscale", isOk: monitor.tailscaleOnline) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
                    }
                }
                
                Spacer()
                
                // 快捷资产入口
                HStack(spacing: 8) {
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces/zi-yan-mcp-quan-jing-tu.html"))
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 10.5))
                            Text("全景图")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(secondaryTextColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"))
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10.5))
                            Text("Spaces")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(secondaryTextColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/交流.md"))
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 10.5))
                            Text("交流.md")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(secondaryTextColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        monitor.refreshAll()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }
    
    // 全网四层立体架构全透明链路图 (真实架构拓扑 · 过程100%全透明)
    var architectureTopologyView: some View {
        VStack(spacing: 7) {
            // Layer 1: 指挥层
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(hex: "D97706").opacity(0.18)).frame(width: 24, height: 24)
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: "D97706"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("【01 指挥层】露露 (Commander)").font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(primaryTextColor)
                    Text("iPhone 手机端 / Muse / 微信 — 意图发起与最高裁决").font(.system(size: 9.5, weight: .medium)).foregroundColor(secondaryTextColor)
                }
                Spacer()
                Text("意图源头").font(.system(size: 9, weight: .semibold)).foregroundColor(Color(hex: "D97706")).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(Color(hex: "D97706").opacity(0.12)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(squircleCardBackground)
            
            // Arrow 1
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.system(size: 8.5, weight: .bold)).foregroundColor(secondaryTextColor.opacity(0.5))
                Text("自然语言意图 / 手机点选决策卡").font(.system(size: 8.5, weight: .medium, design: .monospaced)).foregroundColor(secondaryTextColor.opacity(0.7))
            }
            
            // Layer 2: 总控层
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(hex: "5856D6").opacity(0.18)).frame(width: 24, height: 24)
                    Image(systemName: "cloud.fill").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "5856D6"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("【02 总控层】Ping (Dispatcher · 云端 VM)").font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(primaryTextColor)
                    Text("意图编译、全网派单 (Step 1)、指标核验、发起方结案 (Step 4)").font(.system(size: 9.5, weight: .medium)).foregroundColor(secondaryTextColor)
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(Color(hex: "10B981")).frame(width: 5, height: 5)
                    Text("云端常驻").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "10B981"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(squircleCardBackground)
            
            // Arrow 2: Dual Dedicated Channels
            HStack(spacing: 16) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 8))
                    Text("Funnel 443 HTTPS 专线 (100ms)").font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "059669"))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(hex: "059669").opacity(0.14)))
                
                HStack(spacing: 3) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 8))
                    Text("Tailscale SSH 专线").font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundColor(Color(hex: "3B82F6"))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(hex: "3B82F6").opacity(0.14)))
            }
            
            // Layer 3: 执行端双机协同
            HStack(spacing: 8) {
                // Mac Mini
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "apple.terminal.fill").font(.system(size: 10, weight: .bold)).foregroundColor(accentColor)
                        Text("【03 执行中台】Mac Mini").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(primaryTextColor)
                    }
                    Text("白/AGY (前台交互/代码走查) · Alma (中台)").font(.system(size: 8.5, weight: .medium)).foregroundColor(secondaryTextColor)
                    Text("Funnel 接收即广播: events.log ➔ autoloop").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "059669"))
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(squircleCardBackground)
                
                // Simulation PC
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "3B82F6"))
                        Text("【04 算力实机】模拟电脑").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(primaryTextColor)
                    }
                    Text("PFC3D 9012 / FLAC3D 9011 原生求解").font(.system(size: 8.5, weight: .medium)).foregroundColor(secondaryTextColor)
                    Text("IP 192.168.50.239 · 2400×1600 图件落盘").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Color(hex: "3B82F6"))
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(squircleCardBackground)
            }
        }
        .padding(.horizontal, 14)
    }

    // AgentIsland 架构调度·全透明履约焦点卡 (点开卡片可查看核心提炼重点)
    @ViewBuilder
    var liveDispatchHeroCardView: some View {
        let count = monitor.pendingConfirms.count
        if count > 0 {
            let safeIdx = min(max(0, monitor.activeConfirmIndex), count - 1)
            let item = monitor.pendingConfirms[safeIdx]
            
            VStack(spacing: 8) {
                // Header: 调度状态 + 轮播器
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "8B5CF6"))
                            .frame(width: 18, height: 18)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("架构调度 · 发起方亲自视觉验收闭环")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8B5CF6"))
                    
                    Spacer()
                    
                    if count > 1 {
                        HStack(spacing: 6) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx - 1 + count) % count
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 18, height: 18)
                                    .background(squircleCardBackground)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("\(safeIdx + 1)/\(count)")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx + 1) % count
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 18, height: 18)
                                    .background(squircleCardBackground)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 4)
                
                // Card Body (点击卡片展开提炼重点)
                VStack(alignment: .leading, spacing: 6) {
                    // Task Title + 4-Step Stepper
                    HStack(alignment: .center) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(1)
                        Spacer()
                        lifecycleStepperView(stage: item.stage)
                    }
                    
                    // Route & Artifact Link
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("履约方: \(item.from)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Color(hex: "3B82F6"))
                            Text("➔")
                                .font(.system(size: 9))
                                .foregroundColor(secondaryTextColor)
                            Text("派单方: \(item.to)")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(Color(hex: "8B5CF6"))
                        }
                        
                        if !item.artifacts.isEmpty {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(secondaryTextColor)
                            Button(action: {
                                let ap = item.artifacts.hasPrefix("/") ? item.artifacts : "\(monitor.rootPath)/../\(item.artifacts)"
                                NSWorkspace.shared.open(URL(fileURLWithPath: ap))
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right.square.fill")
                                        .font(.system(size: 9.5))
                                    Text("产物: \(item.artifacts)")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundColor(accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            monitor.toggleTaskExpanded(item.id)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8.5))
                                Text(monitor.expandedTaskId == item.id ? "收起" : "重点")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(monitor.expandedTaskId == item.id ? Color.white : accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule().fill(monitor.expandedTaskId == item.id ? accentColor : accentColor.opacity(monitor.isDarkMode ? 0.20 : 0.10))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            let path = "\(monitor.rootPath)/\(item.file)"
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }) {
                            Text("原文")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule().fill(monitor.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // 点开卡片展开核心提炼重点
                    if monitor.expandedTaskId == item.id {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(accentColor)
                                Text("核心提炼重点")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundColor(accentColor)
                            }
                            Text(item.highlights.isEmpty ? "（本单据暂无正文摘要）" : item.highlights)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(primaryTextColor)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "8B5CF6").opacity(monitor.isDarkMode ? 0.16 : 0.08))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    monitor.toggleTaskExpanded(item.id)
                }
            }
            .padding(10)
            .background(squircleCardBackground)
        }
    }
    
    // 全员就绪态 Hero 卡片 (AgentIsland & Autoloop 中台运行就绪)
    @ViewBuilder
    var autoloopReadyHeroCardView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "059669").opacity(monitor.isDarkMode ? 0.20 : 0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: "059669"))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("全网架构就绪 · 0 积压待办")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Text("•")
                        .foregroundColor(secondaryTextColor)
                    Text("Funnel 443 专线直达")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "059669"))
                }
                
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 9))
                            .foregroundColor(accentColor)
                        Text(monitor.tokenTotal)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                    }
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundColor(secondaryTextColor.opacity(0.4))
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8.5))
                            .foregroundColor(Color(hex: "34C759"))
                        Text("缓存率 \(monitor.tokenCacheRate)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                monitor.triggerVerifyAndReconcile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("全网核验")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "059669"))
                )
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
        .padding(12)
        .background(squircleCardBackground)
    }
    
    // 横向三等分 Agent 平衡卡片 (3 Balanced Cards)
    func agentBalanceCard(icon: String, iconBg: Color, title: String, subtitle: String, hasPending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(iconBg)
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    if hasPending {
                        Circle()
                            .fill(Color(hex: "8B5CF6"))
                            .frame(width: 7, height: 7)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(hasPending ? Color(hex: "8B5CF6") : secondaryTextColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(squircleCardBackground)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
    
    // 四段架构履约轴 (派单 ➔ 接单 ➔ 待验 ➔ 结案)
    func lifecycleStepperView(stage: String) -> some View {
        HStack(spacing: 3) {
            stepperNode(name: "派单", active: true, done: stage != "dispatched")
            Text("›").font(.system(size: 8.5)).foregroundColor(secondaryTextColor)
            stepperNode(name: "接单", active: stage == "accepted" || stage == "submitted" || stage == "confirmed", done: stage == "submitted" || stage == "confirmed")
            Text("›").font(.system(size: 8.5)).foregroundColor(secondaryTextColor)
            stepperNode(name: "待验", active: stage == "submitted" || stage == "confirmed", done: stage == "confirmed", highlight: stage == "submitted")
            Text("›").font(.system(size: 8.5)).foregroundColor(secondaryTextColor)
            stepperNode(name: "结案", active: stage == "confirmed", done: stage == "confirmed")
        }
    }

    func stepperNode(name: String, active: Bool, done: Bool, highlight: Bool = false) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(highlight ? Color(hex: "8B5CF6") : (active ? (done ? Color(hex: "10B981") : accentColor) : secondaryTextColor.opacity(0.35)))
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 9.5, weight: highlight || done || active ? .bold : .medium, design: .rounded))
                .foregroundColor(highlight ? Color(hex: "8B5CF6") : (active ? (done ? Color(hex: "10B981") : primaryTextColor) : secondaryTextColor))
        }
        .padding(.horizontal, 4.5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(highlight ? Color(hex: "8B5CF6").opacity(0.18) : (active ? (done ? Color(hex: "10B981").opacity(0.12) : accentColor.opacity(0.10)) : Color.clear))
        )
    }
    
    func channelItem(name: String, isOk: Bool, action: (() -> Void)? = nil) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOk ? Color(hex: "10B981") : Color(hex: "EF4444"))
                    .frame(width: 6, height: 6)
                    .shadow(color: (isOk ? Color(hex: "10B981") : Color(hex: "EF4444")).opacity(0.5), radius: 1.5)
                Text(name)
                    .font(.system(size: 10.5, weight: .semibold))
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

    func agentDoneTasks(_ agent: String) -> [TaskItem] {
        switch agent {
        case "agy": return monitor.agyDoneTasks
        case "alma": return monitor.almaDoneTasks
        case "ping": return monitor.pingDoneTasks
        default: return []
        }
    }

    func agentTaskDrawerView(agent: String) -> some View {
        let tasks = agentTasks(agent)
        let dones = agentDoneTasks(agent)
        return VStack(spacing: 10) {
            // Header Row (14pt 大标题 + 粗体返回)
            HStack {
                Button(action: {
                    monitor.setDrawerAgent(nil)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("返回")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(accentColor.opacity(monitor.isDarkMode ? 0.22 : 0.12))
                    )
                }
                .buttonStyle(PressableScaleButtonStyle())
                
                Spacer()
                
                Text("\(agentDisplayName(agent)) · \(tasks.count) 项真待办")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(monitor.rootPath)/\(agent)"))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10.5))
                        Text("访达")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(monitor.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            
            // Task List + Done Feed Section (自适应展开 · 杜绝巨幅空白)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    // 1. Pending Tasks Section (if any)
                    if !tasks.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(tasks) { task in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(task.stage == "accepted" ? Color(hex: "3B82F6").opacity(0.18) : (task.stage == "submitted" ? Color(hex: "8B5CF6").opacity(0.18) : Color(hex: "FF9500").opacity(0.18)))
                                                .frame(width: 24, height: 24)
                                            Image(systemName: task.stage == "accepted" ? "bolt.fill" : (task.stage == "submitted" ? "bell.badge.fill" : "doc.text.fill"))
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(task.stage == "accepted" ? Color(hex: "3B82F6") : (task.stage == "submitted" ? Color(hex: "8B5CF6") : Color(hex: "D97706")))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                                .foregroundColor(primaryTextColor)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                lifecycleStepperView(stage: task.stage)
                                                Text("•").font(.system(size: 8)).foregroundColor(secondaryTextColor.opacity(0.6))
                                                Text("\(task.from) ➔ \(task.to)")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                if !task.eta.isEmpty {
                                                    Text("• \(task.eta)")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundColor(Color(hex: "3B82F6"))
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Action buttons (点开卡片查看重点)
                                        HStack(spacing: 6) {
                                            Button(action: {
                                                monitor.toggleTaskExpanded(task.id)
                                            }) {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: 8.5))
                                                    Text(monitor.expandedTaskId == task.id ? "收起" : "重点")
                                                        .font(.system(size: 10, weight: .bold))
                                                }
                                                .foregroundColor(monitor.expandedTaskId == task.id ? Color.white : accentColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(
                                                    Capsule().fill(monitor.expandedTaskId == task.id ? accentColor : accentColor.opacity(monitor.isDarkMode ? 0.20 : 0.10))
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(task.file)"
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            }) {
                                                Text("原文")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3.5)
                                                    .background(
                                                        Capsule().fill(monitor.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    
                                    // 点开卡片展开核心提炼重点！
                                    if monitor.expandedTaskId == task.id {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "text.quote")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(accentColor)
                                                Text("核心提炼重点")
                                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                                    .foregroundColor(accentColor)
                                            }
                                            Text(task.highlights.isEmpty ? "（本单据暂无正文摘要）" : task.highlights)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(primaryTextColor)
                                                .lineSpacing(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                                        )
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(squircleCardBackground)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    monitor.toggleTaskExpanded(task.id)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: "059669"))
                            Text("当前无积压待办 · 全员就绪")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "059669"))
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 2. Done Feed Section (Recent Completed Replies)
                    if !dones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 10))
                                    .foregroundColor(secondaryTextColor)
                                Text("最新结案回信 · 已办结流")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(secondaryTextColor)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            
                            VStack(spacing: 6) {
                                ForEach(dones) { done in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(hex: "059669").opacity(0.16))
                                                    .frame(width: 22, height: 22)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(Color(hex: "059669"))
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(done.title)
                                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                                    .foregroundColor(primaryTextColor)
                                                    .lineLimit(1)
                                                HStack(spacing: 4) {
                                                    Text("回件: \(done.from) ➔ \(done.to)")
                                                        .font(.system(size: 9.5, weight: .medium))
                                                        .foregroundColor(secondaryTextColor)
                                                    Text("•").font(.system(size: 8)).foregroundColor(secondaryTextColor.opacity(0.5))
                                                    Text(done.date)
                                                        .font(.system(size: 9.5))
                                                        .foregroundColor(secondaryTextColor)
                                                }
                                            }
                                            Spacer()
                                            
                                            Button(action: {
                                                monitor.toggleTaskExpanded(done.id)
                                            }) {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: 8.5))
                                                    Text(monitor.expandedTaskId == done.id ? "收起" : "重点")
                                                        .font(.system(size: 10, weight: .bold))
                                                }
                                                .foregroundColor(monitor.expandedTaskId == done.id ? Color.white : accentColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(
                                                    Capsule().fill(monitor.expandedTaskId == done.id ? accentColor : accentColor.opacity(monitor.isDarkMode ? 0.20 : 0.10))
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(done.file)"
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            }) {
                                                Text("原文")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3.5)
                                                    .background(
                                                        Capsule().fill(monitor.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        // 点开回信卡片展开核心提炼重点！
                                        if monitor.expandedTaskId == done.id {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "text.quote")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(accentColor)
                                                    Text("核心提炼重点")
                                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                                        .foregroundColor(accentColor)
                                                }
                                                Text(done.highlights.isEmpty ? "（本回信暂无正文摘要）" : done.highlights)
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .foregroundColor(primaryTextColor)
                                                    .lineSpacing(3)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(monitor.isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(squircleCardBackground)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        monitor.toggleTaskExpanded(done.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Bottom Guidance Line
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "D97706"))
                Text("露露掌握最高裁决权 · 见真实回信与产物方可收口")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(secondaryTextColor.opacity(0.85))
            }
            .padding(.bottom, 8)
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
    
    var compactBadgeColor: Color {
        if !monitor.funnelOnline || !monitor.nutstoreOnline || !monitor.tailscaleOnline {
            return Color(hex: "EF4444")
        }
        let totalWorking = monitor.totalAccepted + monitor.totalSubmitted + monitor.totalDispatched
        if totalWorking > 0 {
            return Color(hex: "3B82F6") // 动感蓝：系统调度履约中，不催促用户
        }
        return Color(hex: "10B981") // 薄荷绿：全员就绪
    }

    var compactBadgeIcon: String {
        if !monitor.funnelOnline || !monitor.nutstoreOnline || !monitor.tailscaleOnline {
            return "exclamationmark.triangle.fill"
        }
        let totalWorking = monitor.totalAccepted + monitor.totalSubmitted + monitor.totalDispatched
        if totalWorking > 0 {
            return "bolt.fill"
        }
        return "checkmark.shield.fill"
    }

    var statusTextColor: Color {
        compactBadgeColor
    }
    
    var contentWidth: CGFloat {
        switch monitor.currentMode {
        case .compact: return monitor.totalSubmitted > 0 || monitor.totalAccepted > 0 ? 196 : 176
        case .notification: return 340
        case .expanded:
            return 520
        }
    }
    
    var contentHeight: CGFloat {
        switch monitor.currentMode {
        case .compact: return 28
        case .notification: return 32
        case .expanded:
            let extra = monitor.expandedTaskId != nil ? 65 : 0
            if monitor.selectedDrawerAgent != nil {
                let ag = monitor.selectedDrawerAgent ?? ""
                let tCount = agentTasks(ag).count
                let dCount = agentDoneTasks(ag).count
                return CGFloat(((tCount + dCount <= 4) ? 260 : 330) + extra)
            } else if monitor.showTopology {
                return 248
            } else {
                return CGFloat((monitor.pendingConfirms.isEmpty ? 204 : 278) + extra)
            }
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
        return monitor.funnelOnline && monitor.nutstoreOnline && monitor.tailscaleOnline && totalPending == 0 && monitor.totalSubmitted == 0
    }
    
    var statusSummary: String {
        if !monitor.funnelOnline || !monitor.nutstoreOnline || !monitor.tailscaleOnline {
            return "通道异常"
        }
        let totalWorking = monitor.totalAccepted + monitor.totalSubmitted + monitor.totalDispatched
        if totalWorking > 0 {
            return "\(totalWorking) 项履约中"
        }
        return "全员就绪"
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
            windowWidth = 220
            windowHeight = 36
        case .notification:
            windowWidth = 364
            windowHeight = 40
        case .expanded:
            windowWidth = 544
            let extra = monitor.expandedTaskId != nil ? 65 : 0
            if monitor.selectedDrawerAgent != nil {
                let ag = monitor.selectedDrawerAgent ?? ""
                let tCount = (ag == "agy" ? monitor.agyTasks.count : (ag == "alma" ? monitor.almaTasks.count : monitor.pingTasks.count))
                let dCount = (ag == "agy" ? monitor.agyDoneTasks.count : (ag == "alma" ? monitor.almaDoneTasks.count : monitor.pingDoneTasks.count))
                windowHeight = CGFloat(((tCount + dCount <= 4) ? 276 : 346) + extra)
            } else if monitor.showTopology {
                windowHeight = 264
            } else {
                windowHeight = CGFloat((monitor.pendingConfirms.isEmpty ? 220 : 294) + extra)
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
