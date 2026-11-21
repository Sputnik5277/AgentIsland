import AppKit
import CoreGraphics
import SwiftUI
import Foundation
import UniformTypeIdentifiers

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

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF)
        let g = CGFloat((int >> 8) & 0xFF)
        let b = CGFloat(int & 0xFF)
        self.init(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
}

// MARK: - Native AppKit Visual Effect View (True Apple System Backdrop Blur)
struct AppleGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    /// 玻璃材质档位（按皮肤策略选择 clear/regular）
    enum GlassStyle { case regular, clear }
    /// macOS 26+ 原生液态玻璃的皮肤色（tintColor 保住三皮肤可区分）
    var glassTint: NSColor = .clear
    var glassStyle: GlassStyle = .regular
    var cornerRadius: CGFloat = 16
    /// 像素验收时可用 AGENT_ISLAND_GLASS=0 强制走旧 NSVisualEffectView 对照组
    var forceFallback: Bool = ProcessInfo.processInfo.environment["AGENT_ISLAND_GLASS"] == "0"

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), !forceFallback {
            let v = NSGlassEffectView()
            v.style = glassStyle == .clear ? .clear : .regular
            v.cornerRadius = cornerRadius
            v.tintColor = glassTint
            if #available(macOS 27.0, *) {
                v.effectIsInteractive = false
            }
            return v
        }
        return makeFallback()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let v = nsView as? NSGlassEffectView, !forceFallback {
            v.style = glassStyle == .clear ? .clear : .regular
            v.cornerRadius = cornerRadius
            v.tintColor = glassTint
            return
        }
        guard let v = nsView as? NSVisualEffectView else { return }
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
    }

    private func makeFallback() -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.wantsLayer = true
        return v
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
        case .blue: return "经典蓝 (Apple Blue)"
        case .purple: return "极光紫 (Context Purple)"
        case .yellow: return "琥珀黄 (Warm Amber)"
        case .green: return "薄荷绿 (Fresh Green)"
        case .red: return "珊瑚红 (Coral Red)"
        }
    }
}

// MARK: - Agent Identity (固定色彩 · 靠色认人 · 任何位置颜色不变)
struct AgentIdentity: Identifiable, Hashable {
    let key: String
    let title: String
    let short: String
    let symbol: String
    let hex: String
    var id: String { key }
    var color: Color { Color(hex: hex) }
}

enum AgentRoster {
    static let agy = AgentIdentity(key: "agy", title: "AGY", short: "AGY", symbol: "apple.terminal.fill", hex: "0A84FF")
    static let alma = AgentIdentity(key: "alma", title: "Alma", short: "Alma", symbol: "wrench.and.screwdriver.fill", hex: "FF9F0A")
    static let ping = AgentIdentity(key: "ping", title: "Ping", short: "Ping", symbol: "cloud.fill", hex: "7C3AED")
    static let all: [AgentIdentity] = [agy, alma, ping]

    static func identity(for key: String?) -> AgentIdentity? {
        guard let key = key?.lowercased() else { return nil }
        return all.first { $0.key == key }
    }
}

/// 最近一次真实通讯（来自 Funnel events.log 或 handoff 文件 mtime）
struct AgentCommPulse: Identifiable, Equatable {
    let source: String
    let target: String
    let count: Int
    let lastAt: Date
    var id: String { source + "->" + target }
}

// MARK: - 外观 / 形态 / 停靠边（可调项，全部落 UserDefaults）
enum DockEdge: String, CaseIterable, Identifiable {
    case top, left, right
    var id: String { rawValue }
    var name: String {
        switch self {
        case .top: return "顶部"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
}

enum IslandSkin: String, CaseIterable, Identifiable {
    case glass, obsidian, ceramic
    var id: String { rawValue }
    var name: String {
        switch self {
        case .glass: return "通透玻璃"
        case .obsidian: return "曜石深色"
        case .ceramic: return "陶瓷实心"
        }
    }
    /// 收起态与展开态的底色透明度（0~1）
    var compactTint: (dark: Double, light: Double) {
        switch self {
        case .glass: return (0.97, 0.99)
        case .obsidian: return (0.97, 0.985)
        case .ceramic: return (1.0, 1.0)
        }
    }
    var expandedTint: (dark: Double, light: Double) {
        switch self {
        case .glass: return (0.97, 0.99)
        case .obsidian: return (0.97, 0.985)
        case .ceramic: return (1.0, 1.0)
        }
    }
}

enum IslandForm: String, CaseIterable, Identifiable {
    case capsule, card
    var id: String { rawValue }
    var name: String {
        switch self {
        case .capsule: return "胶囊"
        case .card: return "卡片"
        }
    }
}

enum PanelSectionKey: String, CaseIterable, Identifiable {
    case overview, confirm, inboxes, channels, assets
    var id: String { rawValue }
    var name: String {
        switch self {
        case .overview: return "总览摘要"
        case .confirm: return "待你验收"
        case .inboxes: return "三个收件箱"
        case .channels: return "三层通道"
        case .assets: return "快捷资产"
        }
    }
    static let defaultOrder: [String] = allCases.map { $0.rawValue }
    static let defaults: [String: Bool] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, true) })
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
    @Published var fusedCount: Int = 0
    @Published var fusedSummary: String = ""
    @Published var lastFunnelEvent: String = "等待广播..."
    
    @Published var agyTasks: [TaskItem] = []
    @Published var almaTasks: [TaskItem] = []
    @Published var pingTasks: [TaskItem] = []
    
    @Published var agyDoneTasks: [TaskItem] = []
    @Published var almaDoneTasks: [TaskItem] = []
    @Published var pingDoneTasks: [TaskItem] = []
    
    @Published var funnelOnline: Bool = true
    @Published var nutstoreOnline: Bool = true
    @Published var tailscaleOnline: Bool = true

    /// 最近 15 秒仍有真实通讯的链路；无通讯时为空，视图不绘制任何脉冲
    @Published var activePulses: [AgentCommPulse] = []
    @Published var lastCommAt: Date? = nil

    @Published var currentMode: IslandMode = .compact
    @Published var selectedDrawerAgent: String? = nil {
        didSet { self.onDrawerChange?() }
    }
    @Published var showTopology: Bool = false {
        didSet { self.onDrawerChange?() }
    }
    @Published var showSettings: Bool = false {
        didSet { self.onDrawerChange?() }
    }
    @Published var expandedTaskId: String? = nil

    // 数据可信度：读取失败时显示「未知」，绝不假装有数据
    @Published var dataUnknown: Bool = false
    @Published var lastRefreshAt: Date? = nil

    // 外观 × 形态 × 尺寸 × 停靠边 × 模块开关/排序
    @Published var uiScale: Double = 1.0
    @Published var dockEdge: DockEdge = .top
    @Published var skin: IslandSkin = .glass
    @Published var islandForm: IslandForm = .capsule
    @Published var enabledSections: [String: Bool] = PanelSectionKey.defaults
    @Published var sectionOrder: [String] = PanelSectionKey.defaultOrder
    /// 拖拽排序时的临时来源（不参与渲染）
    var draggingSectionStore: String? = nil
    
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
    var onLayoutChange: (() -> Void)?
    
    private var lastKnownTotalPending: Int = -1
    private var lastKnownSubmitted: Int = -1

    /// 谁有几件没读：按未读数降序，完全来自真实收件箱
    var unreadLeaders: [(AgentIdentity, Int)] {
        AgentRoster.all
            .map { ($0, pendingCount(for: $0.key)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    func pendingCount(for key: String) -> Int {
        switch key {
        case "agy": return agyPending
        case "alma": return almaPending
        case "ping": return pingPending
        default: return 0
        }
    }

    var totalUnread: Int { agyPending + almaPending + pingPending }

    var compactHeadText: String {
        if dataUnknown { return "数据未知" }
        if fusedCount > 0 { return "M1 熔断 \(fusedCount) 项" }
        if totalSubmitted > 0 { return "\(totalSubmitted) 件待你验收" }
        if let lead = unreadLeaders.first { return "\(lead.0.short) \(lead.1) 件未读" }
        return "全员已读"
    }

    var compactTailText: String {
        if dataUnknown { return "· 收件箱读取失败" }
        if fusedCount > 0 { return "· 待露露终裁" }
        if totalSubmitted > 0 {
            let unread = unreadLeaders.map { "\($0.0.short) \($0.1)" }.joined(separator: " · ")
            if !unread.isEmpty { return "· 未读 \(unread)" }
            let names = Set(pendingConfirms.compactMap { AgentRoster.identity(for: $0.from.lowercased())?.short })
            let joined = names.isEmpty ? "Agent" : names.sorted().joined(separator: " / ")
            return "· 来自 \(joined)"
        }
        let others = unreadLeaders.dropFirst()
        if !others.isEmpty {
            return "· " + others.map { "\($0.0.short) \($0.1)" }.joined(separator: " · ")
        }
        return totalUnread > 0 ? "" : "· 0 待办"
    }

    var preferredCompactWidth: CGFloat {
        let len = CGFloat(compactHeadText.count) * 15.5 + CGFloat(compactTailText.count) * 11.5
        return max(272, min(520, 68 + len))
    }

    /// 展开态内容高度（视图与窗口共用同一套数值，避免裁切）
    var expandedContentHeight: CGFloat {
        let extra: CGFloat = expandedTaskId != nil ? 65 : 0
        if let ag = selectedDrawerAgent {
            let tCount = pendingCount(for: ag)
            let dCount: Int = {
                switch ag {
                case "agy": return agyDoneTasks.count
                case "alma": return almaDoneTasks.count
                case "ping": return pingDoneTasks.count
                default: return 0
                }
            }()
            return CGFloat(((tCount + dCount <= 4) ? 340 : 410) + extra)
        }
        // 内联链路：总览头部 + 迷你条 + 300pt 展开区（含三层通道原文案）
        if showTopology { return 360 + extra }
        if showSettings { return 560 + extra }

        // 头部实际行高比旧估值高 8pt；补足后内容不再溢出玻璃底边
        var h: CGFloat = 34
        if enabledSections[PanelSectionKey.overview.rawValue] ?? true { h += 16 }
        if enabledSections[PanelSectionKey.confirm.rawValue] ?? true {
            h += pendingConfirms.isEmpty ? 49 : 92
        }
        if enabledSections[PanelSectionKey.inboxes.rawValue] ?? true { h += 40 }
        if enabledSections[PanelSectionKey.channels.rawValue] ?? true { h += 44 }
        if enabledSections[PanelSectionKey.assets.rawValue] ?? true { h += 18 }
        let enabledSectionCount = PanelSectionKey.allCases.reduce(0) { partial, key in
            partial + ((enabledSections[key.rawValue] ?? true) ? 1 : 0)
        }
        let gaps = CGFloat(max(0, enabledSectionCount - 1)) * 16
        let verticalPadding: CGFloat = 10 + 10
        return max(120, h + gaps + verticalPadding) + extra
    }
    private var timer: Timer?
    private var breathTimer: Timer?
    private var commTimer: Timer?
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
    
    private let preferences: UserDefaults?
    let rootPath: String
    let handoffScript = "/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts/handoff.py"

    init(virtualTest: Bool = false) {
        if virtualTest {
            // 固定的进程内数据；不读取偏好、生产 handoff 或事件源，也不启动轮询。
            preferences = nil
            rootPath = ""
            if let raw = ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_THEME"],
               let mode = ThemeMode(rawValue: raw) {
                themeMode = mode
            }
            checkAppearance()
            return
        }
        preferences = .standard
        // 多根模式下与事件解析使用同一根目录，避免兜底扫描串到生产 handoffs。
        if let root = ProcessInfo.processInfo.environment["AGENT_ISLAND_MULTI_ROOT"], !root.isEmpty {
            rootPath = root.hasSuffix("/handoffs") ? root : root + "/handoffs"
        } else {
            rootPath = "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs"
        }
        if let savedTheme = preferences?.string(forKey: "agent_island_theme_mode"),
           let tm = ThemeMode(rawValue: savedTheme) {
            self.themeMode = tm
        }
        if let savedAccent = preferences?.string(forKey: "agent_island_accent_hex") {
            self.accentHex = savedAccent
        }
        if let savedScale = preferences?.object(forKey: "agent_island_ui_scale") as? Double {
            self.uiScale = min(1.4, max(0.8, savedScale))
        }
        if let savedDock = preferences?.string(forKey: "agent_island_dock_edge"),
           let edge = DockEdge(rawValue: savedDock) {
            self.dockEdge = edge
        }
        if let savedSkin = preferences?.string(forKey: "agent_island_skin"),
           let sk = IslandSkin(rawValue: savedSkin) {
            self.skin = sk
        }
        if let savedForm = preferences?.string(forKey: "agent_island_form"),
           let fm = IslandForm(rawValue: savedForm) {
            self.islandForm = fm
        }
        if let savedOrder = preferences?.stringArray(forKey: "agent_island_section_order") {
            let valid = savedOrder.filter { PanelSectionKey(rawValue: $0) != nil }
            let missing = PanelSectionKey.defaultOrder.filter { !valid.contains($0) }
            self.sectionOrder = valid + missing
        }
        if let savedSections = preferences?.dictionary(forKey: "agent_island_sections") as? [String: Bool] {
            var merged = PanelSectionKey.defaults
            for (k, v) in savedSections where merged[k] != nil { merged[k] = v }
            self.enabledSections = merged
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
            self.preferences?.set(mode.rawValue, forKey: "agent_island_theme_mode")
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
            self.preferences?.set(hex, forKey: "agent_island_accent_hex")
            self.objectWillChange.send()
        }
    }
    
    func setMode(_ mode: IslandMode) {
        DispatchQueue.main.async {
            if case .compact = mode { self.showSettings = false }
            self.currentMode = mode
            self.onModeChange?(mode)
            print("[AgentIsland] setMode -> \(mode)")
        }
    }

    func setUIScale(_ value: Double) {
        let clamped = min(1.4, max(0.8, (value * 20).rounded() / 20))
        DispatchQueue.main.async {
            self.uiScale = clamped
            self.preferences?.set(clamped, forKey: "agent_island_ui_scale")
            self.onLayoutChange?()
        }
    }

    func setDockEdge(_ edge: DockEdge) {
        DispatchQueue.main.async {
            self.dockEdge = edge
            self.preferences?.set(edge.rawValue, forKey: "agent_island_dock_edge")
            self.onLayoutChange?()
        }
    }

    func setSkin(_ value: IslandSkin) {
        DispatchQueue.main.async {
            self.skin = value
            self.preferences?.set(value.rawValue, forKey: "agent_island_skin")
        }
    }

    func setIslandForm(_ value: IslandForm) {
        DispatchQueue.main.async {
            self.islandForm = value
            self.preferences?.set(value.rawValue, forKey: "agent_island_form")
        }
    }

    /// 面板实际明暗：曜石深色皮肤无论系统模式如何，都使用深色表面与浅色文字
    var panelIsDark: Bool {
        isDarkMode || skin == .obsidian
    }

    func toggleSection(_ key: String) {
        DispatchQueue.main.async {
            guard PanelSectionKey(rawValue: key) != nil else { return }
            self.enabledSections[key] = !(self.enabledSections[key] ?? true)
            self.preferences?.set(self.enabledSections, forKey: "agent_island_sections")
            self.onLayoutChange?()
        }
    }

    func moveSection(_ key: String, before target: String) {
        guard key != target,
              let from = sectionOrder.firstIndex(of: key),
              let to = sectionOrder.firstIndex(of: target) else { return }
        var order = sectionOrder
        order.remove(at: from)
        let insertIndex = to > from ? to - 1 : to
        order.insert(key, at: insertIndex)
        sectionOrder = order
        preferences?.set(order, forKey: "agent_island_section_order")
    }

    func moveSection(_ key: String, by delta: Int) {
        guard let idx = sectionOrder.firstIndex(of: key) else { return }
        let dest = idx + delta
        guard dest >= 0 && dest < sectionOrder.count else { return }
        var order = sectionOrder
        order.swapAt(idx, dest)
        sectionOrder = order
        preferences?.set(order, forKey: "agent_island_section_order")
    }
    
    func startTimers() {
        guard preferences != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAppearance()
            self?.refreshAll()
        }
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pulse.toggle()
            }
        }
        refreshCommPulses()
        commTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshCommPulses()
        }
    }

    // MARK: - 事件驱动通讯脉冲（只认真实文件通讯，静默时不画线）

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let multiRoot = ProcessInfo.processInfo.environment["AGENT_ISLAND_MULTI_ROOT"]
        ?? "/Users/l/Nutstore Files/Obsidian_/multi-agent"
    private static let eventLog = ProcessInfo.processInfo.environment["AGENT_ISLAND_EVENT_LOG"]
        ?? "/Users/l/.local/funnel-sync/events.log"

    private func parseEventTime(_ raw: String) -> Date? {
        Self.isoFull.date(from: raw) ?? Self.isoPlain.date(from: raw)
    }

    /// 从 handoff front matter 取实名收发方；只接受 AGY / Alma / Ping 三家
    private func handoffEndpoints(at url: URL) -> (String, String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var from = "", to = ""
        for line in text.prefix(1600).split(separator: "\n") {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("from:") {
                from = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            } else if s.hasPrefix("to:") {
                to = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            }
            if !from.isEmpty && !to.isEmpty { break }
        }
        let f = from.lowercased(), t = to.lowercased()
        guard AgentRoster.identity(for: f) != nil, AgentRoster.identity(for: t) != nil, f != t else { return nil }
        return (f, t)
    }

    private func refreshCommPulses() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let cutoff = now.addingTimeInterval(-15)
            var hits: [(String, String, Date)] = []

            // 主源：Funnel 443 写入事件（只认 PUT，不认 HEARTBEAT）
            if let data = FileManager.default.contents(atPath: Self.eventLog),
               let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n").suffix(240) {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                          let d = obj as? [String: Any],
                          d["action"] as? String == "PUT",
                          let path = d["path"] as? String,
                          path.hasPrefix("handoffs/"),
                          let raw = d["time"] as? String,
                          let when = self.parseEventTime(raw),
                          when >= cutoff else { continue }
                    let url = URL(fileURLWithPath: Self.multiRoot).appendingPathComponent(path)
                    if let (from, to) = self.handoffEndpoints(at: url) {
                        hits.append((from, to, when))
                    }
                }
            }

            // 兜底：events.log 静默时，用 handoff 文件 mtime（15 秒窗口）
            if hits.isEmpty {
                let fm = FileManager.default
                for box in AgentRoster.all.map({ $0.key }) {
                    let dir = URL(fileURLWithPath: self.rootPath).appendingPathComponent(box)
                    guard let files = try? fm.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for url in files where ["md", "txt"].contains(url.pathExtension.lowercased()) {
                        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        guard mtime >= cutoff, let (from, to) = self.handoffEndpoints(at: url) else { continue }
                        hits.append((from, to, mtime))
                    }
                }
            }

            var grouped: [String: (from: String, to: String, count: Int, last: Date)] = [:]
            for (from, to, when) in hits {
                let key = from + "->" + to
                if var g = grouped[key] {
                    g.count += 1
                    g.last = max(g.last, when)
                    grouped[key] = g
                } else {
                    grouped[key] = (from, to, 1, when)
                }
            }
            let order = Dictionary(uniqueKeysWithValues: AgentRoster.all.enumerated().map { ($1.key, $0) })
            let pulses = grouped.values.map {
                AgentCommPulse(source: $0.from, target: $0.to, count: $0.count, lastAt: $0.last)
            }.sorted {
                let a = order[$0.source] ?? 99, b = order[$1.source] ?? 99
                if a != b { return a < b }
                return (order[$0.target] ?? 99) < (order[$1.target] ?? 99)
            }
            let lastAt = pulses.map { $0.lastAt }.max()

            DispatchQueue.main.async {
                self.activePulses = pulses
                self.lastCommAt = lastAt
            }
        }
    }
    
    func refreshAll() {
        guard preferences != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let snapshot = self.fetchInboxesJSON()
            let dataOK = snapshot != nil
            let data = snapshot ?? [:]
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
                self.funnelOnline = fOnline
                self.nutstoreOnline = nOnline
                self.tailscaleOnline = tOnline

                guard dataOK else {
                    // 读取失败：保留上一份真数据，但明确标记「未知」，不假装有数据
                    self.dataUnknown = true
                    return
                }
                self.dataUnknown = false
                self.lastRefreshAt = Date()

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
                
                if let telem = data["__telemetry__"]?.first {
                    self.tokenTotal = telem.file
                    self.tokenCacheRate = telem.title
                    self.tokenTopModel = telem.from
                }
                if let pl = data["__ping_loop__"]?.first {
                    self.fusedCount = Int(pl.file) ?? 0
                    self.lastFunnelEvent = pl.title.isEmpty ? "等待广播..." : pl.title
                    self.fusedSummary = pl.from
                }
                
                let currentTotal = pingArr.count + agyArr.count + almaArr.count
                let prevTotal = self.lastKnownTotalPending
                if prevTotal >= 0 && currentTotal > prevTotal {
                    let lead = self.unreadLeaders.first
                    self.triggerNotification(
                        title: "📩 \(currentTotal - prevTotal) 件新未读",
                        subtitle: lead.map { "\($0.0.title) 收件箱 \($0.1) 件未读 · 靠近自动展开" } ?? "靠近自动展开"
                    )
                }
                self.lastKnownTotalPending = currentTotal

                let prevSubmitted = self.lastKnownSubmitted
                if prevSubmitted >= 0 && confirms.count > prevSubmitted {
                    let from = confirms.first?.from ?? "Agent"
                    self.triggerNotification(
                        title: "🔔 \(confirms.count) 件待你验收",
                        subtitle: "\(from) 已递交成果 · 点击查看并验收"
                    )
                }
                self.lastKnownSubmitted = confirms.count

                // 收起态单行摘要随数据变化，窗口宽度需同步，避免文字溢出
                if case .compact = self.currentMode {
                    self.onLayoutChange?()
                }
            }
        }
    }
    
    func confirmTask(file: String, dispatcher: String) {
        guard preferences != nil else { return }
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
        guard preferences != nil else { return }
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
    
    func resolveFusedByLulu() {
        guard preferences != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = ["-c", """
import sys, json, os, re, subprocess
from pathlib import Path
sys.path.insert(0, '/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts')
import handoff

fuse_script = Path('/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/ping-loop/scripts/ping_loop_fuse.py')
proc = subprocess.run([sys.executable, str(fuse_script), '--json'], capture_output=True, text=True)
try:
    data = json.loads(proc.stdout)
    tasks = data.get('fused_tasks', [])
    for t in tasks:
        base = t.get('base')
        if base:
            acked = handoff.load_ack('agy')
            acked[f"{base}.md"] = "confirmed: 露露最高终裁一键结案"
            handoff.save_ack('agy', acked)
            p_acked = handoff.load_ack('ping')
            p_acked[f"{base}.md"] = "confirmed: 露露最高终裁一键结案"
            handoff.save_ack('ping', p_acked)
except Exception:
    pass
"""]
            try? p.run()
            p.waitUntilExit()
            
            self.refreshAll()
            DispatchQueue.main.async {
                withAnimation(.spring()) {
                    self.fusedCount = 0
                    self.reconcileFeedback = "⚖️ 露露终裁已生效：熔断归零 恢复薄荷绿"
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
    
    private func fetchInboxesJSON() -> [String: [TaskItem]]? {
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
        if handoff.REPLY_RE.search(p.name) or p.name.startswith('cancel-') or '-accept' in p.name or '-confirm' in p.name:
            base = handoff.re.sub(r'-(reply\\d*|accept\\d*|confirm\\d*)\\.md$', '.md', p.name, flags=handoff.re.IGNORECASE)
            base_clean = re.sub(r'-reply\\d*$', '', base.replace('.md', '')) + '.md'
            global_replied.add(base)
            global_replied.add(base_clean)
            global_replied.add(p.stem)
            global_replied.add(p.name)
            try:
                meta, _ = handoff.parse_frontmatter(p.read_text(encoding='utf-8', errors='replace'))
                rt = str(meta.get('reply_to', '')).strip()
                if rt and rt != 'none':
                    global_replied.add(Path(rt).name)
                    global_replied.add(Path(rt).stem)
                rel = meta.get('related', [])
                if isinstance(rel, list):
                    for item in rel:
                        global_replied.add(Path(str(item)).name)
                        global_replied.add(Path(str(item)).stem)
            except Exception:
                pass

# Phase 2: Per-box pending extraction (Trace ID 强归组模型，露露定版：一个单子一个状态)
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
    
    # 彻底过滤中继传令票与取消票，按 trace_id 强聚合（结合最新通报过滤状态与汇报件）
    trace_groups = {}
    for p in all_md:
        if p.name.startswith('pingloop-route-') or p.name.startswith('cancel-') or re.search(r"(-status\\.md$|-report\\.md$|state/|loop-probe)", p.name, re.I):
            continue
        try:
            txt = p.read_text(encoding='utf-8', errors='replace')
            meta, body = handoff.parse_frontmatter(txt)
            tid = str(meta.get('trace_id', '')).strip()
            b_name = p.stem.split('-reply')[0].split('-accept')[0].split('-confirm')[0]
            if not tid or tid == 'none' or tid == '-':
                tid = f"base-{b_name}"
            trace_groups.setdefault(tid, []).append((p, meta, body))
        except Exception:
            pass

    items = []
    for tid, files in trace_groups.items():
        base_names = {p.stem.split('-reply')[0].split('-accept')[0].split('-confirm')[0] for p, _, _ in files}
        is_acked = any(k in [p.name for p, _, _ in files] or k.replace('.md', '') in base_names for k in acked_names)
        has_confirm = any('-confirm' in p.name for p, _, _ in files) or any(b in global_replied for b in base_names)
        has_closed = any(any(c in str(meta.get('status', '')) for c in ('已完成', '作废', '已关闭', '已核销', '参考', '已结案')) for _, meta, _ in files)

        if is_acked or has_confirm or has_closed:
            continue

        files.sort(key=lambda x: x[0].stat().st_mtime, reverse=True)
        latest_p, latest_meta, latest_body = files[0]
        
        # 寻找该组的原始派单方向（排除回执类文件 -accept/-reply/-audit）
        orig_dispatch = None
        for p_item, meta_item, body_item in files:
            if not any(p_item.name.endswith(s) for s in ('-accept.md', '-reply.md', '-audit.md')):
                orig_dispatch = (p_item, meta_item, body_item)
                break
        if orig_dispatch is None:
            orig_dispatch = files[-1]
        orig_frm = str(orig_dispatch[1].get('from', '')).strip().lower()
        orig_to = str(orig_dispatch[1].get('to', '')).strip().lower()
        # 严格责任边界：收件人不是本箱的（如抄送件、外发件），严禁算作本箱待办！
        if orig_to and orig_to != box:
            continue
        # 只有原单自身就是外发单且非发给当前信箱时才过滤；收到派单并签署 -accept 属于正常履约中，严禁过滤！
        if orig_frm == box and orig_to != box:
            continue

        cur_status = str(latest_meta.get('status', '待办'))
        if cur_status == '履约中' or any('-accept' in p.name for p, _, _ in files):
            stage = 'accepted'
            status_text = '履约中'
            total_accepted += 1
            eta = str(latest_meta.get('eta', '履约推进中'))
        elif cur_status == '待确认' or any(handoff.REPLY_RE.search(p.name) for p, _, _ in files):
            # 关键分流：待确认属于发起方闭环待验收（Phase 3），严禁混入各 agent 的真待办抽屉！
            continue
        else:
            stage = 'dispatched'
            status_text = '待接单'
            total_dispatched += 1
            eta = ''

        items.append({
            'file': latest_p.name,
            'from': str(latest_meta.get('from', '未知')),
            'to': str(latest_meta.get('to', box)),
            'date': str(latest_meta.get('date', '-')),
            'title': handoff.first_heading(latest_body) or latest_p.stem,
            'mtime': latest_p.stat().st_mtime,
            'stage': stage,
            'statusText': status_text,
            'artifacts': str(latest_meta.get('artifacts', '')),
            'eta': eta,
            'highlights': handoff.extract_highlights(latest_p.read_text(encoding='utf-8', errors='replace'))
        })

    items.sort(key=lambda x: x['mtime'], reverse=True)
    res[box] = items

# Phase 3: Pending Confirmations (发起方闭环核验中)
raw_confirms = []
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    all_b_files = list(b_dir.iterdir())
    for p in all_b_files:
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

            # 凡同目录存在对应 -confirm 结案回执，或原单已结案，严禁混入待验收！
            has_confirm_file = any((b_stem in f.name and '-confirm' in f.name) for f in all_b_files)
            if has_confirm_file:
                continue
            orig_p = b_dir / f'{b_stem}.md'
            if orig_p.is_file():
                o_txt = orig_p.read_text(encoding='utf-8', errors='replace')
                o_meta, _ = handoff.parse_frontmatter(o_txt)
                if any(c in str(o_meta.get('status', '')) for c in ('已完成', '已结案', '已确认', '已核销', '作废')):
                    continue

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

pl_fused = 0
pl_event = 'events.log 实时待命'
pl_summary = ''
try:
    sys.path.insert(0, '/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/ping-loop/scripts')
    import ping_loop_fuse
    f_res = ping_loop_fuse.scan_fuse()
    pl_fused = int(f_res.get('fused_count', 0))
    pl_event = str(f_res.get('last_event', 'events.log 实时待命'))
    if f_res.get('fused_tasks'):
        top_f = f_res['fused_tasks'][0]
        pl_summary = f"{top_f['base']} ({top_f['rounds']}轮)"
except Exception:
    pass

res['__ping_loop__'] = [{'file': str(pl_fused), 'title': pl_event, 'from': pl_summary, 'to': 'self', 'date': '-', 'mtime': 0}]

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
        return nil
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
                // 仅玻璃皮肤承接实时壁纸折射；陶瓷/曜石走窗口内材质以压低透射。
                let usesLiveBackdrop = monitor.skin == .glass
                let forceFallback = !usesLiveBackdrop || ProcessInfo.processInfo.environment["AGENT_ISLAND_GLASS"] == "0"
                AppleGlassBackground(
                    material: usesLiveBackdrop
                        ? (monitor.panelIsDark ? .hudWindow : .popover)
                        : .windowBackground,
                    blendingMode: usesLiveBackdrop ? .behindWindow : .withinWindow,
                    glassTint: glassTintNSColor,
                    // `.regular` 在当前参数下可同时满足透射与 σ≥10 的模糊门槛。
                    // 展开态高透：改用系统 `.clear` 变体，仍由系统绘制折射/高光，不做自绘 shader。
                    glassStyle: (monitor.skin == .glass && monitor.currentMode == .expanded && !forceFallback) ? .clear : .regular,
                    cornerRadius: cornerRadius,
                    forceFallback: forceFallback
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                // Layer 2: Solid Obsidian & Ceramic Glass Tint (深浅色双模原生适配，防HDR溢色强化)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(panelFill)

                // Layer 2.5: 0.5px inset stroke，做出玻璃砖内壁切面
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(monitor.panelIsDark ? 0.14 : 0.30),
                        lineWidth: 0.5
                    )

                // Layer 3: Razor Specular Border (深浅色自适应金属高反差切面)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: monitor.panelIsDark ? Color.white.opacity(0.65) : Color.white.opacity(0.98), location: 0.0),
                                .init(color: monitor.panelIsDark ? Color.white.opacity(0.20) : Color.black.opacity(0.08), location: 0.45),
                                .init(color: monitor.panelIsDark ? Color.white.opacity(0.10) : Color.black.opacity(0.14), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
                
                // Content View（GLASS_PROBE 仅用于像素验收：留空面板，只量玻璃本身）
                if ProcessInfo.processInfo.environment["AGENT_ISLAND_GLASS_PROBE"] != "1" {
                    contentForCurrentMode
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 玻璃边缘压在裁剪之后：顶部 1px 镜面高光 + 底部 1px 深色压边，不被内容盖住
            .overlay {
                glassMirrorEdge
            }
            .scaleEffect(monitor.uiScale, anchor: .top)
            .frame(width: contentWidth * monitor.uiScale, height: contentHeight * monitor.uiScale, alignment: .top)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: monitor.currentMode)
            .animation(.easeInOut(duration: 0.25), value: monitor.panelIsDark)
            .animation(.easeInOut(duration: 0.22), value: monitor.skin)
            .animation(.easeInOut(duration: 0.22), value: monitor.uiScale)
            // Outer two-level shadow：大范围柔光 + 1.5px 贴边
            .shadow(
                color: Color.black.opacity(monitor.panelIsDark ? 0.45 : 0.16),
                radius: monitor.panelIsDark ? 18 : 12,
                x: 0,
                y: monitor.panelIsDark ? 6 : 4
            )
            .shadow(
                color: Color.black.opacity(monitor.panelIsDark ? 0.20 : 0.05),
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

    /// 顶部 1px 镜面高光（深色 0.65 / 浅色 0.98）+ 底部 1px 深色压边
    var glassMirrorEdge: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(monitor.panelIsDark ? 0.65 : 0.98), location: 0.0),
                        .init(color: Color.white.opacity(monitor.panelIsDark ? 0.26 : 0.52), location: 0.55),
                        .init(color: Color.white.opacity(monitor.panelIsDark ? 0.06 : 0.16), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        Color.black.opacity(monitor.panelIsDark ? 0.55 : 0.18),
                        Color.black.opacity(monitor.panelIsDark ? 0.20 : 0.04)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .allowsHitTesting(false)
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
    
    // MARK: - Compact Mode（单行摘要：最要紧的一件事，谁有几件没读）
    var compactView: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(compactAccent)
                    .frame(width: 19, height: 19)
                    .shadow(color: compactAccent.opacity(compactIsAlert ? 0.55 : 0.30), radius: compactIsAlert ? 4.5 : 2)
                    .scaleEffect(compactIsAlert && monitor.pulse ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 1.1), value: monitor.pulse)

                Image(systemName: compactGlyphName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(compactHead)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(compactTail)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
    }

    var compactAccent: Color {
        if monitor.dataUnknown { return Color(hex: "F59E0B") }
        if monitor.fusedCount > 0 { return Color(hex: "EF4444") }
        if monitor.totalSubmitted > 0, let from = monitor.pendingConfirms.first?.from,
           let agent = AgentRoster.identity(for: from.lowercased()) {
            return agent.color
        }
        if let lead = monitor.unreadLeaders.first { return lead.0.color }
        return Color(hex: "10B981")
    }

    var compactIsAlert: Bool {
        monitor.dataUnknown || monitor.fusedCount > 0 || monitor.totalSubmitted > 0 || monitor.totalUnread > 0
    }

    var compactGlyphName: String {
        if monitor.dataUnknown { return "questionmark" }
        if monitor.fusedCount > 0 { return "exclamationmark" }
        if monitor.totalSubmitted > 0 { return "bell.fill" }
        if monitor.totalUnread > 0 { return "tray.fill" }
        return "checkmark"
    }

    var compactHead: String { monitor.compactHeadText }
    var compactTail: String { monitor.compactTailText }
    
    func notificationView(title: String, subtitle: String) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF9500"))
                    .frame(width: 18, height: 18)
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 11, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }
    
    // MARK: - AgentIsland & Multi-Agent 架构控制中心 (苹果原厂大字阶与四层空间调度)
    var controlCenterExpandedView: some View {
        VStack(spacing: 16) {
            // Layer 1: Header Row (14pt 大标题 + 链路图切换 + 关闭/Esc)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .bold))
                }
                Text("总览")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)

                if monitor.dataUnknown {
                    Text("数据未知")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(textAmber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.16)))
                }

                // 顶部只剩「总览 / 待办总览」两个入口；链路架构改为总览内联区块
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.showTopology = false
                        }
                    }) {
                        Text("待办总览")
                            .font(.system(size: 13, weight: !monitor.showTopology ? .bold : .semibold, design: .rounded))
                            .foregroundColor(!monitor.showTopology ? accentOnColor : secondaryTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(!monitor.showTopology ? accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("回到总览，收起内联链路")
                }
                .padding(2)
                .background(
                    Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                )
                
                Spacer()
                
                // Status hint / reconcile feedback
                if let fb = monitor.reconcileFeedback {
                    Text(fb)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(totalPending == 0 ? Color(hex: "059669") : Color(hex: "D97706"))
                        .transition(.scale)
                } else {
                    Text("Esc 收起")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        monitor.showSettings.toggle()
                    }
                }) {
                    Image(systemName: monitor.showSettings ? "gearshape.fill" : "gearshape")
                        .foregroundColor(monitor.showSettings ? accentColor : secondaryTextColor)
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                .help("外观、尺寸、停靠边与模块开关")

                Button(action: {
                    monitor.setMode(.compact)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(secondaryTextColor)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)

            // Layer 2: 黄金展示区 (工单流 vs 架构链路图)
            if monitor.fusedCount > 0 {
                fusedDecisionBannerView
                    .padding(.horizontal, 14)
            }
            
            if monitor.showTopology {
                // 链路架构内联在总览里：迷你条常驻，点一下就地展开，不占独立 tab
                VStack(spacing: 10) {
                    miniLinkStrip
                    architectureTopologyView
                }
                .padding(.horizontal, 14)
            } else if monitor.showSettings {
                settingsView
            } else {
                // 模块可单独开关、可拖动排序：先总览，再验收，再三箱，再通道，最后资产
                ForEach(monitor.sectionOrder, id: \.self) { key in
                    if monitor.enabledSections[key] ?? true {
                        panelSectionView(key)
                    }
                }
            }

        }
        .padding(.bottom, 10)
    }

    // MARK: - Panel Sections (可单独开关 · 可拖动排序)
    @ViewBuilder
    func panelSectionView(_ key: String) -> some View {
        switch PanelSectionKey(rawValue: key) {
        case .overview:
            overviewSummaryStrip
                .padding(.horizontal, 14)
        case .confirm:
            if !monitor.pendingConfirms.isEmpty {
                liveDispatchHeroCardView
                    .padding(.horizontal, 14)
            } else {
                autoloopReadyHeroCardView
                    .padding(.horizontal, 14)
            }
        case .inboxes:
            inboxCardsRow
                .padding(.horizontal, 14)
        case .channels:
            miniLinkStrip
                .padding(.horizontal, 14)
                .padding(.top, 2)
        case .assets:
            assetsRow
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 2)
        case .none:
            EmptyView()
        }
    }

    /// 首屏总览：三箱未读 + 待验收，一眼看完，不用翻页
    var overviewSummaryStrip: some View {
        HStack(spacing: 6) {
            if monitor.dataUnknown {
                Text("⚪️ 未知")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.14)))
            } else {
                ForEach(AgentRoster.all) { agent in
                    let count = monitor.pendingCount(for: agent.key)
                    HStack(spacing: 4) {
                        Circle().fill(agent.color).frame(width: 6, height: 6)
                        Text(agent.short)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                        Text(count == 0 ? "已读" : "\(count) 未读")
                            .font(.system(size: 11, weight: count == 0 ? .semibold : .bold, design: .rounded))
                            .foregroundColor(count == 0 ? secondaryTextColor : agent.color)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(agent.color.opacity(count == 0 ? 0.06 : 0.12)))
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textPurple)
                Text(monitor.totalSubmitted == 0 ? "无待验收" : "\(monitor.totalSubmitted) 待验收")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(monitor.totalSubmitted == 0 ? secondaryTextColor : Color(hex: "8B5CF6"))
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color(hex: "8B5CF6").opacity(monitor.totalSubmitted == 0 ? 0.05 : 0.13)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
        .background(squircleCardBackground)
    }

    /// 三个固定色收件箱卡（颜色在任何页面都不变）
    var inboxCardsRow: some View {
        HStack(spacing: 10) {
            ForEach(AgentRoster.all) { agent in
                let count = monitor.pendingCount(for: agent.key)
                agentBalanceCard(
                    icon: agent.symbol,
                    iconBg: agent.color,
                    textTint: agentTextColor(agent),
                    title: agent.title,
                    subtitle: monitor.dataUnknown
                        ? "读取失败 · 未知"
                        : (count == 0 ? "收件箱已读" : "收件箱 \(count) 件未读"),
                    hasPending: !monitor.dataUnknown && count > 0
                ) {
                    monitor.setDrawerAgent(agent.key)
                }
            }
        }
    }

    /// 底部三层通道：底座(网络) → 主通道(Funnel) → 冷备(坚果云)，不再并排混淆
    // MARK: - 40–44pt 迷你链路条（替换 93pt 通道三层区块）
    // 三层语义靠纵向位置 + 色阶区分：Tailscale 基座下沉、Funnel 主通道居中抬升、坚果云冷备上浮。
    // 原文案不丢：hover 出完整说明；点击展开后链路图底部再给出三层原文。
    var miniLinkStrip: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                monitor.showTopology.toggle()
            }
        }) {
            VStack(spacing: 0) {
                // ③ 主体改成 AGY/Alma/Ping 三节点 + 1.5pt 主通道线；
                //    Tailscale/Funnel/坚果云降级为两端小标签，不再占主体。
                HStack(spacing: 7) {
                    miniStripChannelTag(
                        text: "Tailscale",
                        icon: "network",
                        ok: monitor.tailscaleOnline,
                        tint: monitor.panelIsDark ? Color(hex: "A8B3C2") : Color(hex: "475569")
                    )

                    Spacer(minLength: 4)

                    ZStack {
                        Capsule()
                            .fill(monitor.panelIsDark ? Color(hex: "9FCBFF") : Color(hex: "0A4FB6"))
                            .frame(height: 1.5)
                            .padding(.horizontal, 14)

                        HStack(spacing: 30) {
                            miniStripAgentNode(agent: AgentRoster.agy)
                            miniStripAgentNode(agent: AgentRoster.alma)
                            miniStripAgentNode(agent: AgentRoster.ping)
                        }

                        HStack {
                            Spacer()
                            Image(systemName: monitor.showTopology ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(monitor.panelIsDark ? Color(hex: "D7E6F9") : Color(hex: "1F3A5F"))
                        }
                    }
                    .frame(width: 166, height: 18)

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        miniStripChannelTag(
                            text: "Funnel 443",
                            icon: "bolt.horizontal.fill",
                            ok: monitor.funnelOnline,
                            tint: monitor.panelIsDark ? Color(hex: "9FDBFF") : Color(hex: "075985")
                        )
                        miniStripChannelTag(
                            text: "坚果云",
                            icon: "externaldrive.fill",
                            ok: monitor.nutstoreOnline,
                            tint: monitor.panelIsDark ? Color(hex: "C4CCD8") : Color(hex: "4B5563")
                        )
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 27)

                // V5 + ⑨：保留最近通讯行与单光点，并补「最后通讯 N 秒前」。
                HStack(spacing: 5) {
                    Circle()
                        .fill(monitor.activePulses.isEmpty ? textGray : textGreen)
                        .frame(width: 5, height: 5)
                    Text("\(miniRecentCommText) · \(miniLastCommAgoText)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(monitor.activePulses.isEmpty ? textGray : textGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 15)
            }
            .frame(height: 44)
            .background(squircleCardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .help("中轴节点：AGY/Alma/Ping（18px）\n主通道：1.5pt\n侧标：Tailscale / Funnel 443 / 坚果云\n点击展开/收起横向链路")
    }

    var miniRecentCommText: String {
        guard let p = monitor.activePulses.first else { return "最近通讯：无通讯" }
        let s = AgentRoster.identity(for: p.source)?.short ?? p.source.uppercased()
        let t = AgentRoster.identity(for: p.target)?.short ?? p.target.uppercased()
        let extra = monitor.activePulses.count > 1 ? " · +\(monitor.activePulses.count - 1) 条" : ""
        return "最近通讯：\(s) → \(t) ×\(p.count)\(extra)"
    }

    var miniLastCommAgoText: String {
        guard let lastAt = monitor.lastCommAt else { return "最后通讯：无通讯" }
        let seconds = max(0, Int(Date().timeIntervalSince(lastAt)))
        return "最后通讯 \(seconds) 秒前"
    }

    func miniStripChannelTag(text: String, icon: String, ok: Bool, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
            Circle()
                .fill(ok ? Color(hex: "10B981") : Color(hex: "EF4444"))
                .frame(width: 4, height: 4)
        }
        .foregroundColor(tint)
    }

    func miniStripAgentNode(agent: AgentIdentity) -> some View {
        Circle()
            .fill(agent.color.opacity(0.24))
            .frame(width: 18, height: 18)
            .overlay(
                Circle().stroke(agent.color.opacity(0.96), lineWidth: 1)
            )
            .overlay(
                Circle().fill(Color.white.opacity(monitor.panelIsDark ? 0.88 : 0.72))
                    .frame(width: 3.5, height: 3.5)
            )
            .shadow(color: agent.color.opacity(0.30), radius: 1.5)
            .help(agent.short)
    }

    var channelHierarchyView: some View {
        VStack(spacing: 5) {
            channelTierRow(
                tier: "底座",
                name: "Tailscale",
                detail: "私网底座 · SSH 可达",
                icon: "network",
                ok: monitor.tailscaleOnline,
                tint: monitor.panelIsDark ? Color(hex: "94A3B8") : Color(hex: "475569")
            ) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app"))
            }
            Divider().opacity(0.12).padding(.leading, 74)
            channelTierRow(
                tier: "主通道",
                name: "Funnel 443",
                detail: "HTTPS 专用通道 · 主传输路径",
                icon: "bolt.fill",
                ok: monitor.funnelOnline,
                tint: monitor.panelIsDark ? Color(hex: "7DD3FC") : Color(hex: "0369A1")
            ) {
                if monitor.funnelOnline, let u = URL(string: "https://lmac-mini.tail463092.ts.net/v1/health") {
                    NSWorkspace.shared.open(u)
                }
            }
            Divider().opacity(0.12).padding(.leading, 74)
            channelTierRow(
                tier: "冷备",
                name: "坚果云",
                detail: "只读冷备 · 灾难恢复底仓",
                icon: "externaldrive.fill",
                ok: monitor.nutstoreOnline,
                tint: Color(hex: "9CA3AF"),
                muted: true
            ) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files"))
            }
        }
        .background(squircleCardBackground)
    }

    func channelTierRow(tier: String, name: String, detail: String, icon: String, ok: Bool, tint: Color, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(tier)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(muted ? secondaryTextColor : tint)
                    .frame(width: 40, alignment: .leading)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(muted ? secondaryTextColor : tint)
                    .frame(width: 14)
                Text(name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(muted ? secondaryTextColor : primaryTextColor)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Circle().fill(ok ? Color(hex: "10B981") : Color(hex: "EF4444")).frame(width: 5, height: 5)
                    Text(ok ? "在线" : "离线")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ok ? Color(hex: "059669") : Color(hex: "DC2626"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 0.5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 快捷资产入口（保留原入口，独立成可关闭模块）
    var assetsRow: some View {
        HStack(spacing: 10) {
            assetButton(icon: "photo.on.rectangle", label: "全景图") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces/zi-yan-mcp-quan-jing-tu.html"))
            }
            assetButton(icon: "folder.fill", label: "Spaces") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"))
            }
            assetButton(icon: "bubble.left.and.bubble.right.fill", label: "交流.md") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/交流.md"))
            }
            Spacer(minLength: 0)
            Button(action: { monitor.refreshAll() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { monitor.setMode(.compact) }) {
                Text("收起")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(assetsRowBackground)
    }

    // MARK: - 设置：皮肤 × 形态 × 尺寸 × 停靠边 × 模块开关/排序
    var settingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accentTextColor)
                Text("外观与面板")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                Spacer()
                Text(monitor.dataUnknown ? "数据未知" : "数据正常")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(monitor.dataUnknown ? Color(hex: "B45309") : Color(hex: "059669"))
                Button(action: { withAnimation { monitor.showSettings = false } }) {
                    Text("完成")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(accentTextColor)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(accentColor.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    settingsRow(title: "皮肤") {
                        HStack(spacing: 4) {
                            ForEach(IslandSkin.allCases) { sk in
                                settingsChip(sk.name, selected: monitor.skin == sk) { monitor.setSkin(sk) }
                            }
                        }
                    }
                    settingsRow(title: "形态") {
                        HStack(spacing: 4) {
                            ForEach(IslandForm.allCases) { fm in
                                settingsChip(fm.name, selected: monitor.islandForm == fm) { monitor.setIslandForm(fm) }
                            }
                        }
                    }
                    settingsRow(title: "尺寸") {
                        HStack(spacing: 8) {
                            Slider(value: Binding(
                                get: { monitor.uiScale },
                                set: { monitor.setUIScale($0) }
                            ), in: 0.8...1.4, step: 0.05)
                            .frame(width: 150)
                            Text("\(Int(monitor.uiScale * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    settingsRow(title: "停靠边") {
                        HStack(spacing: 4) {
                            ForEach(DockEdge.allCases) { edge in
                                settingsChip(edge.name, selected: monitor.dockEdge == edge) { monitor.setDockEdge(edge) }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("模块 · 开关与排序（拖动行可换序）")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(secondaryTextColor)
                        ForEach(monitor.sectionOrder, id: \.self) { key in
                            sectionSettingsRow(key)
                                .onDrag {
                                    monitor.draggingSectionStore = key
                                    return NSItemProvider(object: key as NSString)
                                }
                                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                                    if let drag = monitor.draggingSectionStore {
                                        monitor.moveSection(drag, before: key)
                                        monitor.draggingSectionStore = nil
                                    }
                                    return true
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(squircleCardBackground)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    func settingsRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(secondaryTextColor)
                .frame(width: 44, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(squircleCardBackground)
    }

    func settingsChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .rounded))
                .foregroundColor(selected ? accentOnColor : secondaryTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(selected ? accentColor : (monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    func sectionSettingsRow(_ key: String) -> some View {
        let section = PanelSectionKey(rawValue: key)
        let enabled = monitor.enabledSections[key] ?? true
        return HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(secondaryTextColor)
            Button(action: { monitor.toggleSection(key) }) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(enabled ? accentColor : secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            Text(section?.name ?? key)
                .font(.system(size: 13, weight: enabled ? .bold : .semibold, design: .rounded))
                .foregroundColor(enabled ? primaryTextColor : secondaryTextColor)
            Spacer(minLength: 0)
            Button(action: { monitor.moveSection(key, by: -1) }) {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(secondaryTextColor)
            Button(action: { monitor.moveSection(key, by: 1) }) {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(monitor.panelIsDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)))
    }

    func assetButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(secondaryTextColor)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - M1 熔断露露专属决策卡（批奏折专区：有熔断时最高优先级置顶）
    var fusedDecisionBannerView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(textRed)
                    .font(.system(size: 13, weight: .bold))
                Text("M1 轮次硬熔断停机保护（连续超 3 轮未收敛）")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textRed)
                Spacer()
                Text("待露露终裁")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(textAmber)
            }
            
            HStack(spacing: 10) {
                Text("任务触发 exit 3 停机保护，已自动拦截下一轮派单，杜绝空烧 Token。")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(2)
                Spacer()
                
                Button(action: {
                    monitor.resolveFusedByLulu()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("露露终裁 · 一键结案")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color(hex: "EF4444"))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "EF4444").opacity(monitor.panelIsDark ? 0.16 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "EF4444").opacity(0.35), lineWidth: 0.9)
                )
        )
    }
    
    // 横向多 Agent 拓扑：AGY 左 · Alma 中 · Ping 右；Funnel 443 横贯中部。
    // 脉冲只来自 events.log / handoff mtime 的真实通讯；静默时零活动连线、零脉冲、零高亮。
    var architectureTopologyView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("横向链路 · 事件驱动脉冲")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Text("AGY 左 · Alma 中 · Ping 右")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                Spacer()
                // 坚果云：右上角小节点，只作冷备，不参与通讯判定
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("坚果云 · 冷备")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Circle()
                        .fill(monitor.nutstoreOnline ? Color(hex: "10B981") : Color(hex: "EF4444"))
                        .frame(width: 5, height: 5)
                }
                .foregroundColor(textGray)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "9CA3AF").opacity(0.14)))
            }
            .padding(.horizontal, 12)

            GeometryReader { geo in
                let width = geo.size.width
                let railY: CGFloat = 34
                ZStack {
                    // 空闲态不画任何线段：没有通讯就没有连线、脉冲和光点。
                    // 只有 activePulses 非空时才挂载 pulseLayer（实线 + 箭头 + 光点）。

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Funnel 443 · 主通道")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(monitor.activePulses.isEmpty ? textGray : textGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(monitor.activePulses.isEmpty
                        ? Color(hex: "9CA3AF").opacity(0.14)
                        : Color(hex: "059669").opacity(0.14)))
                    .position(x: width / 2, y: railY - 18)

                    ForEach(Array(AgentRoster.all.enumerated()), id: \.element.id) { idx, agent in
                        topologyNode(
                            agent: agent,
                            isActive: monitor.activePulses.contains { $0.source == agent.key || $0.target == agent.key }
                        )
                        .position(x: width * [0.16, 0.5, 0.84][idx], y: railY + 20)
                    }

                    if !monitor.activePulses.isEmpty {
                        topologyPulseLayer(width: width, railY: railY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 108)

            // Tailscale：底部基座横条
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(textBlue)
                Text("Tailscale 私网 · 基座")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                Text("跨机底座，不承载业务脉冲")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                Spacer()
                Circle()
                    .fill(monitor.tailscaleOnline ? Color(hex: "10B981") : Color(hex: "EF4444"))
                    .frame(width: 6, height: 6)
                Text(monitor.tailscaleOnline ? "在线" : "离线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(monitor.tailscaleOnline ? textGreen : textRed)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(squircleCardBackground)

            // 诚实状态条：没有通讯就明说静默，绝不画假脉冲
            HStack(spacing: 6) {
                Circle()
                    .fill(monitor.activePulses.isEmpty ? textGray : Color(hex: "10B981"))
                    .frame(width: 5, height: 5)
                if monitor.activePulses.isEmpty {
                    Text("最近 15 秒无通讯 · 脉冲静默")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                } else {
                    Text("最近 15 秒 \(monitor.activePulses.reduce(0) { $0 + $1.count }) 次通讯")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(textGreen)
                    ForEach(Array(monitor.activePulses.prefix(3))) { pulse in
                        Text("\(AgentRoster.identity(for: pulse.source)?.short ?? pulse.source) → \(AgentRoster.identity(for: pulse.target)?.short ?? pulse.target) ×\(pulse.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)

            // D3：迷你条压缩后，原文案不丢——展开态在这里给出完整三层说明
            VStack(alignment: .leading, spacing: 2) {
                channelCopyRow(tier: "底座", name: "Tailscale", detail: "私网底座 · SSH 可达")
                channelCopyRow(tier: "主通道", name: "Funnel 443", detail: "HTTPS 专用通道 · 主传输路径")
                channelCopyRow(tier: "冷备", name: "坚果云", detail: "只读冷备 · 灾难恢复底仓")
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 14)
    }

    func channelCopyRow(tier: String, name: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Text(tier)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(textGray)
                .frame(width: 40, alignment: .leading)
            Text(name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(primaryTextColor)
            Text("· \(detail)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(secondaryTextColor)
            Spacer(minLength: 0)
        }
    }

    func topologyNode(agent: AgentIdentity, isActive: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(agent.color.opacity(isActive ? 0.26 : 0.13))
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(isActive ? agent.color.opacity(0.95) : idleRingColor(for: agent),
                            lineWidth: isActive ? 2 : 1)
                    .frame(width: 40, height: 40)
                    .shadow(color: agent.color.opacity(isActive ? 0.55 : 0), radius: 5)
                Image(systemName: agent.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(agent.color)
            }
            Text(agent.short)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(primaryTextColor)
            Text("\(monitor.pendingCount(for: agent.key)) 待办")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(secondaryTextColor)
        }
        .frame(width: 100, height: 82, alignment: .top)
    }

    /// V4：空闲节点环要求四组（浅/深玻璃 + 浅/深陶瓷）全部 ≥2.2:1。
    /// 仅改色值：按明暗 + 皮肤分档，特别补强浅玻璃橙环。
    func idleRingColor(for agent: AgentIdentity) -> Color {
        if monitor.panelIsDark {
            switch agent.key {
            case "agy": return Color(hex: "9FD0FF").opacity(0.96)
            case "alma": return Color(hex: "FFD7A1").opacity(0.96)
            case "ping": return Color(hex: "E2C6FF").opacity(0.96)
            default: return Color.white.opacity(0.92)
            }
        }

        switch monitor.skin {
        case .glass:
            switch agent.key {
            case "agy": return Color(hex: "0A4FB6").opacity(0.90)
            case "alma": return Color(hex: "9A4300").opacity(0.96)
            case "ping": return Color(hex: "5B1FB5").opacity(0.90)
            default: return Color(hex: "334155").opacity(0.88)
            }
        case .ceramic:
            switch agent.key {
            case "agy": return Color(hex: "0A4FB6").opacity(0.90)
            case "alma": return Color(hex: "9A4300").opacity(0.90)
            case "ping": return Color(hex: "5B1FB5").opacity(0.90)
            default: return Color(hex: "334155").opacity(0.88)
            }
        case .obsidian:
            switch agent.key {
            case "agy": return Color(hex: "9FD0FF").opacity(0.94)
            case "alma": return Color(hex: "FFD7A1").opacity(0.94)
            case "ping": return Color(hex: "E2C6FF").opacity(0.94)
            default: return Color.white.opacity(0.90)
            }
        }
    }

    /// V2：活动线独立用高对比配色；按「明暗 × 皮肤」分档，避免一套色走天下。
    func activePulseColor(for key: String) -> Color {
        let k = key.lowercased()

        if monitor.panelIsDark {
            switch monitor.skin {
            case .glass, .ceramic:
                switch k {
                case "agy": return Color(hex: "9FCBFF")
                case "alma": return Color(hex: "FFD4A0")
                case "ping": return Color(hex: "D9B8FF")
                default: return Color(hex: "9FCBFF")
                }
            case .obsidian:
                switch k {
                case "agy": return Color(hex: "84BFFF")
                case "alma": return Color(hex: "FFC27A")
                case "ping": return Color(hex: "CFA8FF")
                default: return Color(hex: "84BFFF")
                }
            }
        }

        switch monitor.skin {
        case .glass:
            switch k {
            case "agy": return Color(hex: "0840A3")
            case "alma": return Color(hex: "7A3300")
            case "ping": return Color(hex: "5A20B5")
            default: return Color(hex: "0840A3")
            }
        case .ceramic:
            switch k {
            case "agy": return Color(hex: "0B4BB3")
            case "alma": return Color(hex: "8A3B00")
            case "ping": return Color(hex: "5A20B5")
            default: return Color(hex: "0B4BB3")
            }
        case .obsidian:
            switch k {
            case "agy": return Color(hex: "9FCBFF")
            case "alma": return Color(hex: "FFD4A0")
            case "ping": return Color(hex: "D9B8FF")
            default: return Color(hex: "9FCBFF")
            }
        }
    }

    /// 只有 activePulses 非空时才挂载；每条边固定 1 个光点、共享 2.4s 周期
    func topologyPulseLayer(width: CGFloat, railY: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                func anchorX(_ key: String) -> CGFloat {
                    switch key {
                    case "agy": return size.width * 0.16
                    case "ping": return size.width * 0.84
                    default: return size.width * 0.5
                    }
                }
                for (edgeIndex, pulse) in monitor.activePulses.enumerated() {
                    let source = AgentRoster.identity(for: pulse.source)
                    let color = activePulseColor(for: source?.key ?? pulse.source)
                    let a = CGPoint(x: anchorX(pulse.source), y: railY)
                    let b = CGPoint(x: anchorX(pulse.target), y: railY)
                    let dir: CGFloat = b.x >= a.x ? 1 : -1
                    let start = CGPoint(x: a.x + dir * 22, y: railY)
                    let tip = CGPoint(x: b.x - dir * 24, y: railY)

                    // V2：活动线使用高对比专色，不再直接取 agent 原色。
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: CGPoint(x: tip.x - dir * 6, y: railY))
                    context.stroke(line, with: .color(color), lineWidth: 2.2)

                    // 方向箭头
                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - dir * 8, y: railY - 4.5))
                    head.addLine(to: CGPoint(x: tip.x - dir * 8, y: railY + 4.5))
                    head.closeSubpath()
                    context.fill(head, with: .color(color))

                    // V5：每条边只有 1 个光点，全边共享 2.4s 周期；半径 3、单层 4px 辉光。
                    // 两条边同时活跃 = 两个点（0.3s 相位差），绝不叠成一串。
                    let cycle: Double = 2.4
                    let phase = (now / cycle + Double(edgeIndex) * 0.3 / cycle)
                        .truncatingRemainder(dividingBy: 1.0)
                    let x = a.x + (b.x - a.x) * CGFloat(phase)
                    let glow = CGRect(x: x - 4, y: railY - 4, width: 8, height: 8)
                    let core = CGRect(x: x - 3, y: railY - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: glow), with: .color(color.opacity(0.20)))
                    context.fill(Path(ellipseIn: core), with: .color(color.opacity(0.92)))
                    context.fill(Path(ellipseIn: core.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white.opacity(0.95)))
                }
            }
            .frame(width: width, height: 108)
        }
    }

    // AgentIsland 架构调度·全透明履约焦点卡 (点开卡片可查看核心提炼重点)
    @ViewBuilder
    var liveDispatchHeroCardView: some View {
        let count = monitor.pendingConfirms.count
        if count > 0 {
            let safeIdx = min(max(0, monitor.activeConfirmIndex), count - 1)
            let item = monitor.pendingConfirms[safeIdx]
            
            VStack(spacing: 12) {
                // Header: 调度状态 + 轮播器
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "8B5CF6"))
                            .frame(width: 18, height: 18)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("架构调度 · 发起方亲自视觉验收闭环")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(textPurple)
                    
                    Spacer()
                    
                    if count > 1 {
                        HStack(spacing: 6) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx - 1 + count) % count
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 18, height: 18)
                                    .background(squircleCardBackground)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("\(safeIdx + 1)/\(count)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx + 1) % count
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
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
                VStack(alignment: .leading, spacing: 12) {
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textBlue)
                            Text("➔")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Text("派单方: \(item.to)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(textPurple)
                        }
                        
                        if !item.artifacts.isEmpty {
                            Text("•")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Button(action: {
                                let ap = item.artifacts.hasPrefix("/") ? item.artifacts : "\(monitor.rootPath)/../\(item.artifacts)"
                                NSWorkspace.shared.open(URL(fileURLWithPath: ap))
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right.square.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("产物: \(item.artifacts)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(accentTextColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            monitor.toggleTaskExpanded(item.id)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(monitor.expandedTaskId == item.id ? "收起" : "重点")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(monitor.expandedTaskId == item.id ? accentOnColor : accentTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(monitor.expandedTaskId == item.id ? accentColor : accentColor.opacity(monitor.panelIsDark ? 0.20 : 0.10))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            let path = "\(monitor.rootPath)/\(item.file)"
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }) {
                            Text("原文")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // 点开卡片展开核心提炼重点
                    if monitor.expandedTaskId == item.id {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(accentTextColor)
                                Text("核心提炼重点")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(accentTextColor)
                            }
                            Text(item.highlights.isEmpty ? "（本单据暂无正文摘要）" : item.highlights)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(primaryTextColor)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(monitor.panelIsDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "8B5CF6").opacity(monitor.panelIsDark ? 0.16 : 0.08))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    monitor.toggleTaskExpanded(item.id)
                }
            }
            .padding(.horizontal, 2)
            .background(squircleCardBackground)
        }
    }

    // 全员就绪态 Hero 卡片 (AgentIsland & Autoloop 中台运行就绪)
    @ViewBuilder
    var autoloopReadyHeroCardView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "059669").opacity(monitor.panelIsDark ? 0.20 : 0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(textGreen)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("全网架构就绪 · 0 积压待办")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Text("•")
                        .foregroundColor(secondaryTextColor)
                    Text("Funnel 443 专线直达")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textGreen)
                }
                
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accentTextColor)
                        Text(monitor.tokenTotal)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                    }
                    Text("·")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(textGreen)
                        Text("缓存率 \(monitor.tokenCacheRate)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 13, weight: .bold))
                    Text("全网核验")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(squircleCardBackground)
    }

    // 横向三等分 Agent 平衡卡片 (3 Balanced Cards)
    func agentBalanceCard(icon: String, iconBg: Color, textTint: Color, title: String, subtitle: String, hasPending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(iconBg)
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    if hasPending {
                        Circle()
                            .fill(iconBg)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(hasPending ? textTint : secondaryTextColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(squircleCardBackground)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
    
    // 四段架构履约轴 (派单 ➔ 接单 ➔ 待验 ➔ 结案)
    func lifecycleStepperView(stage: String) -> some View {
        HStack(spacing: 3) {
            stepperNode(name: "派单", active: true, done: stage != "dispatched")
            Text("›").font(.system(size: 11, weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: "接单", active: stage == "accepted" || stage == "submitted" || stage == "confirmed", done: stage == "submitted" || stage == "confirmed")
            Text("›").font(.system(size: 11, weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: "待验", active: stage == "submitted" || stage == "confirmed", done: stage == "confirmed", highlight: stage == "submitted")
            Text("›").font(.system(size: 11, weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: "结案", active: stage == "confirmed", done: stage == "confirmed")
        }
    }

    func stepperNode(name: String, active: Bool, done: Bool, highlight: Bool = false) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(highlight ? Color(hex: "8B5CF6") : (active ? (done ? Color(hex: "10B981") : accentColor) : secondaryTextColor.opacity(0.35)))
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 11, weight: highlight || done || active ? .bold : .semibold, design: .rounded))
                .foregroundColor(highlight ? (monitor.panelIsDark ? Color(hex: "BF5AF2") : Color(hex: "6D28D9")) : (active ? (done ? (monitor.panelIsDark ? Color(hex: "30D158") : Color(hex: "047857")) : primaryTextColor) : secondaryTextColor))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isOk ? secondaryTextColor : Color(hex: "EF4444"))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func agentDisplayName(_ agent: String) -> String {
        AgentRoster.identity(for: agent)?.title ?? agent
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
                            .font(.system(size: 13, weight: .bold))
                        Text("返回")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(accentTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(accentColor.opacity(monitor.panelIsDark ? 0.22 : 0.12))
                    )
                }
                .buttonStyle(PressableScaleButtonStyle())
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle().fill(AgentRoster.identity(for: agent)?.color ?? accentColor)
                        .frame(width: 8, height: 8)
                    Text("\(agentDisplayName(agent)) 收件箱 · \(tasks.count) 件未读")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)
                }
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(monitor.rootPath)/\(agent)"))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                        Text("访达")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
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
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(task.stage == "accepted" ? Color(hex: "3B82F6") : (task.stage == "submitted" ? Color(hex: "8B5CF6") : Color(hex: "D97706")))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundColor(primaryTextColor)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                lifecycleStepperView(stage: task.stage)
                                                Text("•").font(.system(size: 11, weight: .semibold)).foregroundColor(secondaryTextColor)
                                                Text("\(task.from) ➔ \(task.to)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                if !task.eta.isEmpty {
                                                    Text("• \(task.eta)")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(textBlue)
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
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text(monitor.expandedTaskId == task.id ? "收起" : "重点")
                                                        .font(.system(size: 11, weight: .bold))
                                                }
                                                .foregroundColor(monitor.expandedTaskId == task.id ? accentOnColor : accentTextColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(
                                                    Capsule().fill(monitor.expandedTaskId == task.id ? accentColor : accentColor.opacity(monitor.panelIsDark ? 0.20 : 0.10))
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(task.file)"
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            }) {
                                                Text("原文")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3.5)
                                                    .background(
                                                        Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
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
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(accentTextColor)
                                                Text("核心提炼重点")
                                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                                    .foregroundColor(accentTextColor)
                                            }
                                            Text(task.highlights.isEmpty ? "（本单据暂无正文摘要）" : task.highlights)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(primaryTextColor)
                                                .lineSpacing(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(monitor.panelIsDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
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
                                .foregroundColor(textGreen)
                            Text("当前无积压待办 · 全员就绪")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(textGreen)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 2. Done Feed Section (Recent Completed Replies)
                    if !dones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(secondaryTextColor)
                                Text("最新结案回信 · 已办结流")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(textGreen)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(done.title)
                                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                                    .foregroundColor(primaryTextColor)
                                                    .lineLimit(1)
                                                HStack(spacing: 4) {
                                                    Text("回件: \(done.from) ➔ \(done.to)")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(secondaryTextColor)
                                                    Text("•").font(.system(size: 11, weight: .semibold)).foregroundColor(secondaryTextColor)
                                                    Text(done.date)
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(secondaryTextColor)
                                                }
                                            }
                                            Spacer()
                                            
                                            Button(action: {
                                                monitor.toggleTaskExpanded(done.id)
                                            }) {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: 11, weight: .semibold))
                                                    Text(monitor.expandedTaskId == done.id ? "收起" : "重点")
                                                        .font(.system(size: 11, weight: .bold))
                                                }
                                                .foregroundColor(monitor.expandedTaskId == done.id ? accentOnColor : accentTextColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(
                                                    Capsule().fill(monitor.expandedTaskId == done.id ? accentColor : accentColor.opacity(monitor.panelIsDark ? 0.20 : 0.10))
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(done.file)"
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            }) {
                                                Text("原文")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3.5)
                                                    .background(
                                                        Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        // 点开回信卡片展开核心提炼重点！
                                        if monitor.expandedTaskId == done.id {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "text.quote")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(accentTextColor)
                                                    Text("核心提炼重点")
                                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                                        .foregroundColor(accentTextColor)
                                                }
                                                Text(done.highlights.isEmpty ? "（本回信暂无正文摘要）" : done.highlights)
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundColor(primaryTextColor)
                                                    .lineSpacing(3)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(monitor.panelIsDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
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
                .padding(.vertical, 3.5)
            }
            
            // Bottom Guidance Line
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textAmber)
                Text("露露掌握最高裁决权 · 见真实回信与产物方可收口")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.bottom, 8)
        }
    }

    /// 卡片层：macOS 26+ 用 SwiftUI 原生玻璃；旧系统退回半透明填充。
    /// 玻璃上的文字仍是实色，只有背景透明，避免“实色层把玻璃盖死”。
    @ViewBuilder
    var squircleCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if #available(macOS 26.0, *), !Self.forceGlassFallback {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(cardGlassTint), in: shape)
            } else {
                shape.fill(cardFallbackFill)
            }
        }
        .overlay(
            shape.stroke(
                monitor.panelIsDark
                    ? Color.white.opacity(0.22)
                    : Color.white.opacity(0.95),
                lineWidth: 0.9
            )
        )
        .shadow(
            color: Color.black.opacity(monitor.panelIsDark ? 0.28 : 0.06),
            radius: 2.5,
            y: 1.2
        )
    }

    /// 底部资产条需要更强的可读性：保留玻璃折射，但把透底噪音压住。
    @ViewBuilder
    var assetsRowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if #available(macOS 26.0, *), !Self.forceGlassFallback {
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(assetsRowGlassTint), in: shape)
            } else {
                shape.fill(assetsRowFallbackFill)
            }
        }
        .overlay(
            shape.stroke(
                monitor.panelIsDark
                    ? Color.white.opacity(0.26)
                    : Color.white.opacity(0.96),
                lineWidth: 0.9
            )
        )
        .shadow(
            color: Color.black.opacity(monitor.panelIsDark ? 0.30 : 0.07),
            radius: 2.5,
            y: 1.2
        )
    }

    static var forceGlassFallback: Bool {
        ProcessInfo.processInfo.environment["AGENT_ISLAND_GLASS"] == "0"
    }

    var assetsRowGlassTint: Color {
        switch monitor.skin {
        case .glass:
            return monitor.panelIsDark
                ? Color(hex: "0B1526").opacity(0.62)
                : Color(hex: "EAF4FF").opacity(0.60)
        case .obsidian:
            return Color(hex: "0A0A0C").opacity(0.66)
        case .ceramic:
            return monitor.panelIsDark
                ? Color(hex: "2A2620").opacity(0.64)
                : Color(hex: "F7EFDF").opacity(0.66)
        }
    }

    var assetsRowFallbackFill: Color {
        switch monitor.skin {
        case .glass:
            return monitor.panelIsDark
                ? Color(hex: "141418").opacity(0.78)
                : Color(hex: "FFFFFF").opacity(0.86)
        case .obsidian:
            return Color(hex: "141418").opacity(0.90)
        case .ceramic:
            return monitor.panelIsDark
                ? Color(hex: "2A2620").opacity(0.86)
                : Color(hex: "FBF5E9").opacity(0.90)
        }
    }

    var cardGlassTint: Color {
        switch monitor.skin {
        case .glass:
            return monitor.panelIsDark
                ? Color(hex: "0B1526").opacity(usesHighTransmissionGlass ? 0.30 : 0.78)
                : Color(hex: "EAF4FF").opacity(usesHighTransmissionGlass ? 0.10 : 0.34)
        case .obsidian:
            return Color(hex: "0A0A0C").opacity(0.66)
        case .ceramic:
            return monitor.panelIsDark
                ? Color(hex: "2A2620").opacity(0.78)
                : Color(hex: "F7EFDF").opacity(0.52)
        }
    }

    var cardFallbackFill: Color {
        switch monitor.skin {
        case .glass:
            return monitor.panelIsDark
                ? Color(hex: "141418").opacity(0.84)
                : Color(hex: "FFFFFF").opacity(0.78)
        case .obsidian:
            return Color(hex: "141418").opacity(0.92)
        case .ceramic:
            return monitor.panelIsDark
                ? Color(hex: "2A2620").opacity(0.88)
                : Color(hex: "FBF5E9").opacity(0.90)
        }
    }
    
    var totalPending: Int {
        monitor.agyPending + monitor.almaPending + monitor.pingPending
    }
    
    /// 皮肤 × 明暗：三种皮肤必须真实可见，而不是三个几乎同色的白/黑
    /// - 通透玻璃：冷白半透明，保留背后折射
    /// - 曜石深色：不论系统明暗都使用近黑石板，文字自动切浅色
    /// - 陶瓷实心：暖象牙实底，无透视
    var panelFill: Color {
        // 原生玻璃已在下层折射；这层只保留皮肤色感，不能再盖成不透明实色。
        switch monitor.skin {
        case .glass:
            // 展开态减薄满幅色罩，资产条和文字继续提供局部对比。
            return monitor.panelIsDark
                ? Color(hex: "101A2E").opacity(usesHighTransmissionGlass ? 0.00 : 0.10)
                : Color(hex: "F5F9FF").opacity(usesHighTransmissionGlass ? 0.00 : 0.06)
        case .obsidian:
            return Color(hex: "050506").opacity(monitor.panelIsDark ? 0.80 : 0.90)
        case .ceramic:
            return monitor.panelIsDark
                ? Color(hex: "2A2620").opacity(0.74)
                : Color(hex: "F6F1E7").opacity(0.78)
        }
    }

    private var usesHighTransmissionGlass: Bool {
        if #available(macOS 26.0, *) {
            return monitor.skin == .glass && monitor.currentMode == .expanded && !Self.forceGlassFallback
        }
        return false
    }

    /// 传给 NSGlassEffectView.tintColor，保留原生材质与折射。
    var glassTintNSColor: NSColor {
        switch monitor.skin {
        case .glass:
            return monitor.panelIsDark
                ? NSColor(srgbRed: 0.043, green: 0.082, blue: 0.149, alpha: usesHighTransmissionGlass ? 0.06 : 0.30)
                : NSColor(srgbRed: 0.863, green: 0.922, blue: 1.0, alpha: usesHighTransmissionGlass ? 0.05 : 0.22)
        case .obsidian:
            return NSColor(srgbRed: 0.020, green: 0.020, blue: 0.024, alpha: 0.55)
        case .ceramic:
            return monitor.panelIsDark
                ? NSColor(srgbRed: 0.165, green: 0.149, blue: 0.125, alpha: 0.45)
                : NSColor(srgbRed: 0.965, green: 0.945, blue: 0.906, alpha: 0.35)
        }
    }

    // Dynamic Typography Colors
    var primaryTextColor: Color {
        monitor.panelIsDark ? Color.white : Color(hex: "000000")
    }
    
    var secondaryTextColor: Color {
        monitor.panelIsDark ? Color(hex: "E5E5EA") : Color(hex: "1C1C1E")
    }

    /// 正文用强调色（浅色模式下压暗，保证 ≥4.5:1；不靠 opacity 调淡）
    var accentTextColor: Color {
        let hex = monitor.accentHex.uppercased()
        if monitor.panelIsDark {
            switch hex {
            case "EAB308": return Color(hex: "FFD60A")
            case "22C55E": return Color(hex: "30D158")
            case "9053F8": return Color(hex: "BF5AF2")
            case "EF4444": return Color(hex: "FF6961")
            default: return Color(hex: "64D2FF")
            }
        } else {
            switch hex {
            case "9053F8": return Color(hex: "5E3DB3")
            case "EAB308": return Color(hex: "7A5C00")
            case "22C55E": return Color(hex: "0B7A3B")
            case "EF4444": return Color(hex: "C1121F")
            default: return Color(hex: "0051D5")
            }
        }
    }

    /// Agent 固定身份色的「文字安全」版本；识别色仍由圆点/图标承担
    func agentTextColor(_ agent: AgentIdentity) -> Color {
        if monitor.panelIsDark {
            switch agent.key {
            case "agy": return Color(hex: "64D2FF")
            case "alma": return Color(hex: "FFB340")
            case "ping": return Color(hex: "BF5AF2")
            default: return primaryTextColor
            }
        } else {
            switch agent.key {
            case "agy": return Color(hex: "0051D5")
            case "alma": return Color(hex: "9A3412")
            case "ping": return Color(hex: "6D28D9")
            default: return primaryTextColor
            }
        }
    }

    /// 在强调色实底上选黑/白文字：按相对亮度取对比度更高者
    var accentOnColor: Color {
        let hex = monitor.accentHex
        let chars = Array(hex.uppercased())
        guard chars.count == 6 else { return .white }
        func comp(_ i: Int) -> Double {
            let v = Double(Int(String(chars[i * 2...i * 2 + 1]), radix: 16) ?? 0) / 255.0
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let lum = 0.2126 * comp(0) + 0.7152 * comp(1) + 0.0722 * comp(2)
        let onWhite = 1.05 / (lum + 0.05)
        let onBlack = (lum + 0.05) / 0.05
        return onWhite >= onBlack ? .white : .black
    }

    var textGreen: Color { monitor.panelIsDark ? Color(hex: "30D158") : Color(hex: "047857") }
    var textBlue: Color { monitor.panelIsDark ? Color(hex: "64D2FF") : Color(hex: "1D4ED8") }
    var textPurple: Color { monitor.panelIsDark ? Color(hex: "BF5AF2") : Color(hex: "6D28D9") }
    var textAmber: Color { monitor.panelIsDark ? Color(hex: "FFD60A") : Color(hex: "B45309") }
    var textRed: Color { monitor.panelIsDark ? Color(hex: "FF6961") : Color(hex: "C1121F") }
    var textGray: Color { monitor.panelIsDark ? Color(hex: "FFFFFF") : Color(hex: "1F2937") }
    
    var compactBadgeColor: Color {
        if !monitor.funnelOnline || !monitor.nutstoreOnline || !monitor.tailscaleOnline || monitor.fusedCount > 0 {
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
        if monitor.fusedCount > 0 {
            return "flame.fill"
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
        case .compact:
            return monitor.preferredCompactWidth
        case .notification: return 340
        case .expanded:
            return 560
        }
    }
    
    var contentHeight: CGFloat {
        switch monitor.currentMode {
        case .compact: return 40
        case .notification: return 38
        case .expanded:
            return monitor.expandedContentHeight
        }
    }
    
    var cornerRadius: CGFloat {
        switch monitor.currentMode {
        case .compact:
            // 胶囊圆角 = 高度的一半，不再固定 14
            return monitor.islandForm == .capsule ? contentHeight / 2 : 10
        case .notification:
            return monitor.islandForm == .capsule ? contentHeight / 2 : 14
        case .expanded: return monitor.islandForm == .capsule ? 18 : 22
        }
    }
    
    var allHealthy: Bool {
        return monitor.funnelOnline && monitor.nutstoreOnline && monitor.tailscaleOnline && totalPending == 0 && monitor.totalSubmitted == 0
    }
    
    var statusSummary: String {
        if !monitor.funnelOnline || !monitor.nutstoreOnline || !monitor.tailscaleOnline {
            return "通道异常"
        }
        if monitor.fusedCount > 0 {
            return "M1熔断 \(monitor.fusedCount)项"
        }
        var parts: [String] = []
        if monitor.totalDispatched > 0 {
            parts.append("\(monitor.totalDispatched)待办")
        }
        if monitor.totalAccepted > 0 {
            parts.append("\(monitor.totalAccepted)履约中")
        }
        if monitor.totalSubmitted > 0 {
            parts.append("\(monitor.totalSubmitted)待验")
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        return "全员就绪"
    }
}

// MARK: - AppKit Window Controller with Auto-Dismiss & Screen Tracking
// MARK: - Virtual-only test placement
private enum VirtualIslandDisplay {
    static let name = "AlmaVirtualScreen"

    static func id(of screen: NSScreen?) -> CGDirectDisplayID? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func find(id expectedID: CGDirectDisplayID? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        let matches = screens.filter { $0.localizedName == name }
        guard matches.count == 1, let screen = matches.first, let id = id(of: screen),
              expectedID == nil || id == expectedID,
              CGDisplayIsActive(id) != 0, CGDisplayIsMain(id) == 0,
              CGDisplayIsInMirrorSet(id) == 0, !screen.frame.isEmpty,
              !screens.contains(where: { $0 !== screen && $0.frame.intersects(screen.frame) }) else {
            return nil
        }
        return screen
    }

    static func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        return NSRect(x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    static func stop(_ reason: String) -> Never {
        fputs("ISLAND_VIRTUAL_ONLY: \(reason)\n", stderr)
        exit(1)
    }

    static func watchConfiguration() {
        // Quit at Quartz's pre-change callback, rather than let WindowServer
        // migrate a visible test panel and react only after the change.
        guard CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if !flags.isEmpty {
                fputs("ISLAND_VIRTUAL_ONLY: display configuration changed; exiting\n", stderr)
                _exit(1)
            }
        }, nil) == .success else {
            stop("cannot watch display reconfiguration")
        }
    }
}

class DynamicIslandPanel: NSPanel {
    private let virtualBounds: NSRect?

    init(contentRect: NSRect, virtualBounds: NSRect? = nil) {
        self.virtualBounds = virtualBounds
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: virtualBounds != nil
        )
        self.ignoresMouseEvents = virtualBounds != nil
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
    
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let virtualBounds else { return super.constrainFrameRect(frameRect, to: screen) }
        return VirtualIslandDisplay.clamp(frameRect, to: virtualBounds)
    }

    override var canBecomeKey: Bool { return virtualBounds == nil }
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
    let monitor: AgentMonitor
    private let virtualDisplayID: CGDirectDisplayID?

    init(virtualDisplayID: CGDirectDisplayID?) {
        self.virtualDisplayID = virtualDisplayID
        monitor = AgentMonitor(virtualTest: virtualDisplayID != nil)
        super.init()
    }

    var globalClickMonitor: Any?
    var localClickMonitor: Any?

    var hoverTimer: Timer?
    var autoHoverExpanded = false
    var suppressHoverUntilExit = false
    var hoverOutsideSince: Date?
    var hoverInsideSince: Date?
    /// 仅快照自测使用：让定时轮询也采用同一假鼠标点，模拟真实指针停留。
    var hoverOverridePoint: NSPoint?

    var themeAutoItem: NSMenuItem?
    var themeLightItem: NSMenuItem?
    var themeDarkItem: NSMenuItem?
    var accentMenuItems: [String: NSMenuItem] = [:]
    var skinMenuItems: [String: NSMenuItem] = [:]
    var formMenuItems: [String: NSMenuItem] = [:]
    var scaleMenuItems: [Int: NSMenuItem] = [:]
    var edgeMenuItems: [String: NSMenuItem] = [:]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let virtualDisplayID {
            launchVirtualTest(on: virtualDisplayID)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        // 仅截图取证：临时以普通 App 身份运行，让 Dock 显示真实 AppIcon（不改变常驻形态）
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_SHOW_DOCK"] == "1" {
            NSApp.setActivationPolicy(.regular)
        }
        
        setupStatusItem()
        setupIslandPanel()
        setupAutoDismissMonitors()
        setupHoverWatcher()

        monitor.onModeChange = { [weak self] mode in
            self?.updatePanelFrame(for: mode)
        }

        monitor.onDrawerChange = { [weak self] in
            guard let self = self else { return }
            self.updatePanelFrame(for: self.monitor.currentMode)
        }

        monitor.onLayoutChange = { [weak self] in
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

        // 快照导出（仅在显式传入 AGENT_ISLAND_SNAPSHOT_DIR 时启用；用于本机无录屏权限时自证 UI）
        if let dir = ProcessInfo.processInfo.environment["AGENT_ISLAND_SNAPSHOT_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self = self else { return }
                self.autoHoverExpanded = false
                self.monitor.setMode(.compact)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.exportPanelPNG(to: dir + "/compact.png")
                    // 用与真实鼠标相同的 evaluateHover 路径验证「靠近自动展开」
                    let hotPoint = NSPoint(x: self.islandPanel.frame.midX, y: self.islandPanel.frame.minY - 20)
                    self.suppressHoverUntilExit = false
                    self.hoverInsideSince = nil
                    self.hoverOverridePoint = hotPoint
                    self.evaluateHover(at: hotPoint)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.evaluateHover(at: hotPoint)
                        self.appendSnapshotLog(dir: dir, line: "hover_selftest=\(self.monitor.currentMode)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            self.exportPanelPNG(to: dir + "/expanded.png")
                            self.monitor.showTopology = true
                            self.updatePanelFrame(for: .expanded)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.exportPanelPNG(to: dir + "/topology.png")
                                self.monitor.showTopology = false
                                self.monitor.showSettings = true
                                self.updatePanelFrame(for: .expanded)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.exportPanelPNG(to: dir + "/settings.png")
                                    self.monitor.showSettings = false
                                    self.monitor.setDrawerAgent("agy")
                                    self.updatePanelFrame(for: .expanded)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        self.exportPanelPNG(to: dir + "/drawer.png")
                                        self.monitor.selectedDrawerAgent = nil
                                        self.updatePanelFrame(for: .expanded)
                                        self.hoverOverridePoint = NSPoint(x: 0, y: 0)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                            self.appendSnapshotLog(dir: dir, line: "hover_collapse=\(self.monitor.currentMode)")
                                            self.hoverOverridePoint = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 右键菜单截图（仅显式传入 AGENT_ISLAND_OPEN_MENU=1 时启用；菜单展开会阻塞主线程直至人工关闭）
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_OPEN_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, let button = self.statusItem.button else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.statusItem.menu?.popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: button.bounds.height + 2),
                    in: button
                )
            }
        }
    }

    private func virtualScreenOrExit(id: CGDirectDisplayID) -> NSScreen {
        guard let screen = VirtualIslandDisplay.find(id: id) else {
            islandPanel?.orderOut(nil)
            VirtualIslandDisplay.stop("test display missing or no longer isolated")
        }
        return screen
    }

    private func launchVirtualTest(on id: CGDirectDisplayID) {
        let screen = virtualScreenOrExit(id: id)
        guard NSApp.setActivationPolicy(.accessory), !NSApp.isActive else {
            VirtualIslandDisplay.stop("cannot run as a background accessory")
        }

        let initialFrame = VirtualIslandDisplay.clamp(panelFrame(for: .compact, in: screen.frame), to: screen.frame)
        islandPanel = DynamicIslandPanel(contentRect: initialFrame, virtualBounds: screen.frame)
        // Check the frame returned by AppKit, not just the requested frame.
        let currentScreen = virtualScreenOrExit(id: id)
        guard currentScreen.frame.contains(islandPanel.frame), !islandPanel.frame.isEmpty else {
            VirtualIslandDisplay.stop("initial panel frame is outside test display")
        }
        logVirtualPanel(phase: "initial", on: currentScreen)
        installPanelContent()
        updatePanelFrame(for: .compact)
        islandPanel.orderFrontRegardless()
        verifyVisibleVirtualPanel(phase: "compact", on: virtualScreenOrExit(id: id))

        monitor.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.updatePanelFrame(for: mode)
            self.verifyVisibleVirtualPanel(phase: "\(mode)", on: self.virtualScreenOrExit(id: id))
        }
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_EXPAND"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.monitor.setMode(.expanded)
            }
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        // Secondary guard if AppKit delivers a change without the Quartz callback.
        guard virtualDisplayID != nil else { return }
        islandPanel?.orderOut(nil)
        VirtualIslandDisplay.stop("AppKit screen parameters changed")
    }

    private func verifyVisibleVirtualPanel(phase: String, on screen: NSScreen) {
        guard islandPanel.isVisible, !islandPanel.isKeyWindow, !NSApp.isActive,
              VirtualIslandDisplay.id(of: islandPanel.screen) == virtualDisplayID,
              screen.frame.contains(islandPanel.frame), !islandPanel.frame.isEmpty else {
            islandPanel.orderOut(nil)
            VirtualIslandDisplay.stop("panel not confined to test display or acquired focus")
        }
        logVirtualPanel(phase: phase, on: screen)
    }

    private func logVirtualPanel(phase: String, on screen: NSScreen) {
        print("ISLAND_VIRTUAL_ONLY: phase=\(phase) target=\(screen.localizedName) id=\(virtualDisplayID ?? 0) screenFrame=\(screen.frame) panelScreen=\(islandPanel.screen?.localizedName ?? "none") panelFrame=\(islandPanel.frame) window=\(islandPanel.windowNumber) visible=\(islandPanel.isVisible) key=\(islandPanel.isKeyWindow) active=\(NSApp.isActive)")
        fflush(stdout)
    }

    func appendSnapshotLog(dir: String, line: String) {
        let logURL = URL(fileURLWithPath: dir + "/snapshot.log")
        guard let d = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        } else { try? d.write(to: logURL) }
    }

    /// 用 AppKit 直接把面板视图渲染为 PNG（不依赖系统屏幕录制权限）
    func exportPanelPNG(to path: String) {
        guard let view = islandPanel.contentView, view.bounds.width > 0 else { return }
        let logLine = "mode=\(monitor.currentMode) panel=\(islandPanel.frame) view=\(view.bounds)\n"
        let logURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent + "/snapshot.log")
        if let d = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
            } else { try? d.write(to: logURL) }
        }
        // 以 2 倍像素密度渲染，保证导出的 PNG 字体锐利（1x 缓存会发虚）
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * scale),
            pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path))
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
                } else {
                    // 用户已亲自操作面板 → 转成「钉住」，不再随鼠标离开自动收起
                    self.autoHoverExpanded = false
                }
            }
            return event
        }
    }

    // MARK: - 靠近自动展开 / 离开自动收起（不依赖 Accessibility 权限，轮询鼠标位置）
    func setupHoverWatcher() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            self?.evaluateHover()
        }
        if let t = hoverTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    func evaluateHover(at overridePoint: NSPoint? = nil) {
        guard islandPanel != nil else { return }
        let mouse = overridePoint ?? hoverOverridePoint ?? NSEvent.mouseLocation
        let frame = islandPanel.frame
        if let dbgPath = ProcessInfo.processInfo.environment["AGENT_ISLAND_HOVER_LOG"] {
            let line = "mode=\(monitor.currentMode) auto=\(autoHoverExpanded) mouse=\(mouse) panel=\(frame) supp=\(suppressHoverUntilExit) inside=\(hoverInsideSince.map { Date().timeIntervalSince($0) } ?? -1) outside=\(hoverOutsideSince.map { Date().timeIntervalSince($0) } ?? -1)\n"
            if let d = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: dbgPath) {
                    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: dbgPath)) { h.seekToEndOfFile(); h.write(d); try? h.close() }
                } else { try? d.write(to: URL(fileURLWithPath: dbgPath)) }
            }
        }

        switch monitor.currentMode {
        case .compact:
            // 收起态：鼠标靠近面板周边即展开
            let hot = NSRect(
                x: frame.minX - 72,
                y: frame.minY - 48,
                width: frame.width + 144,
                height: frame.height + 62
            )
            guard hot.contains(mouse) else {
                suppressHoverUntilExit = false
                hoverInsideSince = nil
                return
            }
            guard !suppressHoverUntilExit else { return }
            if hoverInsideSince == nil { hoverInsideSince = Date() }
            // 停留 0.18s 再展开，避免鼠标路过误触
            if Date().timeIntervalSince(hoverInsideSince ?? Date()) >= 0.18 {
                autoHoverExpanded = true
                hoverOutsideSince = nil
                monitor.setMode(.expanded)
            }

        case .expanded:
            guard autoHoverExpanded else { return }
            let keep = frame.insetBy(dx: -76, dy: -52)
            if keep.contains(mouse) {
                hoverOutsideSince = nil
            } else {
                if hoverOutsideSince == nil { hoverOutsideSince = Date() }
                if Date().timeIntervalSince(hoverOutsideSince ?? Date()) >= 0.7 {
                    autoHoverExpanded = false
                    hoverOutsideSince = nil
                    suppressHoverUntilExit = true
                    monitor.setMode(.compact)
                }
            }

        default:
            break
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "AgentIsland")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = "3A"
        }

        let menu = NSMenu()
        menu.delegate = self

        // 统一图标语义：全部使用 SF Symbols（template），不用 emoji
        func makeItem(_ title: String, _ symbol: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .option) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            item.image = image
            if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
            return item
        }

        func makeHeader(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            item.isEnabled = false
            return item
        }

        // 1. 中控台
        menu.addItem(makeItem("打开/收起中控台", "rectangle.topthird.inset.filled", #selector(toggleIsland), key: "1"))
        menu.addItem(makeItem("全局核验与归档", "checkmark.seal", #selector(reconcileAll), key: "k"))
        menu.addItem(NSMenuItem.separator())

        // 2. 打开
        menu.addItem(makeItem("Spaces 产物库", "folder", #selector(openSpaces), key: "s"))
        menu.addItem(makeItem("交流.md", "bubble.left.and.bubble.right", #selector(openCommLog), key: "c"))
        menu.addItem(makeItem("全景图", "photo.on.rectangle", #selector(openPanorama), key: "p"))
        menu.addItem(NSMenuItem.separator())

        // 3. 自检
        menu.addItem(makeItem("检查 Funnel 健康状态", "waveform.path.ecg", #selector(openFunnelHealth), key: "f"))
        menu.addItem(NSMenuItem.separator())

        // 4. 外观：明暗模式 / 皮肤 / 形态 / 尺寸 / 停靠边 / 强调色 合并为一个子菜单
        let appearanceMenu = NSMenu()
        appearanceMenu.addItem(makeHeader("明暗模式"))
        let aItem = makeItem("跟随系统", "display", #selector(setThemeAuto))
        let lItem = makeItem("浅色", "sun.max", #selector(setThemeLight))
        let dItem = makeItem("深色", "moon", #selector(setThemeDark))
        appearanceMenu.addItem(aItem)
        appearanceMenu.addItem(lItem)
        appearanceMenu.addItem(dItem)
        themeAutoItem = aItem
        themeLightItem = lItem
        themeDarkItem = dItem

        appearanceMenu.addItem(NSMenuItem.separator())
        appearanceMenu.addItem(makeHeader("皮肤"))
        skinMenuItems.removeAll()
        for skin in IslandSkin.allCases {
            let it = makeItem(skin.name, "square.on.square", #selector(setSkinAction(_:)))
            it.representedObject = skin.rawValue
            appearanceMenu.addItem(it)
            skinMenuItems[skin.rawValue] = it
        }

        appearanceMenu.addItem(NSMenuItem.separator())
        appearanceMenu.addItem(makeHeader("形态"))
        formMenuItems.removeAll()
        for form in IslandForm.allCases {
            let it = makeItem(form.name, form == .capsule ? "capsule" : "rectangle.portrait", #selector(setFormAction(_:)))
            it.representedObject = form.rawValue
            appearanceMenu.addItem(it)
            formMenuItems[form.rawValue] = it
        }

        appearanceMenu.addItem(NSMenuItem.separator())
        appearanceMenu.addItem(makeHeader("尺寸"))
        scaleMenuItems.removeAll()
        var percent = 80
        while percent <= 140 {
            let it = makeItem("\(percent)%", "arrow.up.left.and.arrow.down.right", #selector(setUIScaleAction(_:)))
            it.tag = percent
            appearanceMenu.addItem(it)
            scaleMenuItems[percent] = it
            percent += 5
        }

        appearanceMenu.addItem(NSMenuItem.separator())
        appearanceMenu.addItem(makeHeader("停靠边"))
        edgeMenuItems.removeAll()
        for edge in DockEdge.allCases {
            let it = makeItem(edge.name, "dock.rectangle", #selector(setDockEdgeAction(_:)))
            it.representedObject = edge.rawValue
            appearanceMenu.addItem(it)
            edgeMenuItems[edge.rawValue] = it
        }

        appearanceMenu.addItem(NSMenuItem.separator())
        appearanceMenu.addItem(makeHeader("强调色"))
        accentMenuItems.removeAll()
        for preset in AccentPreset.allCases {
            let it = makeItem(preset.name, "circle.fill", #selector(setAccentPresetAction(_:)))
            it.representedObject = preset.rawValue
            let swatch = NSImage(size: NSSize(width: 13, height: 13))
            swatch.lockFocus()
            NSColor(hex: preset.rawValue).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 11, height: 11)).fill()
            swatch.unlockFocus()
            it.image = swatch
            appearanceMenu.addItem(it)
            accentMenuItems[preset.rawValue] = it
        }

        let appearanceParent = NSMenuItem(title: "外观设置", action: nil, keyEquivalent: "")
        let appearanceIcon = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: nil)
        appearanceIcon?.isTemplate = true
        appearanceParent.image = appearanceIcon
        appearanceParent.submenu = appearanceMenu
        menu.addItem(appearanceParent)
        menu.addItem(NSMenuItem.separator())

        // 5. 退出
        menu.addItem(makeItem("退出 AgentIsland", "power", #selector(quitApp), key: "q", modifiers: .command))
        statusItem.menu = menu

        updateMenuCheckmarks()
    }

    func setupIslandPanel() {
        let initialRect = NSRect(x: 0, y: 0, width: 200, height: 48)
        islandPanel = DynamicIslandPanel(contentRect: initialRect)
        installPanelContent()
        updatePanelFrame(for: .compact)
        islandPanel.orderFrontRegardless()
    }

    private func installPanelContent() {
        let hostingView = FirstMouseHostingView(rootView: DynamicIslandView(monitor: monitor))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        islandPanel.contentView = hostingView
    }
    
    func getActiveScreen() -> NSScreen {
        let mouseLoc = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLoc, screen.frame, false) {
                return screen
            }
        }
        return NSScreen.screens.first ?? NSScreen()
    }
    
    private func panelFrame(for mode: IslandMode, in screenFrame: NSRect) -> NSRect {
        let windowWidth: CGFloat
        let windowHeight: CGFloat
        
        let scale = monitor.uiScale
        switch mode {
        case .compact:
            windowWidth = monitor.preferredCompactWidth * scale + 24
            windowHeight = 40 * scale + 8
        case .notification:
            windowWidth = 340 * scale + 24
            windowHeight = 38 * scale + 8
        case .expanded:
            windowWidth = 560 * scale + 24
            windowHeight = monitor.expandedContentHeight * scale + 16
        }

        let x: CGFloat
        let y: CGFloat
        switch monitor.dockEdge {
        case .top:
            x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2.0
            y = screenFrame.origin.y + screenFrame.height - windowHeight
        case .left:
            x = screenFrame.origin.x + 8
            y = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2.0
        case .right:
            x = screenFrame.origin.x + screenFrame.width - windowWidth - 8
            y = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2.0
        }
        
        // 半像素/非整数坐标会让 Retina 文字发虚：窗口与原点一律取整点
        return NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: windowWidth.rounded(),
            height: windowHeight.rounded()
        )
    }

    func updatePanelFrame(for mode: IslandMode) {
        if let virtualDisplayID {
            let screen = virtualScreenOrExit(id: virtualDisplayID)
            let rect = VirtualIslandDisplay.clamp(panelFrame(for: mode, in: screen.frame), to: screen.frame)
            islandPanel.setFrame(rect, display: true, animate: false)
            guard screen.frame.contains(islandPanel.frame), !islandPanel.frame.isEmpty else {
                islandPanel.orderOut(nil)
                VirtualIslandDisplay.stop("panel frame escaped test display")
            }
            return
        }
        let targetRect = panelFrame(for: mode, in: getActiveScreen().frame)
        islandPanel.setFrame(targetRect, display: true, animate: false)
        print("[AgentIsland] frame -> \(targetRect) contentH=\(monitor.expandedContentHeight)")
        
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

    @objc func openPanorama() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces/zi-yan-mcp-quan-jing-tu.html"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuCheckmarks()
    }

    func updateMenuCheckmarks() {
        themeAutoItem?.state = monitor.themeMode == .auto ? .on : .off
        themeLightItem?.state = monitor.themeMode == .light ? .on : .off
        themeDarkItem?.state = monitor.themeMode == .dark ? .on : .off

        for (raw, it) in skinMenuItems {
            it.state = monitor.skin.rawValue == raw ? .on : .off
        }
        for (raw, it) in formMenuItems {
            it.state = monitor.islandForm.rawValue == raw ? .on : .off
        }
        let currentScale = Int((monitor.uiScale * 100).rounded())
        for (percent, it) in scaleMenuItems {
            it.state = percent == currentScale ? .on : .off
        }
        for (raw, it) in edgeMenuItems {
            it.state = monitor.dockEdge.rawValue == raw ? .on : .off
        }
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

    @objc func setSkinAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let skin = IslandSkin(rawValue: raw) {
            monitor.setSkin(skin)
            updateMenuCheckmarks()
        }
    }

    @objc func setFormAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let form = IslandForm(rawValue: raw) {
            monitor.setIslandForm(form)
            updateMenuCheckmarks()
        }
    }

    @objc func setUIScaleAction(_ sender: NSMenuItem) {
        monitor.setUIScale(Double(sender.tag) / 100)
        updateMenuCheckmarks()
    }

    @objc func setDockEdgeAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let edge = DockEdge(rawValue: raw) {
            monitor.setDockEdge(edge)
            updateMenuCheckmarks()
        }
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
let testDisplayID: CGDirectDisplayID? = {
    // A/B test builds cannot fall back to normal launch even if the env flag is omitted.
    #if !ISLAND_VIRTUAL_TEST_BUILD
    guard ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_VIRTUAL_ONLY"] == "1" else { return nil }
    #endif
    guard let screen = VirtualIslandDisplay.find(), let id = VirtualIslandDisplay.id(of: screen) else {
        VirtualIslandDisplay.stop("no isolated AlmaVirtualScreen; no UI started")
    }
    VirtualIslandDisplay.watchConfiguration()
    return id
}()
let app = NSApplication.shared
let delegate = AppDelegate(virtualDisplayID: testDisplayID)
app.delegate = delegate
app.run()
