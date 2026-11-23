import AppKit
import CoreGraphics
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import Carbon.HIToolbox

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
            let targetStyle: NSGlassEffectView.Style = glassStyle == .clear ? .clear : .regular
            if v.style != targetStyle { v.style = targetStyle }
            if abs(v.cornerRadius - cornerRadius) > 0.01 { v.cornerRadius = cornerRadius }
            if v.tintColor != glassTint { v.tintColor = glassTint }
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
    var stepNote: String = ""
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

struct QuickAssetItem: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var icon: String
    var path: String

    static let defaults: [QuickAssetItem] = [
        QuickAssetItem(id: "panorama", label: "全景图", icon: "photo.on.rectangle", path: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces/zi-yan-mcp-quan-jing-tu.html"),
        QuickAssetItem(id: "spaces", label: "Spaces", icon: "folder.fill", path: "/Users/l/Nutstore Files/Obsidian_/multi-agent/spaces"),
        QuickAssetItem(id: "comm", label: "交流", icon: "bubble.left.and.bubble.right.fill", path: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/交流.md"),
        QuickAssetItem(id: "decisions", label: "决定档案", icon: "book.closed.fill", path: "/Users/l/Nutstore Files/Obsidian_/multi-agent/research-notes/decisions-archive.md"),
        QuickAssetItem(id: "corrections", label: "纠正日志", icon: "exclamationmark.bubble.fill", path: "/Users/l/Nutstore Files/Obsidian_/_state/corrections.tsv"),
    ]
}

enum PanelSectionKey: String, CaseIterable, Identifiable {
    case overview, wake, confirm, inboxes, channels, quickSend, assets
    var id: String { rawValue }
    var name: String {
        switch self {
        case .overview: return "总览摘要"
        case .wake: return "后台唤醒"
        case .confirm: return "待你验收"
        case .inboxes: return "三个收件箱"
        case .channels: return "三层通道"
        case .quickSend: return "快捷发信"
        case .assets: return "快捷资产"
        }
    }
    static let defaultOrder: [String] = allCases.map { $0.rawValue }
    static let defaults: [String: Bool] = Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0 != .overview) })
}

struct PingloopDeltaState: Equatable {
    var loaded: Bool = false
    var isStale: Bool = true
    var healthAgeMin: Int = 0
    var verdict: String = "PASS"
    var confirm: Int = 0
    var confirmDelta: Int? = nil
    var zombie: Int = 0
    var todayConfirmed: Int = 0
    var confirmMatrixText: String = ""
    var velocityText: String = ""
    var almaLoaded: Bool = false
    var almaAgeText: String = "待命"
    var almaCount: Int = 0
    var convTotal: Int = 0
    var convConfirmed: Int = 0
    var convMeanRounds: Double = 0
    var convFirstPassPct: Double = 0

    var confirmDeltaText: String {
        guard let d = confirmDelta else { return "" }
        if d > 0 { return "(+\(d))" }
        if d < 0 { return "(\(d))" }
        return "(±0)"
    }

    var verifierSummary: String {
        if convTotal == 0 {
            return "A级: 观察态(待试点)"
        }
        return "A级: \(convConfirmed)单·\(String(format: "%.1f", convMeanRounds))轮·\(Int(convFirstPassPct.rounded()))%"
    }

    var verifierShortBadge: String {
        convTotal == 0 ? "观察态" : "\(Int(convFirstPassPct.rounded()))%"
    }

    func fullTooltip(tokenTotal: String, cacheRate: String) -> String {
        var lines: [String] = []
        if loaded {
            lines.append("体检快照：\(verdict) · \(healthAgeMin) 分钟前\(isStale ? "（已超 30m 陈旧）" : "")")
        } else {
            lines.append("体检快照：未加载（M4）")
        }
        if !confirmMatrixText.isEmpty {
            lines.append("待确认矩阵：\n\(confirmMatrixText)")
        }
        if !velocityText.isEmpty {
            lines.append("每日 confirm：\(velocityText)")
        }
        if convTotal > 0 {
            lines.append("M6 A级收敛：\(convConfirmed)/\(convTotal) 单 · 平均 \(String(format: "%.2f", convMeanRounds)) 轮 · 一次率 \(Int(convFirstPassPct.rounded()))%")
        } else {
            lines.append("M6 A级收敛：观察态（暂无 enforce 样本）")
        }
        lines.append("Alma 后台：\(almaAgeText)（累计 \(almaCount) 项）")
        lines.append("本月用量：\(tokenTotal) · 缓存率 \(cacheRate)")
        return lines.joined(separator: "\n")
    }
}

struct FusedDecisionCard: Identifiable, Equatable {
    var id: String { path }
    let traceId: String
    let title: String
    let summary: String
    let path: String
}

struct HarnessProposalItem: Identifiable, Equatable {
    var id: String { signature }
    let signature: String
    let distinctSessions: Int
    let rawHits: Int
    let carrier: String
    let recommendedFix: String
    let shadowVerified: Bool
    let patchReportPath: String
}

enum PanelTab: String, CaseIterable {
    case team = "团队"
    case feed = "战报"
    case opt = "自优化"
    case topo = "链路"
}

struct HarnessAutoChangeItem: Identifiable, Equatable {
    var id: String { "\(signature)-\(kind)" }
    let signature: String
    let kind: String // upgraded, downgraded, observing
    let badge: String
    let title: String
    let change: String
    let sessions: Int
    let carrier: String
}

struct LoopFeedItem: Identifiable, Equatable {
    var id: String { "\(time)-\(path)" }
    let time: String
    let title: String
    let route: String
    let duration: String
    let summary: String
    let path: String
    let isGreen: Bool
}

struct SelfHarnessState: Equatable {
    var loaded: Bool = false
    var isStale: Bool = true
    var ageMin: Int = 0
    var sealOk: Bool = true
    var loopScore: Int = 100
    var smokePassed: Int = 6
    var smokeTotal: Int = 6
    var totalWallMin: Double = 0
    var effectiveExecMin: Double = 0
    var overheadLossMin: Double = 0
    var effectivePct: Double = 100
    var ticketsMeasured: Int = 0
    var proposals: [HarnessProposalItem] = []
    var autoChanges: [HarnessAutoChangeItem] = []

    var escalationCount: Int { proposals.count }
    var effectiveRatio: CGFloat {
        guard totalWallMin > 0 else { return 1.0 }
        return CGFloat(min(1.0, max(0.04, effectiveExecMin / totalWallMin)))
    }
}

struct WakeWorkerState: Equatable {
    var status: String = "idle"
    var dailyRuns: Int = 0
    var dailyRunsLimit: Int = 30
    var dailyTokens: Int = 0
    var dailyTokensLimit: Int = 500_000
    var lastFile: String = ""
    var elapsedS: Double = 0
    var paused: Bool = false
    var loaded: Bool = false
    /// agy-turn 快照里的 last_action（区分同为 status=error 的「异常」与「交付失败」）
    var lastAction: String = ""

    var effectiveStatus: String {
        if paused { return "paused" }
        // agy-turn 在 submit 落盘失败时写 status=error + last_action=submit-failed，
        // 只按 status 判别会显示成绿色「待命」——交付失败在面板上看起来是健康的。
        if status == "error" && lastAction == "submit-failed" { return "submit-failed" }
        return status
    }
    /// daily_tokens_limit<=0 表示不限量（agy-turn 的 0=unlimited 口径），不是「预算 0」。
    var tokenUnlimited: Bool { dailyTokensLimit <= 0 }
    var tokenRatio: Double {
        guard dailyTokensLimit > 0 else { return 0 }
        return min(1.0, max(0.0, Double(dailyTokens) / Double(dailyTokensLimit)))
    }
    var tokenPct: Int {
        Int((tokenRatio * 100).rounded())
    }
    var tokenPctText: String {
        tokenUnlimited ? "无上限" : "\(tokenPct)%"
    }
    var tooltipText: String {
        let tokK = dailyTokens / 1000
        let shortFile = URL(fileURLWithPath: lastFile).deletingPathExtension().lastPathComponent
        let budget = tokenUnlimited ? "Token 预算：无上限（今日已用 \(tokK)K）" : "Token 预算：\(tokK)K / \(dailyTokensLimit / 1000)K"
        if shortFile.isEmpty {
            return "\(budget) · 状态：\(effectiveStatus)"
        }
        return "\(budget) · 最近：\(shortFile)（\(String(format: "%.1fs", elapsedS))）"
    }
}

private func evenCeil(_ v: CGFloat) -> CGFloat {
    let r = v.rounded(.up)
    return r.truncatingRemainder(dividingBy: 2) == 0 ? r : r + 1
}

class AgentMonitor: ObservableObject {
    static let allowedScales: [Double] = [1.0, 1.1, 1.2]
    static func snapScale(_ v: Double) -> Double {
        if v >= 1.15 { return 1.2 }
        if v >= 1.08 { return 1.1 }
        return 1.0
    }

    @Published var themeMode: ThemeMode = .auto
    @Published var accentHex: String = "007AFF"
    @Published var agyPending: Int = 0
    @Published var almaPending: Int = 0
    @Published var pingPending: Int = 0

    @Published var pendingConfirms: [TaskItem] = []
    @Published var luluActions: [TaskItem] = []
    @Published var agentConfirms: [TaskItem] = []
    @Published var totalDispatched: Int = 0
    @Published var totalAccepted: Int = 0
    @Published var totalSubmitted: Int = 0
    @Published var totalLuluActions: Int = 0
    @Published var totalAgentConfirms: Int = 0
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
    @Published var lastCommRoute: String = ""
    /// AGY 后台无头唤醒实时态（监听父目录 ~/.config/alma/state/，抗 os.replace inode 替换）
    @Published var wakeState: WakeWorkerState = WakeWorkerState()

    /// 「恢复」二次确认的就地面板状态（不用系统模态框，避免弹到物理主屏）
    @Published var resumeConfirmPending: Bool = false
    @Published var resumeConfirmBacklog: Int = 0
    @Published var deltaState: PingloopDeltaState = PingloopDeltaState()
    @Published var fusedCards: [FusedDecisionCard] = []
    @Published var harnessState: SelfHarnessState = SelfHarnessState()
    @Published var harnessDrawerExpanded: Bool = false
    @Published var activeTab: PanelTab = .team {
        didSet { self.onLayoutChange?() }
    }
    @Published var todayClosedCount: Int = 0
    @Published var recentLoopFeed: [LoopFeedItem] = []
    @Published var expandedFeedId: String? = nil {
        didSet { self.onLayoutChange?() }
    }
    @Published var recentReceiptTitle: String = ""
    @Published var recentReceiptAt: Date? = nil
    @Published var simPcOnline: Bool = true
    private var prevTodayClosedCount: Int = -1
    @Published var observeResults: [String: String] = [:]
    @Published var drawerSearchText: String = ""
    @Published var drawerTodayOnly: Bool = false
    @Published var rejectTargetFile: String? = nil
    @Published var rejectReasonText: String = ""
    private var wakeDirFD: CInt = -1
    private var wakeDirSource: DispatchSourceFileSystemObject?
    private var wakeLastStatKey: String = ""
    private var liveWatchSources: [DispatchSourceFileSystemObject] = []
    private var liveDebounceWorkItem: DispatchWorkItem?
    private let liveWatchQueue = DispatchQueue(label: "com.sputnik.agentisland.livewatch", qos: .utility)
    private var lastKnownLuluActions: Int = -1

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
    @Published var hoverAutoExpand: Bool = false
    @Published var minimizedToMenuBar: Bool = false
    @Published var quickSendTarget: String = "ping"
    @Published var quickSendText: String = ""
    @Published var quickSendBusy: Bool = false
    @Published var quickAssets: [QuickAssetItem] = QuickAssetItem.defaults
    @Published var newAssetLabel: String = ""
    @Published var newAssetPath: String = ""
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
    var onMinimizeChange: ((Bool) -> Void)?
    
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

    private static let todayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    var todayDatePrefix: String {
        Self.todayDateFormatter.string(from: Date())
    }

    func todayCount(for key: String) -> Int {
        let prefix = todayDatePrefix
        let arr: [TaskItem]
        switch key {
        case "agy": arr = agyTasks
        case "alma": arr = almaTasks
        case "ping": arr = pingTasks
        default: return 0
        }
        return arr.filter { $0.date.hasPrefix(prefix) }.count
    }

    var todayUnreadLeaders: [(AgentIdentity, Int)] {
        AgentRoster.all
            .map { ($0, todayCount(for: $0.key)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    var totalTodayUnread: Int {
        todayCount(for: "agy") + todayCount(for: "alma") + todayCount(for: "ping")
    }

    var isRecentReceiptActive: Bool {
        guard let t = recentReceiptAt, !recentReceiptTitle.isEmpty else { return false }
        return Date().timeIntervalSince(t) <= 30.0
    }

    var compactHeadText: String {
        if dataUnknown { return "数据未知" }
        if fusedCount > 0 { return "M1 熔断 \(fusedCount) 项" }
        if totalLuluActions > 0 { return "\(totalLuluActions) 件待你拍板" }
        if wakeState.effectiveStatus == "running" { return "Loop 运转中" }
        if totalAgentConfirms > 0 && totalUnread > 0 { return "推进 \(totalUnread) · 互验 \(totalAgentConfirms)" }
        if totalAgentConfirms > 0 { return "Agent 互验中 \(totalAgentConfirms)" }
        if totalTodayUnread > 0 { return "推进中 \(totalTodayUnread) 件" }
        if totalUnread > 0 { return "履约中 \(totalUnread) 件" }
        if isRecentReceiptActive { return "自动闭环完成" }
        return "全员就绪"
    }

    private func shortAgentName(_ raw: String) -> String {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let id = AgentRoster.identity(for: k) { return id.short }
        if k == "lulu" { return "露露" }
        return raw.isEmpty ? "Agent" : raw
    }

    var compactTailText: String {
        if dataUnknown { return "· 收件箱读取失败" }
        if fusedCount > 0 { return "· 待露露终裁" }
        if totalLuluActions > 0 {
            let names = Set(luluActions.compactMap { AgentRoster.identity(for: $0.from.lowercased())?.short })
            let joined = names.isEmpty ? "Agent" : names.sorted().prefix(2).joined(separator: "/")
            return "· 来自 \(joined)"
        }
        if wakeState.effectiveStatus == "running" {
            return "· AGY 自动执行中"
        }
        if totalAgentConfirms > 0 {
            if let first = agentConfirms.first {
                let f = shortAgentName(first.from)
                let t = shortAgentName(first.to)
                return "· \(f)→\(t) 验"
            }
            return "· 自动闭环中"
        }
        if totalTodayUnread > 0 {
            if let top = todayUnreadLeaders.first {
                let extra = todayUnreadLeaders.count > 1 ? " 等" : ""
                return "· \(top.0.short) \(top.1)\(extra)"
            }
        }
        if isRecentReceiptActive {
            let shortT = String(recentReceiptTitle.prefix(10))
            return "· \(shortT)"
        }
        if totalUnread == 0 && harnessState.loaded && (!harnessState.sealOk || harnessState.loopScore < 100) {
            return "· 裁判 \(harnessState.loopScore)分"
        }
        if todayClosedCount > 0 {
            return "· 今日自闭环 \(todayClosedCount) 单"
        }
        return totalUnread > 0 ? "· 免人工" : "· 0 积压"
    }

    var preferredCompactWidth: CGFloat {
        let s = CGFloat(uiScale)
        let len = CGFloat(compactHeadText.count) * (15.5 * s) + CGFloat(compactTailText.count) * (12.0 * s)
        return evenCeil(max(260 * s, min(380 * s, 64 * s + len)))
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
            return CGFloat(((tCount + dCount <= 4) ? 380 : 450) + extra)
        }
        if showSettings { return 756 + extra }
        if showTopology { return 372 + extra }

        // v2.0 紧凑 4 分卡定高（不再拉成 700pt 瀑布流），动态适配红线卡/展开摘要
        var h: CGFloat = 52 // 顶栏 + 内边距
        if fusedCount > 0 || !fusedCards.isEmpty { h += 106 }
        if totalLuluActions > 0 { h += 112 }
        if resumeConfirmPending { h += 36 }
        switch activeTab {
        case .team:
            h += 186
        case .feed:
            let rows = max(1, min(5, recentLoopFeed.count))
            h += CGFloat(rows) * 34 + 62 + (expandedFeedId != nil ? 64 : 0)
        case .opt:
            let rows = max(1, min(4, harnessState.autoChanges.count))
            h += CGFloat(rows) * 48 + 64
        case .topo:
            h += 248
        }
        h += 76 // 底部平等快发栏 + 快捷资产条
        return max(260, h + extra)
    }
    private var timer: Timer?
    private var breathTimer: Timer?
    private var commTimer: Timer?
    private var lastToggleTime: Date = Date.distantPast
    private let refreshLock = NSLock()
    private var isRefreshingInFlight = false
    private var needsFollowupRefresh = false
    
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
            self.drawerSearchText = ""
            self.drawerTodayOnly = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                self.selectedDrawerAgent = agent
            }
            self.onDrawerChange?()
        }
    }

    func toggleRejectTarget(_ file: String?) {
        DispatchQueue.main.async {
            if self.rejectTargetFile == file {
                self.rejectTargetFile = nil
                self.rejectReasonText = ""
            } else {
                self.rejectTargetFile = file
                self.rejectReasonText = ""
            }
            self.onLayoutChange?()
        }
    }
    
    private let preferences: UserDefaults?
    let rootPath: String
    let handoffScript = "/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts/handoff.py"

    init(virtualTest: Bool = false) {
        if virtualTest {
            // 固定的进程内数据；不读取偏好、生产 handoff 或事件源；仅当同时显式传入测试事件源时才轮询脉冲。
            preferences = nil
            let env = ProcessInfo.processInfo.environment
            let customEventLog = env["AGENT_ISLAND_EVENT_LOG"] ?? ""
            let customMultiRoot = env["AGENT_ISLAND_MULTI_ROOT"] ?? ""
            if !customEventLog.isEmpty && !customMultiRoot.isEmpty {
                rootPath = customMultiRoot.hasSuffix("/handoffs") ? customMultiRoot : customMultiRoot + "/handoffs"
            } else {
                rootPath = ""
            }
            if let raw = env["AGENT_ISLAND_TEST_THEME"],
               let mode = ThemeMode(rawValue: raw) {
                themeMode = mode
            }
            if let drawer = env["AGENT_ISLAND_TEST_DRAWER"], !drawer.isEmpty, customMultiRoot.isEmpty {
                let sampleStages: [(String, String, String, String)] = [
                    ("dispatched", "待接单", "超时 42m", "2026-11-22 10:45 +08"),
                    ("relay", "需前台接力", "待前台接力", "2026-11-22 11:02 +08"),
                    ("accepted", "履约中", "滞留 1h", "2026-11-22 10:15 +08"),
                    ("accepted", "履约中", "预计 3 分钟", "2026-11-22 11:20 +08"),
                    ("dispatched", "待接单", "超时 18m", "2026-11-22 11:12 +08"),
                    ("relay", "需前台接力", "待前台接力", "2026-11-22 10:50 +08"),
                    ("accepted", "履约中", "履约推进中", "2026-11-22 11:24 +08"),
                    ("dispatched", "待接单", "", "2026-11-22 11:28 +08"),
                    ("accepted", "履约中", "滞留 2h", "2026-11-22 09:10 +08"),
                    ("dispatched", "待接单", "超时 3h", "2026-11-22 08:20 +08"),
                ]
                let mocked = sampleStages.enumerated().map { idx, spec in
                    TaskItem(
                        file: "sample-\(idx + 1)-20261122.md",
                        from: drawer == "ping" ? "agy" : "ping",
                        to: drawer,
                        date: spec.3,
                        title: "美团闭环抽屉压测工单 #\(idx + 1) · \(spec.1)",
                        stage: spec.0,
                        statusText: spec.1,
                        artifacts: "",
                        eta: spec.2,
                        highlights: "虚拟屏 1x 满载防裁切验收样例：验证顶栏返回/标题/搜索不被挤出视口。"
                    )
                }
                if drawer == "ping" {
                    pingTasks = mocked
                    pingPending = mocked.count
                } else if drawer == "agy" {
                    agyTasks = mocked
                    agyPending = mocked.count
                } else if drawer == "alma" {
                    almaTasks = mocked
                    almaPending = mocked.count
                }
                totalAccepted = mocked.filter { $0.stage == "accepted" || $0.stage == "relay" }.count
                totalDispatched = mocked.filter { $0.stage == "dispatched" }.count
            }
            checkAppearance()
            reloadWakeState(force: true)
            if !customEventLog.isEmpty && !customMultiRoot.isEmpty {
                refreshCommPulses()
                commTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.refreshCommPulses()
                }
            }
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
            let snapped = Self.snapScale(savedScale)
            self.uiScale = snapped
            if abs(snapped - savedScale) > 0.001 {
                preferences?.set(snapped, forKey: "agent_island_ui_scale")
            }
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
            var mergedOrder = savedOrder.filter { PanelSectionKey(rawValue: $0) != nil }
            for missingKey in PanelSectionKey.defaultOrder where !mergedOrder.contains(missingKey) {
                if missingKey == PanelSectionKey.quickSend.rawValue,
                   let assetsIdx = mergedOrder.firstIndex(of: PanelSectionKey.assets.rawValue) {
                    mergedOrder.insert(missingKey, at: assetsIdx)
                } else {
                    mergedOrder.append(missingKey)
                }
            }
            self.sectionOrder = mergedOrder
        }
        if let savedSections = preferences?.dictionary(forKey: "agent_island_sections") as? [String: Bool] {
            var merged = PanelSectionKey.defaults
            for (k, v) in savedSections where merged[k] != nil { merged[k] = v }
            self.enabledSections = merged
        }
        if let rawAssets = preferences?.data(forKey: "agent_island_quick_assets"),
           let decoded = try? JSONDecoder().decode([QuickAssetItem].self, from: rawAssets),
           !decoded.isEmpty {
            self.quickAssets = decoded
        }
        if let savedHover = preferences?.object(forKey: "agent_island_hover_auto_expand") as? Bool {
            self.hoverAutoExpand = savedHover
        }
        if let savedMin = preferences?.object(forKey: "agent_island_minimized_menubar") as? Bool {
            self.minimizedToMenuBar = savedMin
        }
        checkAppearance()
        refreshAll()
        startTimers()
        startWakeStateWatcher()
        startLiveEventWatchers()
    }

    /// 事件驱动实时刷新：监听 Funnel events.log 与三箱/.ack 目录，任何落盘 300ms 防抖后立即刷新
    func startLiveEventWatchers() {
        guard preferences != nil else { return }
        for s in liveWatchSources { s.cancel() }
        liveWatchSources.removeAll()

        let evLogURL = URL(fileURLWithPath: Self.eventLog)
        var paths: [String] = [
            evLogURL.deletingLastPathComponent().path,
            evLogURL.path,
        ]
        if !rootPath.isEmpty {
            for sub in ["agy", "alma", "ping", ".ack"] {
                paths.append("\(rootPath)/\(sub)")
            }
        }
        var seen = Set<String>()
        for path in paths where !path.isEmpty && seen.insert(path).inserted {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .attrib, .delete],
                queue: liveWatchQueue
            )
            src.setEventHandler { [weak self] in
                self?.scheduleLiveRefresh()
            }
            src.setCancelHandler {
                close(fd)
            }
            liveWatchSources.append(src)
            src.resume()
        }
    }

    private func scheduleLiveRefresh() {
        liveDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.refreshCommPulses()
            self.refreshAll()
        }
        liveDebounceWorkItem = work
        liveWatchQueue.asyncAfter(deadline: .now() + 0.30, execute: work)
    }

    private var wakeStateDirURL: URL {
        // 仅测试实例可用 AGENT_ISLAND_STATE_DIR 指向沙箱快照（生产不传就走默认路径）
        if let override = ProcessInfo.processInfo.environment["AGENT_ISLAND_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/alma/state", isDirectory: true)
    }

    func startWakeStateWatcher() {
        reloadWakeState(force: true)
        let dirPath = wakeStateDirURL.path
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }
        wakeDirFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.reloadWakeState(force: false)
        }
        src.setCancelHandler {
            close(fd)
        }
        wakeDirSource = src
        src.resume()
    }

    private static let healthTSFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    func reloadWakeState(force: Bool) {
        let env = ProcessInfo.processInfo.environment
        let snapURL = wakeStateDirURL.appendingPathComponent("island-wake-state.json")
        let pauseURL = wakeStateDirURL.appendingPathComponent("agy-turn.paused")
        let healthURL = env["AGENT_ISLAND_HEALTH_STATE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? wakeStateDirURL.appendingPathComponent("pingloop-health.json")
        let convURL = env["AGENT_ISLAND_CONVERGENCE_LOG"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? wakeStateDirURL.appendingPathComponent("pingloop-convergence.jsonl")
        let almaURL = wakeStateDirURL.appendingPathComponent("alma-turn.json")
        let harnessURL = wakeStateDirURL.appendingPathComponent("pingloop-harness-latest.json")
        let decisionsDirURL = env["AGENT_ISLAND_DECISIONS_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? wakeStateDirURL.appendingPathComponent("a-verifier-decisions", isDirectory: true)
        let pingFuseDirURL = URL(fileURLWithPath: "/Users/l/Nutstore Files/Obsidian_/multi-agent/handoffs/ping", isDirectory: true)

        let fm = FileManager.default
        func fileStat(_ url: URL) -> String {
            let attr = try? fm.attributesOfItem(atPath: url.path)
            let mt = (attr?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let sz = (attr?[.size] as? NSNumber)?.int64Value ?? 0
            return "\(mt):\(sz)"
        }
        let pauseExists = fm.fileExists(atPath: pauseURL.path)
        let verifierFiles = (try? fm.contentsOfDirectory(at: decisionsDirURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?
            .filter { $0.lastPathComponent.hasSuffix("-fused.md") } ?? []
        let fuseMemorialFiles = (try? fm.contentsOfDirectory(at: pingFuseDirURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?
            .filter { $0.lastPathComponent.hasPrefix("escalate-fuse-") && $0.lastPathComponent.hasSuffix(".md") } ?? []
        let decFiles = (verifierFiles + fuseMemorialFiles).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decStat = decFiles.map { "\($0.lastPathComponent)=\(fileStat($0))" }.joined(separator: ",")
        let statKey = "\(fileStat(snapURL))|\(pauseExists)|\(fileStat(healthURL))|\(fileStat(convURL))|\(fileStat(almaURL))|\(fileStat(harnessURL))|\(decStat)"
        if !force && statKey == wakeLastStatKey { return }
        wakeLastStatKey = statKey

        var next = WakeWorkerState()
        next.paused = pauseExists
        if let data = try? Data(contentsOf: snapURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let workers = root["workers"] as? [String: Any],
           let agy = workers["agy"] as? [String: Any] {
            next.status = (agy["status"] as? String) ?? "idle"
            next.dailyRuns = (agy["daily_runs"] as? Int) ?? 0
            next.dailyRunsLimit = (agy["daily_runs_limit"] as? Int) ?? 30
            next.dailyTokens = (agy["daily_tokens"] as? Int) ?? 0
            next.dailyTokensLimit = (agy["daily_tokens_limit"] as? Int) ?? 500_000
            next.lastFile = (agy["file"] as? String) ?? ""
            next.lastAction = (agy["last_action"] as? String) ?? ""
            next.elapsedS = (agy["elapsed_s"] as? Double) ?? 0
            next.loaded = true
        }

        // M4/M5/M6 真实 Δ 与双后台/Verifier 只读快照解析（0 新增轮询）
        var nextDelta = PingloopDeltaState()
        let nowDate = Date()
        let todayMMdd = Self.shortDayFormatter.string(from: nowDate)

        if let hData = try? Data(contentsOf: healthURL),
           let hRoot = try? JSONSerialization.jsonObject(with: hData) as? [String: Any] {
            nextDelta.loaded = true
            nextDelta.verdict = (hRoot["verdict"] as? String) ?? "PASS"
            nextDelta.confirm = (hRoot["confirm"] as? Int) ?? 0
            nextDelta.zombie = (hRoot["zombie"] as? Int) ?? 0
            if let dMap = hRoot["delta"] as? [String: Any] {
                nextDelta.confirmDelta = dMap["confirm"] as? Int
            }
            if let vel = hRoot["velocity"] as? [String: Any] {
                nextDelta.todayConfirmed = (vel[todayMMdd] as? Int) ?? 0
                let vParts = vel.keys.sorted().suffix(4).map { k in
                    "\(k):\(vel[k] as? Int ?? 0)"
                }
                nextDelta.velocityText = vParts.joined(separator: " / ")
            }
            if let mat = hRoot["confirm_matrix"] as? [String: [String: Any]] {
                let mLines = mat.sorted { ($0.value["n"] as? Int ?? 0) > ($1.value["n"] as? Int ?? 0) }
                    .map { (k, v) in
                        let n = v["n"] as? Int ?? 0
                        let med = v["median_h"] as? Double ?? 0
                        return "  \(k): \(n)条 (中位 \(String(format: "%.1f", med))h)"
                    }
                nextDelta.confirmMatrixText = mLines.joined(separator: "\n")
            }
            let hTime: Date = {
                if let tsStr = hRoot["ts"] as? String, let parsed = Self.healthTSFormatter.date(from: tsStr) {
                    return parsed
                }
                let attr = try? fm.attributesOfItem(atPath: healthURL.path)
                return (attr?[.modificationDate] as? Date) ?? Date.distantPast
            }()
            let ageSec = max(0, nowDate.timeIntervalSince(hTime))
            nextDelta.healthAgeMin = Int((ageSec / 60.0).rounded())
            nextDelta.isStale = ageSec > 1800
        }

        if let aData = try? Data(contentsOf: almaURL),
           let aRoot = try? JSONSerialization.jsonObject(with: aData) as? [String: Any] {
            nextDelta.almaLoaded = true
            nextDelta.almaCount = aRoot.count
            var maxTs: Double = 0
            for val in aRoot.values {
                if let item = val as? [String: Any], let ts = item["ts"] as? Double, ts > maxTs {
                    maxTs = ts
                }
            }
            if maxTs > 0 {
                let ageSec = max(0, Int(nowDate.timeIntervalSince1970 - maxTs))
                if ageSec < 60 {
                    nextDelta.almaAgeText = "刚刚"
                } else if ageSec < 3600 {
                    nextDelta.almaAgeText = "\(ageSec / 60)m前"
                } else if ageSec < 86400 {
                    nextDelta.almaAgeText = "\(ageSec / 3600)h前"
                } else {
                    nextDelta.almaAgeText = "待命"
                }
            } else {
                nextDelta.almaAgeText = "待命"
            }
        }

        if let cData = try? Data(contentsOf: convURL),
           let cText = String(data: cData, encoding: .utf8) {
            var allRows: [[String: Any]] = []
            for rawLine in cText.split(separator: "\n") {
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if let obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] {
                    allRows.append(obj)
                }
            }
            let enforceRows = allRows.filter { ($0["mode"] as? String) == "enforce" }
            let metricRows = enforceRows.isEmpty ? allRows : enforceRows
            if !metricRows.isEmpty {
                nextDelta.convTotal = metricRows.count
                let passRows = metricRows.filter {
                    let oc = ($0["outcome"] as? String) ?? ""
                    return oc == "confirmed" || oc == "observe_pass"
                }
                nextDelta.convConfirmed = passRows.count
                let roundSum = metricRows.reduce(0) { $0 + (($1["rounds_to_converge"] as? Int) ?? 1) }
                nextDelta.convMeanRounds = Double(roundSum) / Double(metricRows.count)
                let firstPass = passRows.filter { (($0["rounds_to_converge"] as? Int) ?? 0) == 1 }.count
                nextDelta.convFirstPassPct = Double(firstPass) * 100.0 / Double(metricRows.count)
            }
        }

        var nextCards: [FusedDecisionCard] = []
        for url in decFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var title = url.deletingPathExtension().lastPathComponent
            var summary = "连续 3 轮 A 级机检未收敛，已升级 B 级决策卡"
            for rawLn in text.split(separator: "\n") {
                let ln = String(rawLn).trimmingCharacters(in: .whitespacesAndNewlines)
                if ln.hasPrefix("# ") {
                    title = String(ln.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if ln.contains("一句话定什么") {
                    if let idx = ln.range(of: "**：") {
                        summary = String(ln[idx.upperBound...]).trimmingCharacters(in: .whitespaces)
                    } else {
                        summary = ln.replacingOccurrences(of: "- ", with: "")
                    }
                    summary = summary.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "")
                    break
                }
            }
            let tid = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-fused", with: "")
            nextCards.append(FusedDecisionCard(traceId: tid, title: title, summary: summary, path: url.path))
        }

        var nextHarness = SelfHarnessState()
        if let hrData = try? Data(contentsOf: harnessURL),
           let hrRoot = try? JSONSerialization.jsonObject(with: hrData) as? [String: Any] {
            nextHarness.loaded = true
            nextHarness.sealOk = (hrRoot["seal_ok"] as? Bool) ?? true
            let upTs = (hrRoot["updated_ts"] as? Double) ?? ((hrRoot["updated_ts"] as? Int).map(Double.init) ?? 0)
            if upTs > 0 {
                let ageM = max(0, Int((nowDate.timeIntervalSince1970 - upTs) / 60.0))
                nextHarness.ageMin = ageM
                nextHarness.isStale = ageM > 30
            } else {
                nextHarness.isStale = false
            }
            if let smk = hrRoot["smoke_gate"] as? [String: Any] {
                nextHarness.loopScore = (smk["loop_score"] as? Int) ?? 100
                nextHarness.smokePassed = (smk["passed"] as? Int) ?? 6
                nextHarness.smokeTotal = (smk["total"] as? Int) ?? 6
            }
            if let tm = hrRoot["timing"] as? [String: Any] {
                nextHarness.totalWallMin = (tm["total_wall_min"] as? Double) ?? 0
                nextHarness.effectiveExecMin = (tm["effective_exec_min"] as? Double) ?? 0
                nextHarness.overheadLossMin = (tm["overhead_loss_min"] as? Double) ?? 0
                nextHarness.effectivePct = (tm["effective_pct"] as? Double) ?? 100
                nextHarness.ticketsMeasured = (tm["tickets_measured"] as? Int) ?? 0
            }
            if let props = hrRoot["proposals"] as? [[String: Any]] {
                nextHarness.proposals = props.map { p in
                    HarnessProposalItem(
                        signature: (p["signature"] as? String) ?? "UNKNOWN",
                        distinctSessions: (p["distinct_sessions"] as? Int) ?? 1,
                        rawHits: (p["raw_hits"] as? Int) ?? 1,
                        carrier: (p["carrier"] as? String) ?? "",
                        recommendedFix: (p["recommended_fix"] as? String) ?? "",
                        shadowVerified: (p["shadow_verified"] as? Bool) ?? false,
                        patchReportPath: (p["patch_report_path"] as? String) ?? ""
                    )
                }
            }
            if let changes = hrRoot["auto_changes"] as? [[String: Any]] {
                nextHarness.autoChanges = changes.map { c in
                    HarnessAutoChangeItem(
                        signature: (c["signature"] as? String) ?? "",
                        kind: (c["kind"] as? String) ?? "observing",
                        badge: (c["badge"] as? String) ?? "观察中",
                        title: (c["title"] as? String) ?? "",
                        change: (c["change"] as? String) ?? "",
                        sessions: (c["sessions"] as? Int) ?? 0,
                        carrier: (c["carrier"] as? String) ?? ""
                    )
                }
            }
        }

        DispatchQueue.main.async {
            if self.wakeState != next {
                self.wakeState = next
            }
            if self.deltaState != nextDelta {
                self.deltaState = nextDelta
            }
            if self.fusedCards != nextCards {
                self.fusedCards = nextCards
                self.onLayoutChange?()
            }
            if self.harnessState != nextHarness {
                let layoutDiff = self.harnessState.loaded != nextHarness.loaded || self.harnessState.proposals.count != nextHarness.proposals.count
                self.harnessState = nextHarness
                if layoutDiff {
                    self.onLayoutChange?()
                }
            }
        }
    }

    /// 「恢复」一次最多重放多少张积压单。默认 1；只有用户在二次确认里显式选「全部」才放宽。
    static let resumeBacklogDefault = 1
    static let resumeBacklogUnbounded = 0

    /// 点「暂停」直接生效（停下来的动作不该被确认框延迟）；
    /// 点「恢复」要先二次确认——恢复会真的把积压单以全权限重放一遍。
    func toggleAgyWakePaused() {
        if pauseMarkerExists {
            beginResumeConfirmation()
        } else {
            applyPause()
        }
    }

    private var pauseMarkerExists: Bool {
        FileManager.default.fileExists(
            atPath: wakeStateDirURL.appendingPathComponent("agy-turn.paused").path
        )
    }

    private func applyPause() {
        let pauseURL = wakeStateDirURL.appendingPathComponent("agy-turn.paused")
        let fm = FileManager.default
        try? fm.createDirectory(at: wakeStateDirURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? ("paused_by_agent_island: \(stamp)\n").data(using: .utf8)?.write(to: pauseURL, options: .atomic)
        reloadWakeState(force: true)
    }

    /// 恢复前二次确认的文案。只讲「会重放几张」，上限恒为 1，不提供「重放全部」选项。
    static func resumeConfirmationText(backlogCount: Int) -> String {
        let queueLine = backlogCount > 0
            ? "队列里还有 \(backlogCount) 张未接单的积压单"
            : "队列里没有未接单的积压单"
        return "恢复只重放队首 \(resumeBacklogDefault) 张（全权限、不限预算），不会把整队一起重跑。\(queueLine)。"
    }

    /// 二次确认就地弹在灵动岛里。不用 NSAlert：系统模态框会跑到物理主屏，违反「测试窗一律上副屏」。
    func beginResumeConfirmation() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.resumeConfirmBacklog = Self.backlogCount()
            self.resumeConfirmPending = true
        }
    }

    func cancelResumeConfirmation() {
        DispatchQueue.main.async { [weak self] in self?.resumeConfirmPending = false }
    }

    /// 点了「只重放 N 张」才真正动：上限恒为 resumeBacklogDefault，与积压数量无关。
    func confirmResume() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.resumeConfirmPending = false
            self.resume(maxBacklog: Self.resumeBacklogDefault)
        }
    }

    /// 只数「未接单/待整改」的积压单，口径与 agy-turn.py `_scan_backlog_files()` 对齐（0 额外模型调用）。
    static func backlogCount() -> Int {
        let agyDir = URL(fileURLWithPath: Self.multiRootPath, isDirectory: true)
            .appendingPathComponent("handoffs", isDirectory: true)
            .appendingPathComponent("agy", isDirectory: true)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: agyDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for f in files where f.pathExtension.lowercased() == "md" {
            let name = f.lastPathComponent.lowercased()
            if name.range(of: #"-(accept|reply)(\d+|-(reply|confirm)(\d+)?)*\.md$"#, options: .regularExpression) != nil { continue }
            if Self.backlogClaims(name) { continue }
            count += 1
        }
        return count
    }

    /// 已被接单/已在履约中的单不算积压（对齐 `_already_claimed` 的三类判据）。
    static func backlogClaims(_ fileName: String) -> Bool {
        let agyDir = URL(fileURLWithPath: Self.multiRootPath, isDirectory: true)
            .appendingPathComponent("handoffs", isDirectory: true)
            .appendingPathComponent("agy", isDirectory: true)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: agyDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let stem = (fileName as NSString).deletingPathExtension
        for f in files {
            let other = f.lastPathComponent.lowercased()
            if other.hasPrefix("\(stem.lowercased())-accept") || other.hasPrefix("\(stem.lowercased())-reply") { return true }
        }
        // 原单自身 status 已推进（履约中/需前台接力/待确认/已完成）时也不该重放
        let doc = agyDir.appendingPathComponent(fileName)
        guard let head = try? String(contentsOf: doc, encoding: .utf8).prefix(1600) else { return false }
        for line in head.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("status:") {
                let st = s.replacingOccurrences(of: "status:", with: "").trimmingCharacters(in: .whitespaces)
                return !["待办", "待处理", "待接单", "待执行", "待整改"].contains(st)
            }
        }
        return false
    }

    func resumeForSelfTest(maxBacklog: Int) { resume(maxBacklog: maxBacklog) }

    func stateDirForSelfTest() -> URL { wakeStateDirURL }
    func reloadWakeStateForSelfTest() { reloadWakeState(force: true) }

    private func resume(maxBacklog: Int) {
        let pauseURL = wakeStateDirURL.appendingPathComponent("agy-turn.paused")
        let fm = FileManager.default
        try? fm.removeItem(at: pauseURL)
        reloadWakeState(force: true)
        guard maxBacklog > 0 else { return }
        // 用量与重放结果只进日志 + 灵动岛反馈，不再静默（上次一点就把 3 张旧单全重跑，无法回溯）
        // 自测可把脚本换成记录 argv 的桩（AGENT_ISLAND_AGYTURN_SCRIPT），生产不传就走上游脚本
        let script = ProcessInfo.processInfo.environment["AGENT_ISLAND_AGYTURN_SCRIPT"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/Users/l/.config/alma/scripts/agy-turn.py"
        var args = [script, "--resume-backlog", "--max-backlog", "\(maxBacklog)"]
        // 自测专用：把同一串参数加 --dry-run 跑一遍，证明参数确实这么传、但不真重放工单。
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_RESUME_DRYRUN"] == "1" { args.append("--dry-run") }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = args
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            let data = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            Self.appendResumeLog(args: args, output: text)
            let queued = Self.parseResumeCount(text)
            DispatchQueue.main.async {
                self?.showToast("已恢复唤醒 · 重放上限 \(maxBacklog) 张\(queued >= 0 ? "（实际排队 \(queued) 张）" : "")")
                self?.refreshAll()
            }
        }
    }

    static func parseResumeCount(_ output: String) -> Int {
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return -1 }
        if let c = root["count"] as? Int { return c }
        if let results = root["results"] as? [[String: Any]] { return results.count }
        return -1
    }

    static func appendResumeLog(args: [String], output: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] args=\(args.joined(separator: " "))"
            + " out=\(output.replacingOccurrences(of: "\n", with: " ").prefix(600))\n"
        // 测试实例用 AGENT_ISLAND_STATE_DIR 指沙箱，别把自测记录写进生产 state
        let stateDir = ProcessInfo.processInfo.environment["AGENT_ISLAND_STATE_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/alma/state", isDirectory: true)
        let logURL = stateDir.appendingPathComponent("island-resume.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8) ?? Data()); try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL)
        }
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
        let snapped = Self.snapScale(value)
        DispatchQueue.main.async {
            self.uiScale = snapped
            self.preferences?.set(snapped, forKey: "agent_island_ui_scale")
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

    func setHoverAutoExpand(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.hoverAutoExpand = enabled
            self.preferences?.set(enabled, forKey: "agent_island_hover_auto_expand")
        }
    }

    func setMinimizedToMenuBar(_ minimized: Bool) {
        DispatchQueue.main.async {
            self.minimizedToMenuBar = minimized
            self.preferences?.set(minimized, forKey: "agent_island_minimized_menubar")
            self.onMinimizeChange?(minimized)
        }
    }

    /// 面板实际明暗：曜石深色皮肤无论系统模式如何，都使用深色表面与浅色文字
    var panelIsDark: Bool {
        isDarkMode || skin == .obsidian
    }

    func isSectionEnabled(_ key: String) -> Bool {
        enabledSections[key] ?? (PanelSectionKey.defaults[key] ?? true)
    }

    func toggleSection(_ key: String) {
        DispatchQueue.main.async {
            guard PanelSectionKey(rawValue: key) != nil else { return }
            self.enabledSections[key] = !self.isSectionEnabled(key)
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
        // 主刷新已由 startLiveEventWatchers() 毫秒级事件驱动；保留 10s 低频兜底防漏
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkAppearance()
            self?.refreshAll()
        }
        breathTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pulse.toggle()
            }
        }
        refreshCommPulses()
        commTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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
    static var multiRootPath: String { multiRoot }
    private static let eventLog = ProcessInfo.processInfo.environment["AGENT_ISLAND_EVENT_LOG"]
        ?? "/Users/l/.local/funnel-sync/events.log"

    private static func isSyntheticTestPath(_ path: String) -> Bool {
        let low = path.lowercased()
        let base = (low as NSString).lastPathComponent
        if base.hasPrefix("cc-test-") || base.hasPrefix("cc-cc-test-") || base.contains("selftest") {
            return true
        }
        let exact: Set<String> = ["self.md", "self-alma.md", "dispatch-replied.md", "split-quoted-step.md"]
        return exact.contains(base)
    }

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
            var latestOverall: (from: String, to: String, when: Date)? = nil

            func considerOverall(_ from: String, _ to: String, _ when: Date) {
                if let cur = latestOverall {
                    if when > cur.when {
                        latestOverall = (from, to, when)
                    }
                } else {
                    latestOverall = (from, to, when)
                }
            }

            // 主源：Funnel 443 写入事件与 handoff.py 自动 STEP 节点事件（不认 HEARTBEAT）
            if let data = FileManager.default.contents(atPath: Self.eventLog),
               let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n").suffix(240) {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                          let d = obj as? [String: Any],
                          let act = d["action"] as? String,
                          (act == "PUT" || act == "STEP"),
                          let path = d["path"] as? String,
                          path.hasPrefix("handoffs/"),
                          !Self.isSyntheticTestPath(path),
                          let raw = d["time"] as? String,
                          let when = self.parseEventTime(raw) else { continue }
                    if act == "STEP",
                       let f = (d["actor"] as? String)?.lowercased(),
                       let t = (d["to"] as? String)?.lowercased(),
                       AgentRoster.identity(for: f) != nil,
                       AgentRoster.identity(for: t) != nil,
                       f != t {
                        considerOverall(f, t, when)
                        if when >= cutoff {
                            hits.append((f, t, when))
                        }
                    } else {
                        let url = URL(fileURLWithPath: Self.multiRoot).appendingPathComponent(path)
                        if let (from, to) = self.handoffEndpoints(at: url) {
                            considerOverall(from, to, when)
                            if when >= cutoff {
                                hits.append((from, to, when))
                            }
                        }
                    }
                }
            }

            // 兜底与全局最近一笔通讯：扫描三箱按 mtime 降序前 8 条非路由文件
            if !self.rootPath.isEmpty {
                let fm = FileManager.default
                let wasHitsEmpty = hits.isEmpty
                for box in AgentRoster.all.map({ $0.key }) {
                    let dir = URL(fileURLWithPath: self.rootPath).appendingPathComponent(box)
                    guard let files = try? fm.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    let candidates: [(URL, Date)] = files.compactMap { url in
                        let ext = url.pathExtension.lowercased()
                        let name = url.lastPathComponent
                        guard ext == "md" || ext == "txt" else { return nil }
                        guard !name.hasPrefix("pingloop-route-"), !name.hasPrefix("cancel-") else { return nil }
                        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return (url, mtime)
                    }.sorted { $0.1 > $1.1 }

                    for (url, mtime) in candidates.prefix(8) {
                        guard let (from, to) = self.handoffEndpoints(at: url) else { continue }
                        considerOverall(from, to, mtime)
                        if wasHitsEmpty && mtime >= cutoff {
                            hits.append((from, to, mtime))
                        }
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
            let finalLastAt = pulses.map { $0.lastAt }.max() ?? latestOverall?.when
            var finalRoute = ""
            if let top = pulses.first {
                let s = AgentRoster.identity(for: top.source)?.short ?? top.source.uppercased()
                let t = AgentRoster.identity(for: top.target)?.short ?? top.target.uppercased()
                finalRoute = "\(s) → \(t)"
            } else if let ov = latestOverall {
                let s = AgentRoster.identity(for: ov.from)?.short ?? ov.from.uppercased()
                let t = AgentRoster.identity(for: ov.to)?.short ?? ov.to.uppercased()
                finalRoute = "\(s) → \(t)"
            }

            DispatchQueue.main.async {
                self.activePulses = pulses
                self.lastCommAt = finalLastAt
                self.lastCommRoute = finalRoute
            }
        }
    }
    
    func refreshAll(showFeedback: Bool = false) {
        guard preferences != nil else { return }
        refreshLock.lock()
        if isRefreshingInFlight {
            needsFollowupRefresh = true
            refreshLock.unlock()
            return
        }
        isRefreshingInFlight = true
        needsFollowupRefresh = false
        refreshLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer {
                self.refreshLock.lock()
                self.isRefreshingInFlight = false
                let runAgain = self.needsFollowupRefresh
                self.needsFollowupRefresh = false
                self.refreshLock.unlock()
                if runAgain {
                    self.refreshAll()
                }
            }
            
            let snapshot = self.fetchInboxesJSON()
            self.reloadWakeState(force: true)
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
                if showFeedback {
                    self.showToast(dataOK ? "🔄 已刷新最新状态" : "⚠️ 刷新失败（数据未知）")
                }

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
                let luluArr = data["lulu_actions"] ?? []
                let agentConfirmArr = data["agent_confirms"] ?? []
                let confirms = data["pending_confirms"] ?? (luluArr + agentConfirmArr)

                self.pingTasks = pingArr
                self.agyTasks = agyArr
                self.almaTasks = almaArr
                self.luluActions = luluArr
                self.agentConfirms = agentConfirmArr
                self.pendingConfirms = confirms
                
                self.pingDoneTasks = data["ping_done"] ?? []
                self.agyDoneTasks = data["agy_done"] ?? []
                self.almaDoneTasks = data["alma_done"] ?? []
                
                self.pingPending = pingArr.count
                self.agyPending = agyArr.count
                self.almaPending = almaArr.count
                
                let allActive = pingArr + agyArr + almaArr
                self.totalLuluActions = luluArr.count
                self.totalAgentConfirms = agentConfirmArr.count
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
                if let statItem = data["__today_stats__"]?.first {
                    let newCnt = Int(statItem.file) ?? 0
                    let latestTitle = statItem.title
                    if self.prevTodayClosedCount >= 0 && newCnt > self.prevTodayClosedCount && !latestTitle.isEmpty {
                        self.recentReceiptTitle = latestTitle
                        self.recentReceiptAt = Date()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 31.0) { [weak self] in
                            self?.onLayoutChange?()
                        }
                    }
                    self.prevTodayClosedCount = newCnt
                    self.todayClosedCount = newCnt
                }
                if let feedArr = data["__loop_feed__"] {
                    self.recentLoopFeed = feedArr.map { it in
                        LoopFeedItem(
                            time: it.date,
                            title: it.title,
                            route: it.from,
                            duration: it.eta,
                            summary: it.highlights.isEmpty ? it.statusText : it.highlights,
                            path: it.file,
                            isGreen: it.stage == "confirmed"
                        )
                    }
                }
                
                let currentTotal = pingArr.count + agyArr.count + almaArr.count
                let prevTotal = self.lastKnownTotalPending
                if prevTotal >= 0 && currentTotal > prevTotal {
                    let lead = self.unreadLeaders.first
                    let hint = self.hoverAutoExpand ? "靠近或点击展开" : "点击展开"
                    self.triggerNotification(
                        title: "📩 \(currentTotal - prevTotal) 件新未读",
                        subtitle: lead.map { "\($0.0.title) 收件箱 \($0.1) 件未读 · \(hint)" } ?? hint
                    )
                }
                self.lastKnownTotalPending = currentTotal

                let prevLulu = self.lastKnownLuluActions
                if prevLulu >= 0 && luluArr.count > prevLulu {
                    let from = luluArr.first?.from ?? "Agent"
                    self.triggerNotification(
                        title: "🔔 \(luluArr.count) 件待你拍板",
                        subtitle: "\(from) 等待露露确认 · 点击查看"
                    )
                }
                self.lastKnownLuluActions = luluArr.count
                self.lastKnownSubmitted = confirms.count

                // 收起态单行摘要随数据变化，窗口宽度需同步，避免文字溢出
                if case .compact = self.currentMode {
                    self.onLayoutChange?()
                }
            }
        }
    }
    
    func showToast(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring()) {
                self.reconcileFeedback = message
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
                guard let self = self else { return }
                if self.reconcileFeedback == message {
                    withAnimation { self.reconcileFeedback = nil }
                }
            }
        }
    }

    func copyToClipboard(_ text: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        showToast("📋 已复制 \(label)")
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
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var ok = false
            do {
                try p.run()
                _ = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                ok = (p.terminationStatus == 0)
            } catch {}
            self.refreshAll()
            self.showToast(ok ? "✅ 已验收结案" : "⚠️ 验收权限或状态受阻")
        }
    }

    func rejectTask(file: String, dispatcher: String, reason: String) {
        guard preferences != nil else { return }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmed.isEmpty ? "灵动岛退回整改，请核对后重交" : trimmed
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [
                self.handoffScript,
                "reject",
                "--from", dispatcher,
                "--to-file", file,
                "--reason", finalReason
            ]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var ok = false
            do {
                try p.run()
                _ = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                ok = (p.terminationStatus == 0)
            } catch {}
            DispatchQueue.main.async {
                if ok {
                    self.rejectTargetFile = nil
                    self.rejectReasonText = ""
                    self.onLayoutChange?()
                }
            }
            self.refreshAll()
            self.showToast(ok ? "↩️ 已打回整改" : "⚠️ 打回失败，请检查权限")
        }
    }

    func runObserveVerify(file: String) {
        guard preferences != nil, !rootPath.isEmpty else { return }
        showToast("🔍 正在独立机检...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fullPath = file.hasPrefix("/") ? file : "\(self.rootPath)/\(file)"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [
                "/Users/l/.config/alma/scripts/pingloop-a-verifier.py",
                "--file", fullPath,
                "--mode", "observe",
                "--json"
            ]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var summary = "机检异常"
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let dec = (obj["decision"] as? String) ?? ""
                    switch dec {
                    case "observe_pass":
                        let passed = (obj["assertions_passed"] as? Int) ?? 0
                        let total = (obj["assertions_total"] as? Int) ?? 0
                        summary = "机检通过(\(passed)/\(total))"
                    case "route_b":
                        let reason = (obj["reason"] as? String) ?? "人工"
                        summary = reason == "no_submit_assertions" ? "B级无断言 · 需人工" : "B级 · 需人工复核"
                    case "fused", "fused_already":
                        summary = "M1熔断"
                    default:
                        summary = "机检不通过"
                    }
                }
            } catch {}
            DispatchQueue.main.async {
                self.observeResults[file] = summary
            }
            self.showToast("🧪 机检结果：\(summary)")
        }
    }

    func markTaskRead(box: String, file: String) {
        guard preferences != nil, !rootPath.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ackDir = URL(fileURLWithPath: self.rootPath).appendingPathComponent(".ack", isDirectory: true)
            let ackURL = ackDir.appendingPathComponent("\(box).json")
            try? FileManager.default.createDirectory(at: ackDir, withIntermediateDirectories: true)
            var dict: [String: String] = [:]
            if let data = try? Data(contentsOf: ackURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                dict = obj
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
            dict[file] = "read_on_island: \(stamp)"
            if let outData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? outData.write(to: ackURL, options: .atomic)
            }
            self.refreshAll()
            self.showToast("✅ 已标已读")
        }
    }

    private func saveQuickAssets() {
        if let data = try? JSONEncoder().encode(quickAssets) {
            preferences?.set(data, forKey: "agent_island_quick_assets")
        }
    }

    func addQuickAsset(label: String, path: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let expandedPath = NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !trimmedLabel.isEmpty, !expandedPath.isEmpty else {
            showToast("请填写名称与路径")
            return
        }
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir)
        let icon: String
        if expandedPath.hasPrefix("http://") || expandedPath.hasPrefix("https://") {
            icon = "globe"
        } else {
            icon = isDir.boolValue ? "folder.fill" : "doc.text.fill"
        }
        let item = QuickAssetItem(id: UUID().uuidString, label: trimmedLabel, icon: icon, path: expandedPath)
        DispatchQueue.main.async {
            self.quickAssets.append(item)
            self.newAssetLabel = ""
            self.newAssetPath = ""
            self.saveQuickAssets()
            self.showToast("已添加资产：\(trimmedLabel)")
        }
    }

    func removeQuickAsset(id: String) {
        DispatchQueue.main.async {
            self.quickAssets.removeAll { $0.id == id }
            self.saveQuickAssets()
        }
    }

    func resetQuickAssets() {
        DispatchQueue.main.async {
            self.quickAssets = QuickAssetItem.defaults
            self.saveQuickAssets()
            self.showToast("已恢复 5 项默认资产")
        }
    }

    func quickSendMessage() {
        let body = quickSendText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences != nil, !quickSendBusy, !body.isEmpty else { return }
        let target = quickSendTarget
        let df = DateFormatter()
        df.dateFormat = "HHmmss"
        let slug = "island-msg-\(df.string(from: Date()))"
        let title = String(body.prefix(24))
        DispatchQueue.main.async {
            self.quickSendBusy = true
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [
                self.handoffScript,
                "send",
                "--from", "lulu",
                "--to", target,
                "--slug", slug,
                "--title", title,
                "--body", body
            ]
            if let rootEnv = ProcessInfo.processInfo.environment["HANDOFFS_ROOT"], !rootEnv.isEmpty {
                var env = ProcessInfo.processInfo.environment
                env["HANDOFFS_ROOT"] = rootEnv
                p.environment = env
            }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var ok = false
            var t1 = false
            var errMsg = "发送失败"
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    ok = (obj["ok"] as? Bool) ?? false
                    t1 = (obj["t1_verified"] as? Bool) ?? false
                    if let err = obj["error"] as? String, !err.isEmpty { errMsg = err }
                } else {
                    ok = (p.terminationStatus == 0)
                }
            } catch {
                errMsg = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.quickSendBusy = false
                if ok {
                    self.quickSendText = ""
                }
            }
            if ok {
                self.refreshAll()
                self.showToast("📤 已发给 \(target.uppercased())\(t1 ? " (T1✓)" : "")")
            } else {
                self.showToast("⚠️ \(errMsg)")
            }
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
            p.standardError = FileHandle.nullDevice
            var outputData = Data()
            do {
                try p.run()
                outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
            } catch {}
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
import sys, json, os, re, time
from pathlib import Path
sys.path.insert(0, '/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/multi-agent-handoff/scripts')
import handoff, handoff_consts

boxes = ['ping', 'agy', 'alma']
ROOT = handoff.HANDOFFS_ROOT



TERMINAL_STATUSES = ('已完成', '作废', '已关闭', '已核销', '参考', '已结案', '已确认', '已办', '已回复', '已交付', '已结算', '通知', '已撤回', '已阅知')

def is_term_status(st):
    s = str(st or '').strip()
    return handoff_consts.is_terminal(s) or any(c in s for c in TERMINAL_STATUSES)

def is_synthetic_test_name(name):
    low = str(name or '').rsplit('/', 1)[-1].lower()
    if low.startswith('cc-test-') or low.startswith('cc-cc-test-') or 'selftest' in low:
        return True
    return low in ('self.md', 'self-alma.md', 'dispatch-replied.md', 'split-quoted-step.md')

def clean_title(t):
    t = re.sub(r'(\\*\\*|__|`)', '', str(t or ''))
    return re.sub(r'\\s+', ' ', t).strip()

all_acked_bases = set()
closed_traces = set()
closed_files = set()
for b in boxes + ['lulu']:
    for k in handoff.load_ack(b).keys():
        closed_files.add(k)
        closed_files.add(Path(k).stem)
        b_stem = k.replace('.md', '').split('-reply')[0].split('-audit')[0].split('-submit')[0]
        all_acked_bases.add(b_stem)

# Phase 1: Global reply & closed index across all boxes (prevents cross-box blindspots)
global_replied = set()
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    acked_b = handoff.load_ack(b)
    for p in b_dir.iterdir():
        if not p.is_file() or handoff.is_ignored_file(p): continue
        try:
            txt = p.read_text(encoding='utf-8', errors='replace')
            meta, _ = handoff.parse_frontmatter(txt)
        except Exception:
            txt, meta = '', {}
        st = str(meta.get('status', '')).strip()
        tid = str(meta.get('trace_id', '')).strip()
        is_step4_terminal = (
            '【Step 4 终审' in txt
            or '【Step 4a' in txt
            or '核验 + 确认' in txt
            or '核验+确认' in txt
            or '已确认结案' in txt
        )
        is_cc_or_notice = (st in ('通知', '参考', '已阅知') or p.name.startswith(('cc-', 'receipt-')))
        is_doc_closed = (
            (st != '待整改')
            and (not is_cc_or_notice)
            and (
                is_term_status(st)
                or '-confirm' in p.name
                or p.name in acked_b
                or is_step4_terminal
            )
        )
        if is_doc_closed:
            if tid and tid not in ('none', '-'):
                closed_traces.add(tid)
            closed_files.add(p.name)
            closed_files.add(p.stem)
            rt = str(meta.get('reply_to', '')).strip()
            if rt and rt != 'none':
                closed_files.add(Path(rt).name)
                closed_files.add(Path(rt).stem)
            rel = meta.get('related', [])
            if isinstance(rel, list):
                for item in rel:
                    closed_files.add(Path(str(item)).name)
                    closed_files.add(Path(str(item)).stem)

        if handoff.REPLY_RE.search(p.name) or p.name.startswith('cancel-') or '-accept' in p.name or '-confirm' in p.name:
            base = handoff.re.sub(r'-(reply\\d*|accept\\d*|confirm\\d*)\\.md$', '.md', p.name, flags=handoff.re.IGNORECASE)
            base_clean = re.sub(r'-reply\\d*$', '', base.replace('.md', '')) + '.md'
            global_replied.add(base)
            global_replied.add(base_clean)
            global_replied.add(p.stem)
            global_replied.add(p.name)
            rt = str(meta.get('reply_to', '')).strip()
            if rt and rt != 'none':
                global_replied.add(Path(rt).name)
                global_replied.add(Path(rt).stem)
            rel = meta.get('related', [])
            if isinstance(rel, list):
                for item in rel:
                    global_replied.add(Path(str(item)).name)
                    global_replied.add(Path(str(item)).stem)

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
        has_closed = any(any(c in str(meta.get('status', '')) for c in TERMINAL_STATUSES) for _, meta, _ in files)
        is_cross_closed = (tid in closed_traces) or any(p.name in closed_files or p.stem in closed_files for p, _, _ in files)

        if is_acked or has_confirm or has_closed or is_cross_closed:
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
        # 过滤无实名收发头的纯资料/附件文档
        if not orig_frm and not orig_to:
            continue
        # 严格责任边界：收件人不是本箱的（如抄送件、外发件），严禁算作本箱待办！
        if orig_to and orig_to != box:
            continue
        # 升级拍板信（escalate-highrisk-*）由发起方/露露拍板，严禁算作 Ping 自己的待办！
        if box == 'ping' and latest_p.name.startswith('escalate-highrisk-'):
            continue
        # 只有原单自身就是外发单且非发给当前信箱时才过滤；收到派单并签署 -accept 属于正常履约中，严禁过滤！
        if orig_frm == box and orig_to != box:
            continue

        full_txt = latest_p.read_text(encoding='utf-8', errors='replace')
        cur_status = str(latest_meta.get('status', '待办')).strip()
        is_step4_terminal = (
            '【Step 4 终审' in full_txt
            or '【Step 4a' in full_txt
            or '核验 + 确认' in full_txt
            or '核验+确认' in full_txt
            or '已确认结案' in full_txt
        )
        if cur_status != '待整改' and is_step4_terminal:
            continue

        head_lines = full_txt.splitlines()[:140]
        has_inline_step2 = ('【Step 2' in full_txt) or any(ln.lstrip().startswith('##') and 'Step 2' in ln for ln in head_lines)
        # 严格从高阶段往低阶段判：待整改/高危拍板/已交付(Step 3/待确认)优先于旧 Step 2/接力，防止打回后被旧标记遮蔽！
        if cur_status == '待整改':
            stage = 'rework'
            status_text = '待整改'
            total_dispatched += 1
            eta = '打回待整改'
        elif cur_status == '需高危拍板' or '【Step 2.5 需高危拍板】' in full_txt:
            stage = 'high-risk-blocked'
            status_text = '需高危拍板'
            total_accepted += 1
            eta = '高危待拍板'
        elif cur_status in ('待确认', '交付待确认') or ('【Step 3' in full_txt) or any((handoff.REPLY_RE.search(p.name) or '-reply' in p.name.lower()) for p, _, _ in files):
            # 关键分流：待确认与 *-reply*.md 回信属于发起方闭环待验收（Phase 3），严禁混入各 agent 的真待办抽屉！
            continue
        elif all('-accept' in p.name.lower() for p, _, _ in files):
            # 纯接单回执（*-accept*.md）属于告知类，不计入收件方真待办
            continue
        elif cur_status == '需前台接力' or '【Step 2.5 需前台接力】' in full_txt:
            stage = 'relay'
            status_text = '需前台接力'
            total_accepted += 1
            eta = '待前台接力'
        elif cur_status in ('履约中', '进行中') or any('-accept' in p.name for p, _, _ in files) or has_inline_step2:
            stage = 'accepted'
            status_text = '履约中'
            total_accepted += 1
            eta = str(latest_meta.get('eta', '履约推进中'))
        else:
            stage = 'dispatched'
            status_text = '待接单'
            total_dispatched += 1
            eta = ''

        age_sec = max(0, time.time() - latest_p.stat().st_mtime)
        if stage == 'dispatched' and age_sec >= 900:
            hrs = int(age_sec // 3600)
            eta = f'超时 {hrs}h' if hrs >= 1 else f'超时 {int(age_sec // 60)}m'
        elif stage == 'accepted' and age_sec >= 1800 and (not eta or eta == '履约推进中'):
            hrs = int(age_sec // 3600)
            eta = f'滞留 {hrs}h' if hrs >= 1 else f'滞留 {int(age_sec // 60)}m'

        items.append({
            'file': latest_p.name,
            'from': str(latest_meta.get('from', '未知')),
            'to': str(latest_meta.get('to', box)),
            'date': str(latest_meta.get('date', '-')),
            'title': clean_title(handoff.first_heading(latest_body) or latest_p.stem),
            'mtime': latest_p.stat().st_mtime,
            'stage': stage,
            'statusText': status_text,
            'artifacts': str(latest_meta.get('artifacts', '')),
            'eta': eta,
            'highlights': handoff.extract_highlights(full_txt)
        })

    items.sort(key=lambda x: x['mtime'], reverse=True)
    res[box] = items

# Phase 3: Pending Confirmations (与 handoff_backlog_audit.py / handoff._resolve_confirm_roles 100% 同源)
# 严格拆分：lulu_actions（真正需露露本人验收/高危拍板） vs agent_confirms（Agent 之间自动互验闭环）
lulu_raw = []
agent_raw = []
for b in boxes:
    b_dir = ROOT / b
    if not b_dir.is_dir(): continue
    acked_box = handoff.load_ack(b)
    all_b_files = [p for p in b_dir.iterdir() if p.is_file() and not handoff.is_ignored_file(p)]
    for p in all_b_files:
        if re.search(r'-(?:accept|confirm|reject)\\d*\\.md$', p.name, re.I) or p.name.startswith(('receipt-', 'cancel-', 'pingloop-route-', 'cc-')):
            continue
        if handoff.REPLY_RE.search(p.name):
            # 对齐 handoff_backlog_audit.py L58：-reply.md 结尾为派生回执，不单独计入 B 账
            continue
        if is_synthetic_test_name(p.name):
            continue
        is_reply_file = False
        try:
            txt = p.read_text(encoding='utf-8', errors='replace')
            meta, body = handoff.parse_frontmatter(txt)
            if not meta:
                continue
            status = str(meta.get('status', '')).strip()
            if is_term_status(status):
                continue
            is_highrisk = (status == '需高危拍板') or p.name.startswith('escalate-highrisk-')
            if status not in ('待确认', '交付待确认') and not is_highrisk:
                continue

            # 权威角色解析：直接复用 handoff._resolve_confirm_roles，彻底消除 -reply 字符子串反转 Bug
            exp_verifier, exp_submitter = handoff._resolve_confirm_roles(p, meta, txt)
            verifier = (exp_verifier or str(meta.get('from', '')).strip().lower() or 'unknown')
            submitter = (exp_submitter or str(meta.get('to', '')).strip().lower() or '未知')
            b_stem = re.sub(r'-(?:reply\\d*|audit\\d*|submit\\d*)$', '', p.stem, flags=re.I)

            # 本箱已核销、同 trace/reply_to 已闭环、或存在同目录 -confirm/-reply 已终态则跳过（与 handoff_backlog_audit.py 同源）
            if p.name in acked_box:
                continue
            acked_v = handoff.load_ack(verifier) if verifier and verifier != 'unknown' else {}
            if p.name in acked_v:
                continue
            tid = str(meta.get('trace_id', '')).strip()
            rt = str(meta.get('reply_to', '')).strip()
            if tid and tid in closed_traces:
                continue
            if rt and rt != 'none' and (Path(rt).name in closed_files or Path(rt).stem in closed_files):
                continue
            if p.name in closed_files or (is_reply_file and (b_stem in all_acked_bases or b_stem in closed_files)):
                continue
            has_confirm_file = any((b_stem in f.name and '-confirm' in f.name) for f in all_b_files)
            if has_confirm_file:
                continue
            if not is_reply_file and any((f.name.startswith(f'{p.stem}-reply') and f != p) for f in all_b_files):
                continue
            if is_reply_file:
                orig_p = b_dir / f'{b_stem}.md'
                if orig_p.is_file():
                    o_txt = orig_p.read_text(encoding='utf-8', errors='replace')
                    o_meta, _ = handoff.parse_frontmatter(o_txt)
                    if is_term_status(o_meta.get('status', '')):
                        continue

            # 露露终裁：普通 from=lulu 派单由非履约方总控/异构 Agent 自动代理验收，
            # 仅「需高危拍板 / escalate-highrisk」与 M1 熔断才进入 lulu_actions 提醒露露拍板！
            is_lulu = is_highrisk
            eff_verifier = verifier
            if verifier == 'lulu' and not is_highrisk:
                eff_verifier = 'ping' if submitter.lower() != 'ping' else 'agy'
            item_obj = {
                'file': f'{b}/{p.name}',
                'base': b_stem,
                'from': submitter,
                'to': eff_verifier,
                'date': str(meta.get('date', '-')),
                'title': clean_title(handoff.first_heading(body) or p.stem),
                'mtime': p.stat().st_mtime,
                'stage': 'high-risk-blocked' if is_highrisk else 'submitted',
                'statusText': '待露露拍板' if is_lulu else f'待 {eff_verifier} 自动验收',
                'artifacts': str(meta.get('artifacts', '')),
                'eta': '待露露确认' if is_lulu else 'Agent 互验中',
                'highlights': handoff.extract_highlights(txt)
            }
            if is_lulu:
                lulu_raw.append(item_obj)
            else:
                agent_raw.append(item_obj)
        except Exception:
            pass

def dedup_latest(arr):
    by_base = {}
    for it in arr:
        k = it['file'] if not it['base'] else f"{it['base']}::{it['to']}"
        if k not in by_base or it['mtime'] > by_base[k]['mtime']:
            by_base[k] = it
    return sorted(by_base.values(), key=lambda x: x['mtime'], reverse=True)

lulu_list = dedup_latest(lulu_raw)
agent_list = dedup_latest(agent_raw)
res['lulu_actions'] = lulu_list
res['agent_confirms'] = agent_list
res['pending_confirms'] = lulu_list + agent_list

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
                title = clean_title(handoff.first_heading(body) or p.stem)
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

# Attach latest STEP node heartbeat + today auto-closed feed from events.log
latest_real_ev = ''
today_prefix = time.strftime('%Y-%m-%d', time.localtime())
today_closed_set = set()
submit_ts_map = {}
feed_rows = []
try:
    ev_path = Path(os.environ.get('AGENT_ISLAND_EVENT_LOG', '/Users/l/.local/funnel-sync/events.log'))
    if ev_path.exists():
        step_map = {}
        short_ag = {'ping': 'Ping', 'agy': 'AGY', 'alma': 'Alma', 'lulu': '露露'}
        for ln in ev_path.read_text(encoding='utf-8', errors='ignore').splitlines()[-450:]:
            try:
                ev = json.loads(ln)
            except Exception:
                continue
            p_str = str(ev.get('path', ''))
            if not p_str or is_synthetic_test_name(p_str):
                continue
            fname = p_str.rsplit('/', 1)[-1]
            t_raw = str(ev.get('time', ''))
            hhmmss = t_raw[11:19] if len(t_raw) >= 19 else ''
            hhmm = t_raw[11:16] if len(t_raw) >= 16 else ''
            act = str(ev.get('action', ''))
            ev_verb = str(ev.get('event') or act).lower()
            actor = str(ev.get('actor') or '').lower()
            to_ag = str(ev.get('to') or '').lower()
            if act in ('STEP', 'PUT'):
                label = f"{hhmmss} {actor} {ev_verb} {fname}".strip() if actor else f"{hhmmss} {act} {fname}".strip()
                latest_real_ev = label
            if act == 'STEP' and ev_verb == 'submit' and len(t_raw) >= 19:
                try:
                    submit_ts_map[fname] = time.mktime(time.strptime(t_raw[:19], '%Y-%m-%dT%H:%M:%S'))
                except Exception:
                    pass
            if act == 'STEP' and ev_verb == 'confirm' and not fname.startswith(('cc-', 'receipt-')):
                if t_raw.startswith(today_prefix):
                    today_closed_set.add(fname)
                dur_txt = '自动'
                if fname in submit_ts_map and len(t_raw) >= 19:
                    try:
                        c_ts = time.mktime(time.strptime(t_raw[:19], '%Y-%m-%dT%H:%M:%S'))
                        diff_s = max(0, int(c_ts - submit_ts_map[fname]))
                        if diff_s <= 1:
                            dur_txt = '1s' if diff_s == 1 else '<1s'
                        elif diff_s < 60:
                            dur_txt = f'{diff_s}s'
                        elif diff_s < 3600:
                            dur_txt = f'{diff_s // 60}m'
                    except Exception:
                        pass
                rel_p = p_str[len('handoffs/'):] if p_str.startswith('handoffs/') else p_str
                feed_rows.append({
                    'fname': fname,
                    'rel': rel_p,
                    'hhmm': hhmm or '--:--',
                    'route': f"{short_ag.get(to_ag, to_ag or 'Agent')} → {short_ag.get(actor, actor or 'Agent')} 验",
                    'dur': dur_txt,
                    'date_ok': t_raw.startswith(today_prefix),
                })
            if act != 'STEP':
                continue
            s_txt = str(ev.get('step', '')).strip()
            if not s_txt:
                continue
            step_map[fname] = f"{s_txt} · {hhmm}" if hhmm else s_txt
        if step_map:
            for arr in res.values():
                for it in arr:
                    f_leaf = str(it.get('file', '')).rsplit('/', 1)[-1]
                    sn = step_map.get(f_leaf)
                    if sn:
                        it['stepNote'] = sn
except Exception:
    pass

# 构建最近 5 拍去重人话闭环战报
seen_feed = set()
loop_feed_out = []
for row in reversed(feed_rows):
    if row['fname'] in seen_feed:
        continue
    seen_feed.add(row['fname'])
    fp = ROOT / row['rel']
    f_title = row['fname'].replace('.md', '')
    f_hl = '后台自动完成交付与核验结案，全程零人工介入。'
    if fp.is_file():
        try:
            ftxt = fp.read_text(encoding='utf-8', errors='replace')
            _, fbody = handoff.parse_frontmatter(ftxt)
            f_title = clean_title(handoff.first_heading(fbody) or f_title)
            hls = handoff.extract_highlights(ftxt)
            if isinstance(hls, str) and hls.strip():
                f_hl = hls.strip()[:160]
            elif isinstance(hls, list) and hls:
                f_hl = ' '.join(str(x) for x in hls[:2])[:160]
        except Exception:
            pass
    loop_feed_out.append({
        'file': row['rel'],
        'title': f_title[:42],
        'from': row['route'],
        'to': 'lulu',
        'date': row['hhmm'],
        'mtime': 0,
        'stage': 'confirmed',
        'statusText': '已结案 · 0 人工',
        'eta': row['dur'],
        'highlights': f_hl,
    })
    if len(loop_feed_out) >= 5:
        break

latest_closed_title = loop_feed_out[0]['title'] if loop_feed_out else ''
res['__today_stats__'] = [{'file': str(len(today_closed_set)), 'title': latest_closed_title, 'from': '', 'to': 'self', 'date': '-', 'mtime': 0}]
res['__loop_feed__'] = loop_feed_out

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
    raw_pl_ev = str(f_res.get('last_event', 'events.log 实时待命'))
    pl_event = latest_real_ev if (latest_real_ev and (is_synthetic_test_name(raw_pl_ev.split()[-1] if raw_pl_ev.split() else '') or not raw_pl_ev)) else raw_pl_ev
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
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
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
                        let stepNote = (d["stepNote"] as? String) ?? ""
                        return TaskItem(file: file, from: from, to: to, date: date, title: title, stage: stage, statusText: statusText, artifacts: artifacts, eta: eta, highlights: highlights, stepNote: stepNote)
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

    private var uiScale: CGFloat { CGFloat(monitor.uiScale) }
    private func fs(_ base: CGFloat) -> CGFloat { (base * uiScale).rounded() }
    private var is1xDisplay: Bool { (NSScreen.main?.backingScaleFactor ?? 1.0) <= 1.1 }
    private var crispHairline: CGFloat { is1xDisplay ? 1.0 : 0.5 }
    
    var accentColor: Color {
        Color(hex: monitor.accentHex)
    }
    
    var body: some View {
        ZStack {
            Color.clear
            
            // The Frosted Capsule or Control Center Panel（阴影仅作用在底层背景，不包裹文字树）
            ZStack(alignment: .top) {
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
                        // 保留 `.regular` 原生磨砂折射，避免 `.clear` 导致浅色高对比桌面文字穿透串行。
                        glassStyle: .regular,
                        cornerRadius: cornerRadius,
                        forceFallback: forceFallback
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    // Layer 2: Solid Obsidian & Ceramic Glass Tint (深浅色双模原生适配，防HDR溢色强化)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(panelFill)

                    // Layer 2.5: 1.0px(1x) / 0.5px(2x) inset stroke，做出玻璃砖内壁切面
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(monitor.panelIsDark ? 0.14 : 0.30),
                            lineWidth: crispHairline
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
                            lineWidth: 1.0
                        )
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    glassMirrorEdge
                }
                .shadow(
                    color: Color.black.opacity(monitor.panelIsDark ? 0.45 : 0.16),
                    radius: monitor.panelIsDark ? 18 : 12,
                    x: 0,
                    y: monitor.panelIsDark ? 6 : 4
                )
                .shadow(
                    color: Color.black.opacity(monitor.panelIsDark ? 0.20 : 0.05),
                    radius: 2,
                    x: 0,
                    y: 1
                )

                // Content View（纯净矢量层，零 scaleEffect 拉伸、零外层 shadow 光栅化）
                if ProcessInfo.processInfo.environment["AGENT_ISLAND_GLASS_PROBE"] != "1" {
                    contentForCurrentMode
                        .frame(
                            width: contentWidth,
                            height: contentHeight,
                            alignment: monitor.currentMode == .expanded ? .top : .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .top)
            .animation(.spring(response: 0.32, dampingFraction: 0.76), value: monitor.currentMode)
            .animation(.easeInOut(duration: 0.25), value: monitor.panelIsDark)
            .animation(.easeInOut(duration: 0.22), value: monitor.skin)
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
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(.white)
            }

            Text(compactHead)
                .font(.system(size: fs(15), weight: .heavy))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(compactTail)
                .font(.system(size: fs(13), weight: .bold))
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: fs(12), weight: .bold))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
    }

    var compactAccent: Color {
        if monitor.dataUnknown { return Color(hex: "F59E0B") }
        if monitor.fusedCount > 0 { return Color(hex: "EF4444") }
        if monitor.totalLuluActions > 0 { return Color(hex: "8B5CF6") }
        if monitor.totalAgentConfirms > 0 || monitor.totalUnread > 0 { return Color(hex: "3B82F6") }
        return Color(hex: "10B981")
    }

    var compactIsAlert: Bool {
        monitor.dataUnknown || monitor.fusedCount > 0 || monitor.totalLuluActions > 0
    }

    var compactGlyphName: String {
        if monitor.dataUnknown { return "questionmark" }
        if monitor.fusedCount > 0 { return "exclamationmark" }
        if monitor.totalLuluActions > 0 { return "bell.fill" }
        if monitor.totalAgentConfirms > 0 || monitor.totalUnread > 0 { return "bolt.fill" }
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
                    .font(.system(size: fs(12), weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            monitor.setMode(.expanded)
        }
    }
    
    // MARK: - AgentIsland v2.0 & Multi-Agent 紧凑四分卡控制中心（保持原生液态玻璃，零多余 emoji）
    var controlCenterExpandedView: some View {
        VStack(spacing: 11) {
            // Layer 1: 精致顶栏（品牌状态 + 4 分卡切换 + 设置/关闭）
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 22, height: 22)
                    Image(systemName: "infinity")
                        .foregroundColor(.white)
                        .font(.system(size: fs(12), weight: .bold))
                }
                Text("Ping-Loop")
                    .font(.system(size: fs(14), weight: .bold))
                    .foregroundColor(primaryTextColor)

                if monitor.dataUnknown {
                    Text("数据未知")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(textAmber)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.16)))
                } else if let fb = monitor.reconcileFeedback {
                    Text(fb)
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(textGreen)
                        .lineLimit(1)
                } else {
                    let isBusy = monitor.wakeState.effectiveStatus == "running" || monitor.totalAgentConfirms > 0 || monitor.totalUnread > 0
                    Text(isBusy ? "自动闭环中" : "自动闭环正常")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(isBusy ? textBlue : textGreen)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((isBusy ? Color(hex: "3B82F6") : Color(hex: "10B981")).opacity(0.14)))
                }

                Spacer(minLength: 4)

                // 4 张紧凑分卡切换（团队 / 战报 / 自优化 / 链路）
                HStack(spacing: 2) {
                    ForEach(PanelTab.allCases, id: \.self) { tab in
                        let selected = !monitor.showSettings && !monitor.showTopology && monitor.activeTab == tab
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                monitor.showSettings = false
                                monitor.showTopology = false
                                monitor.activeTab = tab
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text(tab.rawValue)
                                    .font(.system(size: fs(12), weight: selected ? .bold : .semibold))
                                if tab == .feed && monitor.todayClosedCount > 0 {
                                    Text("\(monitor.todayClosedCount)")
                                        .font(.system(size: fs(11), weight: .bold, design: .monospaced))
                                        .foregroundColor(selected ? accentOnColor : secondaryTextColor)
                                }
                            }
                            .foregroundColor(selected ? accentOnColor : secondaryTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(selected ? accentColor : Color.clear))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(2)
                .background(
                    Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                )

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        monitor.showSettings.toggle()
                    }
                }) {
                    Image(systemName: monitor.showSettings ? "gearshape.fill" : "gearshape")
                        .foregroundColor(monitor.showSettings ? accentColor : secondaryTextColor)
                        .font(.system(size: fs(13), weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                .help("外观、尺寸、停靠边与模块开关")

                Button(action: {
                    monitor.setMode(.compact)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(secondaryTextColor)
                        .font(.system(size: fs(16)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)

            // 红线拍板区（仅 M1 熔断或高危拦截时出现，平时 0 高度隐藏）
            if monitor.fusedCount > 0 || !monitor.fusedCards.isEmpty {
                fusedDecisionBannerView
                    .padding(.horizontal, 14)
            }
            if monitor.totalLuluActions > 0 && !monitor.showSettings {
                liveDispatchHeroCardView
                    .padding(.horizontal, 14)
            }

            // 主内容区（设置页 vs 4 张紧凑分卡）
            if monitor.showSettings {
                settingsView
            } else {
                if monitor.showTopology || monitor.activeTab == .topo {
                    architectureTopologyView
                        .padding(.horizontal, 14)
                } else {
                    switch monitor.activeTab {
                    case .team:
                        v2TeamCardView
                            .padding(.horizontal, 14)
                    case .feed:
                        v2FeedCardView
                            .padding(.horizontal, 14)
                    case .opt:
                        v2OptCardView
                            .padding(.horizontal, 14)
                    case .topo:
                        architectureTopologyView
                            .padding(.horizontal, 14)
                    }
                }

                // 底部平等三选一快发栏 + 快捷资产入口（4 分卡常驻不跳动）
                VStack(spacing: 6) {
                    quickSendStrip
                    assetsRow
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - v2.0 卡片 1：团队实时态（4 列 Rich Presence + 1 行裁判摘要 + 精简暂停控制）
    var v2TeamCardView: some View {
        let agyRunning = monitor.wakeState.effectiveStatus == "running"
        let agyPaused = monitor.wakeState.effectiveStatus == "paused"
        let agyBlocked = ["fused-m1", "high-risk-blocked", "需高危拍板", "error", "submit-failed"].contains(monitor.wakeState.effectiveStatus)
        let lastClosed = monitor.recentLoopFeed.first
        return VStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("团队实时态 · 点击节点查抽屉")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    let okText = agyRunning ? "AGY 自动执行中" : (agyBlocked ? "高危挂起 · 待拍板" : (agyPaused ? "后台已暂停" : "4 节点在线 · 0 阻塞"))
                    let okColor = agyRunning ? textBlue : (agyBlocked ? textRed : (agyPaused ? textAmber : textGreen))
                    Text(okText)
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(okColor)
                }

                HStack(spacing: 8) {
                    v2AgentTile(
                        badge: "P", name: "Ping", role: "云端 VM",
                        status: monitor.pingPending > 0 ? "处理 \(monitor.pingPending) 单中" : "待命 · Funnel通",
                        color: Color(hex: "7C3AED"),
                        active: monitor.pingPending > 0 || monitor.activePulses.contains { $0.source == "ping" || $0.target == "ping" }
                    ) { monitor.setDrawerAgent("ping") }

                    v2AgentTile(
                        badge: "白", name: "AGY", role: "Mac 代码",
                        status: agyRunning ? "自动执行中" : (agyBlocked ? "高危挂起" : (agyPaused ? "已暂停" : "待命 · 自动验结")),
                        color: agyBlocked ? Color(hex: "EF4444") : Color(hex: "2563EB"),
                        active: agyRunning || agyBlocked || monitor.agyPending > 0
                    ) { monitor.setDrawerAgent("agy") }

                    v2AgentTile(
                        badge: "A", name: "Alma", role: "Mac 巡检",
                        status: monitor.almaPending > 0 ? "履约 \(monitor.almaPending) 单" : "待命 · 跨箱验货",
                        color: Color(hex: "D97706"),
                        active: monitor.almaPending > 0 || monitor.activePulses.contains { $0.source == "alma" || $0.target == "alma" }
                    ) { monitor.setDrawerAgent("alma") }

                    v2AgentTile(
                        badge: "算", name: "模拟机", role: "9011/9012",
                        status: monitor.tailscaleOnline ? "Tailscale 就绪" : "私网离线",
                        color: Color(hex: "059669"),
                        active: false
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) { monitor.activeTab = .topo }
                    }
                }
            }
            .padding(11)
            .background(squircleCardBackground)

            // 1 行健康与最近闭环摘要 + 后台暂停开关
            HStack(spacing: 8) {
                let score = monitor.harnessState.loopScore
                let scoreOk = monitor.harnessState.sealOk && score >= 100
                Text("裁判 \(score)/100 (\(monitor.harnessState.smokePassed)/\(monitor.harnessState.smokeTotal))")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(scoreOk ? textGreen : textAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill((scoreOk ? Color(hex: "10B981") : Color(hex: "F59E0B")).opacity(0.14)))

                if let lc = lastClosed {
                    Text("最近：\(lc.time) \(lc.title)")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                } else {
                    Text("全员就绪 · 今日自闭环 \(monitor.todayClosedCount) 单")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) { monitor.activeTab = .feed }
                }) {
                    Text("看战报")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(accentTextColor)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    monitor.toggleAgyWakePaused()
                }) {
                    Text(monitor.wakeState.paused ? "恢复" : "暂停")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(monitor.wakeState.paused ? textGreen : secondaryTextColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(squircleCardBackground)

            if monitor.resumeConfirmPending {
                resumeConfirmBar
            }
        }
    }

    func v2AgentTile(badge: String, name: String, role: String, status: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ZStack {
                        if active {
                            Circle()
                                .stroke(color.opacity(monitor.pulse ? 0.65 : 0.20), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                        Text(badge)
                            .font(.system(size: fs(11), weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.system(size: fs(12), weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(1)
                        Text(role)
                            .font(.system(size: fs(11), weight: .semibold))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                Text(status)
                    .font(.system(size: fs(11), weight: active ? .bold : .semibold))
                    .foregroundColor(active ? color : secondaryTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? color.opacity(monitor.panelIsDark ? 0.20 : 0.10) : (monitor.panelIsDark ? Color.white.opacity(0.05) : Color.black.opacity(0.035)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(active ? color.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - v2.0 卡片 2：今日自动闭环战报（最近 5 拍无哈希纯人话）
    var v2FeedCardView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日自动闭环战报 · 点行展开结果")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(secondaryTextColor)
                Spacer()
                Text("今日已自闭环 \(monitor.todayClosedCount) 单")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(textGreen)
            }

            if monitor.recentLoopFeed.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "10B981")).frame(width: 7, height: 7)
                    Text("今日尚无新闭环记录，系统后台静默待命中")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 5) {
                    ForEach(monitor.recentLoopFeed) { row in
                        let isExp = monitor.expandedFeedId == row.id
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text(row.time)
                                    .font(.system(size: fs(11), weight: .bold, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                Circle()
                                    .fill(row.isGreen ? Color(hex: "10B981") : Color(hex: "3B82F6"))
                                    .frame(width: 6, height: 6)
                                Text(row.title)
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(row.route)
                                    .font(.system(size: fs(11), weight: .semibold))
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                                Text(row.duration)
                                    .font(.system(size: fs(11), weight: .bold, design: .monospaced))
                                    .foregroundColor(textGreen)
                                    .frame(minWidth: 28, alignment: .trailing)
                            }
                            if isExp {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.summary)
                                        .font(.system(size: fs(12), weight: .regular))
                                        .foregroundColor(secondaryTextColor)
                                        .lineLimit(3)
                                    HStack {
                                        Text(row.path)
                                            .font(.system(size: fs(11), weight: .regular, design: .monospaced))
                                            .foregroundColor(secondaryTextColor)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(action: {
                                            let full = "\(monitor.rootPath)/\(row.path)"
                                            NSWorkspace.shared.open(URL(fileURLWithPath: full))
                                        }) {
                                            Text("打开原文")
                                                .font(.system(size: fs(11), weight: .bold))
                                                .foregroundColor(accentTextColor)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(monitor.panelIsDark ? Color.white.opacity(isExp ? 0.09 : 0.05) : Color.black.opacity(isExp ? 0.06 : 0.035))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                monitor.expandedFeedId = isExp ? nil : row.id
                            }
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(squircleCardBackground)
    }

    // MARK: - v2.0 卡片 3：自优化变化日志（全自动 loop 判断，零手动按钮，只报谁升格/谁降格/变化是什么）
    var v2OptCardView: some View {
        let hs = monitor.harnessState
        let scoreOk = hs.sealOk && hs.loopScore >= 100
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("裁判 \(hs.loopScore)/100 (\(hs.smokePassed)/\(hs.smokeTotal))")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(scoreOk ? textGreen : textRed)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill((scoreOk ? Color(hex: "10B981") : Color(hex: "EF4444")).opacity(0.14)))
                Text("全自动升格/降格 · 仅呈报变化")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(secondaryTextColor)
                Spacer()
                Text(hs.ageMin <= 1 ? "刚刚扫描" : "\(hs.ageMin)m 前扫描")
                    .font(.system(size: fs(11), weight: .semibold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
            }

            if hs.autoChanges.isEmpty {
                Text("当前无新升格或降格变化，6/6 不可变冒烟门禁持续守卫中。")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(hs.autoChanges.prefix(4))) { item in
                        let badgeColor: Color = item.kind == "upgraded" ? Color(hex: "10B981") : (item.kind == "downgraded" ? Color(hex: "3B82F6") : Color(hex: "6B7280"))
                        let badgeTextColor: Color = item.kind == "upgraded" ? textGreen : (item.kind == "downgraded" ? textBlue : secondaryTextColor)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.badge)
                                    .font(.system(size: fs(11), weight: .bold))
                                    .foregroundColor(badgeTextColor)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(badgeColor.opacity(0.15)))
                                Text(item.title)
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.carrier)
                                    .font(.system(size: fs(11), weight: .regular, design: .monospaced))
                                    .foregroundColor(secondaryTextColor)
                                    .lineLimit(1)
                            }
                            Text(item.change)
                                .font(.system(size: fs(11), weight: .medium))
                                .foregroundColor(secondaryTextColor)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(monitor.panelIsDark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
                        )
                    }
                }
            }
        }
        .padding(11)
        .background(squircleCardBackground)
    }

    // MARK: - Panel Sections (可单独开关 · 可拖动排序)
    @ViewBuilder
    func panelSectionView(_ key: String) -> some View {
        switch PanelSectionKey(rawValue: key) {
        case .overview:
            overviewSummaryStrip
                .padding(.horizontal, 14)
        case .wake:
            wakeWorkerStrip
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
        case .quickSend:
            quickSendStrip
                .padding(.horizontal, 14)
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
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(textAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.14)))
            } else {
                ForEach(AgentRoster.all) { agent in
                    let count = monitor.pendingCount(for: agent.key)
                    HStack(spacing: 4) {
                        Circle().fill(agent.color).frame(width: 6, height: 6)
                        Text(agent.short)
                            .font(.system(size: fs(12), weight: .bold))
                            .foregroundColor(primaryTextColor)
                        Text(count == 0 ? "已读" : "\(count) 未读")
                            .font(.system(size: fs(12), weight: count == 0 ? .semibold : .bold))
                            .foregroundColor(count == 0 ? secondaryTextColor : agent.color)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(agent.color.opacity(count == 0 ? 0.06 : 0.12)))
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if monitor.totalLuluActions > 0 {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(textPurple)
                    Text("\(monitor.totalLuluActions) 待你拍板")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(Color(hex: "8B5CF6"))
                } else if monitor.totalAgentConfirms > 0 {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(textBlue)
                    Text("\(monitor.totalAgentConfirms) 互验中")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(textBlue)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(textGreen)
                    Text("0 积压")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill((monitor.totalLuluActions > 0 ? Color(hex: "8B5CF6") : (monitor.totalAgentConfirms > 0 ? Color(hex: "3B82F6") : Color(hex: "10B981"))).opacity(monitor.totalSubmitted == 0 ? 0.06 : 0.13)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(minHeight: 28)
        .background(squircleCardBackground)
    }

    /// 双后台唤醒 + A-Verifier 状态控制条（36pt · 全 ≥11pt · 零新增轮询）
    var wakeWorkerStrip: some View {
        let ws = monitor.wakeState
        let ds = monitor.deltaState
        let st = ws.effectiveStatus
        let statusColor: Color = {
            switch st {
            case "running": return Color(hex: "007AFF")
            case "paused": return Color(hex: "6B7280")
            case "fused-m1", "error", "high-risk-blocked", "需高危拍板", "submit-failed": return Color(hex: "EF4444")
            case "relay-needed", "empty-response", "待整改": return Color(hex: "F59E0B")
            default: return Color(hex: "10B981")
            }
        }()
        let statusLabel: String = {
            switch st {
            case "running": return "运行中"
            case "paused": return "已暂停"
            case "fused-m1": return "M1熔断"
            case "error": return "异常"
            case "high-risk-blocked", "需高危拍板": return "需拍板"
            case "relay-needed": return "需接力"
            case "empty-response": return "空响应"
            case "submit-failed": return "交付失败"
            case "待整改": return "待整改"
            default: return "待命"
            }
        }()
        let barColor: Color = ws.tokenRatio >= 0.8 ? Color(hex: "F59E0B") : statusColor
        let pulseActive = (st == "running" || st == "fused-m1" || st == "high-risk-blocked" || st == "需高危拍板")
        // 不限量时进度条画满整条淡色轨道，不再是一条空条（空条＝看起来像 0 预算快见底）
        let barWidth: CGFloat = ws.tokenUnlimited ? 36 : max(4, (36 * ws.tokenRatio).rounded())

        return VStack(spacing: 4) {
            if monitor.resumeConfirmPending { resumeConfirmBar }
            HStack(spacing: 6) {
            // ① 左段：AGY 状态 + 预算进度条
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .opacity(pulseActive ? (monitor.pulse ? 1.0 : 0.45) : 1.0)
                Text("AGY")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(primaryTextColor)
                Text(statusLabel)
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(statusColor.opacity(0.12)))

            HStack(spacing: 4) {
                Text("\(ws.dailyRuns)/\(ws.dailyRunsLimit)")
                    .font(.system(size: fs(12), weight: .semibold, design: .monospaced))
                    .foregroundColor(primaryTextColor)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(monitor.panelIsDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14))
                        .frame(width: 36, height: 6)
                    Capsule()
                        .fill(ws.tokenUnlimited ? Color(hex: "10B981").opacity(0.55) : barColor)
                        .frame(width: barWidth, height: 6)
                }
                Text(ws.tokenPctText)
                    .font(.system(size: fs(12), weight: .bold, design: .monospaced))
                    .foregroundColor(ws.tokenUnlimited ? secondaryTextColor
                                     : (ws.tokenRatio >= 0.8 ? Color(hex: "D97706") : secondaryTextColor))
            }
            .help(ws.tooltipText)

            Spacer(minLength: 4)

            // ② 中段：Alma 后台 + A-Verifier 态
            HStack(spacing: 4) {
                Circle()
                    .fill(ds.almaLoaded ? Color(hex: "FF9F0A") : secondaryTextColor.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text("Alma \(ds.almaAgeText)")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                Text("·")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                Text("A级 \(ds.verifierShortBadge)")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(ds.convTotal > 0 ? textGreen : accentTextColor)
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            // ③ 右段：一键暂停 / 恢复可控胶囊
            Button(action: { monitor.toggleAgyWakePaused() }) {
                HStack(spacing: 3) {
                    Image(systemName: ws.paused ? "play.fill" : "pause.fill")
                        .font(.system(size: fs(11), weight: .bold))
                    Text(ws.paused ? "恢复" : "暂停")
                        .font(.system(size: fs(12), weight: .bold))
                }
                .foregroundColor(ws.paused ? (monitor.panelIsDark ? Color(hex: "34D399") : Color(hex: "047857")) : primaryTextColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(ws.paused
                            ? Color(hex: "10B981").opacity(monitor.panelIsDark ? 0.24 : 0.18)
                            : (monitor.panelIsDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)))
                        .overlay(
                            Capsule().stroke(
                                ws.paused
                                    ? Color(hex: "10B981").opacity(0.45)
                                    : (monitor.panelIsDark ? Color.white.opacity(0.24) : Color.black.opacity(0.18)),
                                lineWidth: 1.0
                            )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help(ws.paused ? "恢复 AGY 后台自动唤醒" : "暂停 AGY 后台自动唤醒（不影响前台窗口）")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(squircleCardBackground)
    }

    /// 恢复前的就地二次确认条（不用系统 NSAlert，绝不把模态框弹到物理主屏）
    var resumeConfirmBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: fs(12), weight: .bold))
                .foregroundColor(Color(hex: "F59E0B"))
            Text(AgentMonitor.resumeConfirmationText(backlogCount: monitor.resumeConfirmBacklog))
                .font(.system(size: fs(12), weight: .semibold))
                .foregroundColor(secondaryTextColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: { monitor.confirmResume() }) {
                Text("只重放 \(AgentMonitor.resumeBacklogDefault) 张")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(Color(hex: "047857"))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: "10B981").opacity(0.22)))
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { monitor.cancelResumeConfirmation() }) {
                Text("取消")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(primaryTextColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.12)))
    }

    /// 三个固定色收件箱卡（区分今日新单与历史存量，消除数字焦虑）
    var inboxCardsRow: some View {
        HStack(spacing: 10) {
            ForEach(AgentRoster.all) { agent in
                let count = monitor.pendingCount(for: agent.key)
                let tCount = monitor.todayCount(for: agent.key)
                let doneCount: Int = {
                    switch agent.key {
                    case "ping": return monitor.pingDoneTasks.count
                    case "agy": return monitor.agyDoneTasks.count
                    case "alma": return monitor.almaDoneTasks.count
                    default: return 0
                    }
                }()
                let sub: String = {
                    if monitor.dataUnknown { return "读取失败 · 未知" }
                    if count == 0 { return "0 待办 · 已结 \(doneCount)" }
                    if tCount > 0 { return "今日+\(tCount) · 待办\(count) · 已结\(doneCount)" }
                    return "今日0 · 待办\(count) · 已结\(doneCount)"
                }()
                agentBalanceCard(
                    icon: agent.symbol,
                    iconBg: agent.color,
                    textTint: tCount > 0 ? agentTextColor(agent) : secondaryTextColor,
                    title: agent.title,
                    subtitle: sub,
                    hasPending: !monitor.dataUnknown && tCount > 0
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
                                .font(.system(size: fs(11), weight: .bold))
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
                .frame(height: 28)

                // V5 + ⑨：保留最近通讯行与单光点，并补「最后通讯 N 秒前」。
                HStack(spacing: 5) {
                    Circle()
                        .fill(monitor.activePulses.isEmpty ? textGray : textGreen)
                        .frame(width: 5, height: 5)
                    Text("\(miniRecentCommText) · \(miniLastCommAgoText)")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(monitor.activePulses.isEmpty ? textGray : textGreen)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 18)
            }
            .frame(height: 48)
            .background(squircleCardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .help("中轴节点：AGY/Alma/Ping（18px）\n主通道：1.5pt\n侧标：Tailscale / Funnel 443 / 坚果云\n点击展开/收起横向链路")
    }

    var miniRecentCommText: String {
        if let p = monitor.activePulses.first {
            let s = AgentRoster.identity(for: p.source)?.short ?? p.source.uppercased()
            let t = AgentRoster.identity(for: p.target)?.short ?? p.target.uppercased()
            let extra = monitor.activePulses.count > 1 ? " · +\(monitor.activePulses.count - 1) 条" : ""
            return "实时通讯：\(s) → \(t) ×\(p.count)\(extra)"
        }
        if !monitor.lastCommRoute.isEmpty {
            return "最近通讯：\(monitor.lastCommRoute)"
        }
        return "最近通讯：暂无记录"
    }

    var miniLastCommAgoText: String {
        guard let lastAt = monitor.lastCommAt else { return "最后通讯：暂无" }
        let seconds = max(0, Int(Date().timeIntervalSince(lastAt)))
        if seconds < 60 {
            return "最后通讯 \(seconds) 秒前"
        }
        if seconds < 3600 {
            return "最后通讯 \(seconds / 60) 分钟前"
        }
        if seconds < 86400 {
            return "最后通讯 \(seconds / 3600) 小时前"
        }
        return "最后通讯 \(seconds / 86400) 天前"
    }

    func miniStripChannelTag(text: String, icon: String, ok: Bool, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: fs(11), weight: .bold))
            Text(text)
                .font(.system(size: fs(11), weight: .bold))
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
                    .frame(width: 4, height: 4)
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
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(muted ? secondaryTextColor : tint)
                    .frame(width: 40, alignment: .leading)
                Image(systemName: icon)
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(muted ? secondaryTextColor : tint)
                    .frame(width: 14)
                Text(name)
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(muted ? secondaryTextColor : primaryTextColor)
                Text(detail)
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Circle().fill(ok ? Color(hex: "10B981") : Color(hex: "EF4444")).frame(width: 5, height: 5)
                    Text(ok ? "在线" : "离线")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(ok ? Color(hex: "059669") : Color(hex: "DC2626"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 0.5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// 底部一句发信：不打开聊天窗口，选收件人直接走 handoff Funnel 发送
    var quickSendStrip: some View {
        let targets: [(id: String, label: String)] = [("ping", "Ping"), ("agy", "AGY"), ("alma", "Alma")]
        let currentLabel = targets.first(where: { $0.id == monitor.quickSendTarget })?.label ?? "Ping"
        let canSend = !monitor.quickSendBusy && !monitor.quickSendText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(targets, id: \.id) { item in
                    let selected = monitor.quickSendTarget == item.id
                    Button(action: { monitor.quickSendTarget = item.id }) {
                        Text(item.label)
                            .font(.system(size: fs(11), weight: selected ? .bold : .semibold))
                            .foregroundColor(selected ? accentOnColor : secondaryTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(selected ? accentColor : (monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            TextField(
                "",
                text: $monitor.quickSendText,
                prompt: Text("跟 \(currentLabel) 说句话或下任务（完成后自动闭环）").foregroundColor(secondaryTextColor.opacity(0.75))
            )
                .textFieldStyle(.plain)
                .font(.system(size: fs(12)))
                .foregroundColor(primaryTextColor)
                .colorScheme(monitor.panelIsDark ? .dark : .light)
                .onSubmit { monitor.quickSendMessage() }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(monitor.panelIsDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                )
            Button(action: { monitor.quickSendMessage() }) {
                Text(monitor.quickSendBusy ? "发中…" : "发送")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(canSend ? accentOnColor : secondaryTextColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(canSend ? accentColor : (monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(squircleCardBackground)
    }

    /// 快捷资产入口（默认含 M7 决定档案与纠正日志，支持设置页自定义）
    var assetsRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(monitor.quickAssets) { item in
                        assetButton(icon: item.icon, label: item.label) {
                            if item.path.hasPrefix("http://") || item.path.hasPrefix("https://"),
                               let u = URL(string: item.path) {
                                NSWorkspace.shared.open(u)
                            } else {
                                NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            Spacer(minLength: 4)
            Button(action: { monitor.refreshAll(showFeedback: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { monitor.setMode(.compact) }) {
                Text("收起")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(assetsRowBackground)
    }

    // MARK: - 设置：皮肤 × 形态 × 尺寸 × 停靠边 × 模块开关/排序
    var settingsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(accentTextColor)
                Text("外观与面板")
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(primaryTextColor)
                Spacer()
                Text(monitor.dataUnknown ? "数据未知" : "数据正常")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(monitor.dataUnknown ? Color(hex: "B45309") : Color(hex: "059669"))
                Button(action: { withAnimation { monitor.showSettings = false } }) {
                    Text("完成")
                        .font(.system(size: fs(13), weight: .bold))
                        .foregroundColor(accentTextColor)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(accentColor.opacity(0.14)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(squircleCardBackground)
            .padding(.horizontal, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 4) {
                            ForEach(AgentMonitor.allowedScales, id: \.self) { sc in
                                let label = sc == 1.0 ? "标准 100%" : (sc == 1.1 ? "舒适 110%" : "大字 120%")
                                settingsChip(label, selected: abs(monitor.uiScale - sc) < 0.01) {
                                    monitor.setUIScale(sc)
                                }
                            }
                        }
                    }
                    settingsRow(title: "停靠边") {
                        HStack(spacing: 4) {
                            ForEach(DockEdge.allCases) { edge in
                                settingsChip(edge.name, selected: monitor.dockEdge == edge) { monitor.setDockEdge(edge) }
                            }
                        }
                    }
                    settingsRow(title: "防打扰") {
                        HStack(spacing: 4) {
                            settingsChip("仅点击展开", selected: !monitor.hoverAutoExpand) {
                                monitor.setHoverAutoExpand(!monitor.hoverAutoExpand)
                            }
                            settingsChip("最小化到菜单栏", selected: monitor.minimizedToMenuBar) {
                                monitor.setMinimizedToMenuBar(!monitor.minimizedToMenuBar)
                            }
                            Text("全局热键 ⌥I")
                                .font(.system(size: fs(11), weight: .semibold))
                                .foregroundColor(accentTextColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accentColor.opacity(0.12)))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("模块 · 开关与排序（拖动行可换序）")
                            .font(.system(size: fs(12), weight: .bold))
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

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("快捷资产管理（含 M7 决定档案 / 纠正日志）")
                                .font(.system(size: fs(12), weight: .bold))
                                .foregroundColor(secondaryTextColor)
                            Spacer()
                            Button(action: { monitor.resetQuickAssets() }) {
                                Text("恢复默认")
                                    .font(.system(size: fs(11), weight: .semibold))
                                    .foregroundColor(accentTextColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(accentColor.opacity(0.12)))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        ForEach(monitor.quickAssets) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.system(size: fs(11), weight: .semibold))
                                    .foregroundColor(accentTextColor)
                                Text(item.label)
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                Text(URL(fileURLWithPath: item.path).lastPathComponent)
                                    .font(.system(size: fs(11)))
                                    .foregroundColor(secondaryTextColor)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Button(action: { monitor.removeQuickAsset(id: item.id) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: fs(12)))
                                        .foregroundColor(Color(hex: "DC2626").opacity(0.82))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(monitor.panelIsDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                            )
                        }
                        HStack(spacing: 5) {
                            TextField(
                                "",
                                text: $monitor.newAssetLabel,
                                prompt: Text("名称").foregroundColor(secondaryTextColor.opacity(0.75))
                            )
                                .textFieldStyle(.plain)
                                .font(.system(size: fs(11)))
                                .foregroundColor(primaryTextColor)
                                .colorScheme(monitor.panelIsDark ? .dark : .light)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .frame(width: 78)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(monitor.panelIsDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                )
                            TextField(
                                "",
                                text: $monitor.newAssetPath,
                                prompt: Text("绝对路径或 URL").foregroundColor(secondaryTextColor.opacity(0.75))
                            )
                                .textFieldStyle(.plain)
                                .font(.system(size: fs(11)))
                                .foregroundColor(primaryTextColor)
                                .colorScheme(monitor.panelIsDark ? .dark : .light)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(monitor.panelIsDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                                )
                            Button(action: { monitor.addQuickAsset(label: monitor.newAssetLabel, path: monitor.newAssetPath) }) {
                                Text("添加")
                                    .font(.system(size: fs(11), weight: .bold))
                                    .foregroundColor(accentOnColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(accentColor))
                            }
                            .buttonStyle(PlainButtonStyle())
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
                .font(.system(size: fs(13), weight: .bold))
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
                .font(.system(size: fs(12), weight: selected ? .bold : .semibold))
                .foregroundColor(selected ? accentOnColor : secondaryTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? accentColor : (monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    func sectionSettingsRow(_ key: String) -> some View {
        let section = PanelSectionKey(rawValue: key)
        let enabled = monitor.isSectionEnabled(key)
        return HStack(spacing: 7) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: fs(12), weight: .bold))
                .foregroundColor(secondaryTextColor)
            Button(action: { monitor.toggleSection(key) }) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(enabled ? accentColor : secondaryTextColor)
            }
            .buttonStyle(PlainButtonStyle())
            Text(section?.name ?? key)
                .font(.system(size: fs(13), weight: enabled ? .bold : .semibold))
                .foregroundColor(enabled ? primaryTextColor : secondaryTextColor)
            Spacer(minLength: 0)
            Button(action: { monitor.moveSection(key, by: -1) }) {
                Image(systemName: "chevron.up").font(.system(size: fs(12), weight: .bold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(secondaryTextColor)
            Button(action: { monitor.moveSection(key, by: 1) }) {
                Image(systemName: "chevron.down").font(.system(size: fs(12), weight: .bold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(monitor.panelIsDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)))
    }

    func assetButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: fs(12)))
                Text(label).font(.system(size: fs(12), weight: .semibold))
            }
            .foregroundColor(secondaryTextColor)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 有界外骨骼自优化与墙钟透视带（0 点击首屏直达 + 聚类升格一键批红抽屉）
    @ViewBuilder
    var selfHarnessStripView: some View {
        let hs = monitor.harnessState
        let scoreGood = hs.sealOk && hs.loopScore == 100 && !hs.isStale
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: hs.sealOk ? "lock.shield.fill" : "exclamationmark.octagon.fill")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(scoreGood ? textGreen : textRed)
                    Text("裁判 \(hs.loopScore)/100")
                        .font(.system(size: fs(12), weight: .bold).monospacedDigit())
                        .foregroundColor(scoreGood ? textGreen : textRed)
                }
                .layoutPriority(1)

                Text("•")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                Text("有效 \(String(format: "%.1f", hs.effectivePct))% (\(Int(hs.effectiveExecMin.rounded()))m/\(Int(hs.totalWallMin.rounded()))m)")
                    .font(.system(size: fs(12), weight: .semibold).monospacedDigit())
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if hs.escalationCount > 0 {
                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            monitor.harnessDrawerExpanded.toggle()
                        }
                        monitor.onLayoutChange?()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: fs(11), weight: .bold))
                            Text("升格 \(hs.escalationCount)簇")
                                .font(.system(size: fs(12), weight: .bold).monospacedDigit())
                            Image(systemName: monitor.harnessDrawerExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: fs(11), weight: .bold))
                        }
                        .foregroundColor(textAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "FF9F0A").opacity(monitor.panelIsDark ? 0.20 : 0.14)))
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                    .layoutPriority(1)
                } else {
                    Text(hs.isStale ? "陈旧 \(hs.ageMin)m" : "0 待升格")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(hs.isStale ? textAmber : secondaryTextColor)
                        .layoutPriority(1)
                }
            }

            GeometryReader { geo in
                let totalW = max(20, geo.size.width)
                let effW = max(6, min(totalW, totalW * hs.effectiveRatio))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(secondaryTextColor.opacity(0.20))
                        .frame(width: totalW, height: 4)
                    Capsule()
                        .fill(Color(hex: "0A84FF"))
                        .frame(width: effW, height: 4)
                }
            }
            .frame(height: 4)

            if monitor.harnessDrawerExpanded && !hs.proposals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(hs.proposals.prefix(3))) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("\(item.signature) · 跨\(item.distinctSessions)单")
                                        .font(.system(size: fs(12), weight: .bold).monospacedDigit())
                                        .foregroundColor(primaryTextColor)
                                        .lineLimit(1)
                                    if item.shadowVerified {
                                        Text("✓ 沙箱已验")
                                            .font(.system(size: fs(11), weight: .bold))
                                            .foregroundColor(textGreen)
                                            .layoutPriority(1)
                                    }
                                }
                                Text("\(item.carrier) → \(item.recommendedFix)")
                                    .font(.system(size: fs(11), weight: .medium))
                                    .foregroundColor(secondaryTextColor)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button(action: {
                                if item.shadowVerified && !item.patchReportPath.isEmpty {
                                    monitor.copyToClipboard("python3 ~/.config/alma/scripts/apply-dreaming-patch.py --apply --report \"\(item.patchReportPath)\"", label: "一键合入已验补丁命令")
                                } else {
                                    monitor.copyToClipboard("批准机械升格 [\(item.signature)]：请按载体 \(item.carrier) 实施 \(item.recommendedFix) 并补齐先红后绿门禁", label: "A 批准指令")
                                }
                            }) {
                                Text(item.shadowVerified ? "A 合入" : "A 批升格")
                                    .font(.system(size: fs(11), weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: item.shadowVerified ? "059669" : "0A84FF")))
                            }
                            .buttonStyle(PressableScaleButtonStyle())
                            .layoutPriority(1)

                            Button(action: {
                                DispatchQueue.global(qos: .userInitiated).async {
                                    let proc = Process()
                                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                                    proc.arguments = [
                                        "/Users/l/Nutstore Files/Obsidian_/multi-agent/skills/ping-loop/scripts/pingloop_harness_propose.py",
                                        "--cooldown", item.signature,
                                        "--fast", "--quiet"
                                    ]
                                    proc.standardOutput = FileHandle.nullDevice
                                    proc.standardError = FileHandle.nullDevice
                                    try? proc.run()
                                }
                                monitor.copyToClipboard("已将 [\(item.signature)] 写入 7 天冷却止损", label: "7天冷却已生效")
                            }) {
                                Text("C 止损")
                                    .font(.system(size: fs(11), weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(monitor.panelIsDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)))
                            }
                            .buttonStyle(PressableScaleButtonStyle())
                            .layoutPriority(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(monitor.panelIsDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(squircleCardBackground)
    }

    // MARK: - M1 熔断露露专属决策卡（批奏折专区：直读 a-verifier-decisions/*-fused.md）
    var fusedDecisionBannerView: some View {
        let topCard = monitor.fusedCards.first
        let cardTitle = topCard?.title ?? "M1 轮次硬熔断停机保护（连续超 3 轮未收敛）"
        let cardSummary = topCard?.summary ?? "任务触发 exit 3 停机保护，已自动拦截下一轮派单，杜绝空烧 Token。"
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundColor(textRed)
                    .font(.system(size: fs(13), weight: .bold))
                Text(cardTitle)
                    .font(.system(size: fs(13), weight: .bold))
                    .foregroundColor(textRed)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("待露露终裁")
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(textAmber)
            }

            HStack(spacing: 8) {
                Text(cardSummary)
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(2)
                Spacer(minLength: 4)

                if let card = topCard {
                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: card.path))
                    }) {
                        Text("打开决策卡")
                            .font(.system(size: fs(12), weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        monitor.copyToClipboard("\(card.title)\n\(card.summary)\n路径：\(card.path)", label: "决策卡摘要")
                    }) {
                        Text("复制")
                            .font(.system(size: fs(12), weight: .bold))
                            .foregroundColor(secondaryTextColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: {
                    monitor.resolveFusedByLulu()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("A·终裁结案")
                    }
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
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
            ZStack {
                squircleCardBackground
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "EF4444").opacity(monitor.panelIsDark ? 0.16 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(hex: "EF4444").opacity(0.42), lineWidth: 1.0)
                    )
            }
        )
    }
    
    // v2.0 纯正交直线真实网络拓扑：
    // 上路正交直线：Ping -> Funnel 443 -> Mac Mini (AGY -- 0ms 总线 -- Alma) -> 局域网联调 -> 模拟电脑
    // 下路笔直水平绿线：Ping ———————— 模拟电脑 9011/9012（Tailscale SSH 直连 · 不经 Mac）
    var architectureTopologyView: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let macX = w * 0.31
                let macW = w * 0.38
                let macY: CGFloat = 10
                let macH: CGFloat = 80
                let topLineY: CGFloat = 52
                let botLineY: CGFloat = 132
                let pingX = w * 0.12
                let simX = w * 0.88
                let agyX = macX + macW * 0.27
                let almaX = macX + macW * 0.73

                ZStack {
                    // Mac Mini 虚线外框（置于上方，绝不遮挡下方 Ping->模拟电脑 直连线）
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "3B82F6").opacity(monitor.panelIsDark ? 0.08 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(secondaryTextColor.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .frame(width: macW, height: macH)
                        .position(x: macX + macW / 2, y: macY + macH / 2)

                    Text("Mac Mini 本地执行中台")
                        .font(.system(size: fs(11), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .position(x: macX + macW / 2, y: macY + 11)

                    // 正交直线 1：Ping 向上折右直入 Mac Mini（Funnel 443）
                    Path { path in
                        path.move(to: CGPoint(x: pingX, y: botLineY - 20))
                        path.addLine(to: CGPoint(x: pingX, y: topLineY))
                        path.addLine(to: CGPoint(x: macX, y: topLineY))
                    }
                    .stroke(Color(hex: "2563EB"), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Text("Funnel 443")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(textBlue)
                        .position(x: (pingX + macX) / 2, y: topLineY - 12)

                    // Mac 内部直线：AGY — Alma (0ms 本地总线)
                    Path { path in
                        path.move(to: CGPoint(x: agyX + 18, y: topLineY))
                        path.addLine(to: CGPoint(x: almaX - 18, y: topLineY))
                    }
                    .stroke(secondaryTextColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))

                    Text("0ms 总线")
                        .font(.system(size: fs(11), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .position(x: macX + macW / 2, y: topLineY - 11)

                    // 正交直线 2：Mac Mini 向右折下连模拟电脑（局域网联调）
                    Path { path in
                        path.move(to: CGPoint(x: macX + macW, y: topLineY))
                        path.addLine(to: CGPoint(x: simX, y: topLineY))
                        path.addLine(to: CGPoint(x: simX, y: botLineY - 20))
                    }
                    .stroke(Color(hex: "059669"), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [4, 3]))

                    Text("局域网联调")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(textGreen)
                        .position(x: (macX + macW + simX) / 2, y: topLineY - 12)

                    // 笔直水平绿实线（核心）：Ping ———————— 模拟电脑（Tailscale SSH 直连 · 不经 Mac）
                    Path { path in
                        path.move(to: CGPoint(x: pingX + 20, y: botLineY))
                        path.addLine(to: CGPoint(x: simX - 20, y: botLineY))
                    }
                    .stroke(Color(hex: "059669"), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

                    Text("Tailscale SSH 直连 · 不经 Mac")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(textGreen)
                        .position(x: w / 2, y: botLineY + 15)

                    // 节点：AGY（Mac 内左）
                    v2TopoNode(badge: "白", label: "AGY", color: Color(hex: "2563EB"), radius: 16, active: monitor.activePulses.contains { $0.source == "agy" || $0.target == "agy" })
                        .position(x: agyX, y: topLineY + 7)

                    // 节点：Alma（Mac 内右）
                    v2TopoNode(badge: "A", label: "Alma", color: Color(hex: "D97706"), radius: 16, active: monitor.activePulses.contains { $0.source == "alma" || $0.target == "alma" })
                        .position(x: almaX, y: topLineY + 7)

                    // 节点：Ping（左下）
                    v2TopoNode(badge: "P", label: "Ping (VM)", color: Color(hex: "7C3AED"), radius: 19, active: monitor.activePulses.contains { $0.source == "ping" || $0.target == "ping" })
                        .position(x: pingX, y: botLineY + 8)

                    // 节点：模拟电脑（右下）
                    v2TopoNode(badge: "算", label: "模拟电脑 9011", color: Color(hex: "059669"), radius: 19, active: false)
                        .position(x: simX, y: botLineY + 8)
                }
            }
            .frame(height: 178)

            // 底部 1 行诚实状态条
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(monitor.funnelOnline ? Color(hex: "2563EB") : Color(hex: "EF4444")).frame(width: 6, height: 6)
                    Text("Funnel 443")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(primaryTextColor)
                }
                HStack(spacing: 5) {
                    Circle().fill(monitor.tailscaleOnline ? Color(hex: "059669") : Color(hex: "EF4444")).frame(width: 6, height: 6)
                    Text("Tailscale 直连")
                        .font(.system(size: fs(11), weight: .bold))
                        .foregroundColor(primaryTextColor)
                }
                HStack(spacing: 5) {
                    Circle().fill(monitor.nutstoreOnline ? Color(hex: "10B981") : Color(hex: "EF4444")).frame(width: 6, height: 6)
                    Text("坚果云冷备")
                        .font(.system(size: fs(11), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                Spacer()
                Text(monitor.activePulses.isEmpty ? "脉冲静默" : "近 15s \(monitor.activePulses.reduce(0) { $0 + $1.count }) 次通讯")
                    .font(.system(size: fs(11), weight: .bold))
                    .foregroundColor(monitor.activePulses.isEmpty ? secondaryTextColor : textGreen)
            }
            .padding(.horizontal, 8).padding(.top, 4)
        }
        .padding(11)
        .background(squircleCardBackground)
    }

    func v2TopoNode(badge: String, label: String, color: Color, radius: CGFloat, active: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if active {
                    Circle()
                        .stroke(color.opacity(monitor.pulse ? 0.70 : 0.25), lineWidth: 2)
                        .frame(width: radius * 2 + 6, height: radius * 2 + 6)
                }
                Circle()
                    .fill(color)
                    .frame(width: radius * 2, height: radius * 2)
                Text(badge)
                    .font(.system(size: fs(12), weight: .bold))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: fs(11), weight: .bold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
        }
    }

    func channelCopyRow(tier: String, name: String, detail: String) -> some View {
        HStack(spacing: 5) {
            Text(tier)
                .font(.system(size: fs(12), weight: .bold))
                .foregroundColor(textGray)
                .frame(width: 40, alignment: .leading)
            Text(name)
                .font(.system(size: fs(12), weight: .bold))
                .foregroundColor(primaryTextColor)
            Text("· \(detail)")
                .font(.system(size: fs(12), weight: .semibold))
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
                    .font(.system(size: fs(14), weight: .bold))
                    .foregroundColor(agent.color)
            }
            Text(agent.short)
                .font(.system(size: fs(13), weight: .bold))
                .foregroundColor(primaryTextColor)
            Text("\(monitor.pendingCount(for: agent.key)) 待办")
                .font(.system(size: fs(12), weight: .semibold))
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
                let edges = monitor.activePulses.map { pulse -> (color: Color, a: CGPoint, b: CGPoint) in
                    let source = AgentRoster.identity(for: pulse.source)
                    let color = activePulseColor(for: source?.key ?? pulse.source)
                    return (color, CGPoint(x: anchorX(pulse.source), y: railY), CGPoint(x: anchorX(pulse.target), y: railY))
                }
                // 第一趟先绘全部连线与方向箭头，避免后绘线段压切先绘光点
                for edge in edges {
                    let dir: CGFloat = edge.b.x >= edge.a.x ? 1 : -1
                    let start = CGPoint(x: edge.a.x + dir * 22, y: railY)
                    let tip = CGPoint(x: edge.b.x - dir * 24, y: railY)

                    // V2：活动线使用高对比专色，不再直接取 agent 原色。
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: CGPoint(x: tip.x - dir * 6, y: railY))
                    context.stroke(line, with: .color(edge.color), lineWidth: 2.2)

                    // 方向箭头
                    var head = Path()
                    head.move(to: tip)
                    head.addLine(to: CGPoint(x: tip.x - dir * 8, y: railY - 4.5))
                    head.addLine(to: CGPoint(x: tip.x - dir * 8, y: railY + 4.5))
                    head.closeSubpath()
                    context.fill(head, with: .color(edge.color))
                }
                // 第二趟统一绘制全部光点（每条边 1 个、共享 2.4s 周期、0.3s 相位差）
                for (edgeIndex, edge) in edges.enumerated() {
                    let cycle: Double = 2.4
                    let phase = (now / cycle + Double(edgeIndex) * 0.3 / cycle)
                        .truncatingRemainder(dividingBy: 1.0)
                    let x = edge.a.x + (edge.b.x - edge.a.x) * CGFloat(phase)
                    let glow = CGRect(x: x - 4, y: railY - 4, width: 8, height: 8)
                    let core = CGRect(x: x - 3, y: railY - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: glow), with: .color(edge.color.opacity(0.20)))
                    context.fill(Path(ellipseIn: core), with: .color(edge.color.opacity(0.92)))
                    context.fill(Path(ellipseIn: core.insetBy(dx: 1.5, dy: 1.5)), with: .color(.white.opacity(0.95)))
                }
            }
            .frame(width: width, height: 128)
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
                // Header: 区分「需露露拍板（高危/熔断）」与「Agent 内部自动互验」
                let isLuluCard = (item.stage == "high-risk-blocked" || item.file.contains("escalate-highrisk-"))
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isLuluCard ? Color(hex: "8B5CF6") : Color(hex: "3B82F6"))
                            .frame(width: 18, height: 18)
                        Image(systemName: isLuluCard ? "bell.badge.fill" : "bolt.fill")
                            .font(.system(size: fs(12), weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(isLuluCard ? "高危拦截 · 待你拍板（\(monitor.totalLuluActions)）" : "Agent 内部互验中（\(monitor.totalAgentConfirms) · 免人工）")
                        .font(.system(size: fs(13), weight: .bold))
                        .foregroundColor(isLuluCard ? textPurple : textBlue)
                    
                    Spacer()
                    
                    if count > 1 {
                        HStack(spacing: 6) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx - 1 + count) % count
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(primaryTextColor)
                                    .frame(width: 18, height: 18)
                                    .background(squircleCardBackground)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("\(safeIdx + 1)/\(count)")
                                .font(.system(size: fs(13), weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryTextColor)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    monitor.activeConfirmIndex = (safeIdx + 1) % count
                                }
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: fs(12), weight: .bold))
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
                            .font(.system(size: fs(13), weight: .bold))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(1)
                        Spacer()
                        lifecycleStepperView(stage: item.stage)
                    }
                    if !item.stepNote.isEmpty {
                        HStack(spacing: 4) {
                            Circle().fill(accentColor).frame(width: 5, height: 5)
                            Text(item.stepNote)
                                .font(.system(size: fs(11), weight: .semibold))
                                .foregroundColor(accentColor)
                                .lineLimit(1)
                        }
                    }
                    
                    // Route & Artifact Link
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            let isEscalate = item.file.contains("escalate-highrisk-")
                            Text(isEscalate ? "转呈(\(item.from))" : "已送达(\(item.from))")
                                .font(.system(size: fs(13), weight: .semibold))
                                .foregroundColor(textBlue)
                            Text("➔")
                                .font(.system(size: fs(12), weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Text(isEscalate ? "待发起方(\(item.to))核销" : "待 \(item.to) 点确认")
                                .font(.system(size: fs(13), weight: .bold))
                                .foregroundColor(textPurple)
                        }
                        
                        if !item.artifacts.isEmpty {
                            Text("•")
                                .font(.system(size: fs(12), weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Button(action: {
                                let ap = item.artifacts.hasPrefix("/") ? item.artifacts : "\(monitor.rootPath)/../\(item.artifacts)"
                                NSWorkspace.shared.open(URL(fileURLWithPath: ap))
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right.square.fill")
                                        .font(.system(size: fs(12), weight: .semibold))
                                    Text("产物: \(item.artifacts)")
                                        .font(.system(size: fs(13), weight: .semibold))
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
                                    .font(.system(size: fs(12), weight: .semibold))
                                Text(monitor.expandedTaskId == item.id ? "收起" : "重点")
                                    .font(.system(size: fs(12), weight: .bold))
                            }
                            .foregroundColor(monitor.expandedTaskId == item.id ? accentOnColor : accentTextColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
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
                                .font(.system(size: fs(12), weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // 批奏折动作栏：A/B 机检 + 通过(confirm) + 打回(reject)
                    HStack(spacing: 6) {
                        let obsTag = monitor.observeResults[item.file] ?? "待自动机检 · B级需复核"
                        Text(obsTag)
                            .font(.system(size: fs(11), weight: .bold))
                            .foregroundColor(obsTag.contains("通过") || obsTag.contains("PASS") ? textGreen : (obsTag.contains("不通过") || obsTag.contains("FAIL") || obsTag.contains("熔断") ? textRed : textPurple))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill((obsTag.contains("PASS") ? Color(hex: "10B981") : Color(hex: "8B5CF6")).opacity(0.14)))
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Button(action: {
                            monitor.runObserveVerify(file: item.file)
                        }) {
                            Text("机检")
                                .font(.system(size: fs(12), weight: .bold))
                                .foregroundColor(accentTextColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(accentColor.opacity(monitor.panelIsDark ? 0.20 : 0.12)))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            monitor.confirmTask(file: item.file, dispatcher: item.to)
                        }) {
                            Text("通过")
                                .font(.system(size: fs(12), weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: "059669")))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            monitor.toggleRejectTarget(item.file)
                        }) {
                            Text("打回")
                                .font(.system(size: fs(12), weight: .bold))
                                .foregroundColor(textRed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color(hex: "EF4444").opacity(monitor.panelIsDark ? 0.22 : 0.12)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if monitor.rejectTargetFile == item.file {
                        HStack(spacing: 6) {
                            TextField("输入一句话打回原因（回车提交）", text: $monitor.rejectReasonText)
                                .textFieldStyle(.plain)
                                .font(.system(size: fs(12), weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.white.opacity(0.9))
                                )
                                .onSubmit {
                                    monitor.rejectTask(file: item.file, dispatcher: item.to, reason: monitor.rejectReasonText)
                                }

                            Button(action: {
                                monitor.rejectTask(file: item.file, dispatcher: item.to, reason: monitor.rejectReasonText)
                            }) {
                                Text("确认打回")
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color(hex: "EF4444")))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                monitor.toggleRejectTarget(nil)
                            }) {
                                Text("取消")
                                    .font(.system(size: fs(12), weight: .semibold))
                                    .foregroundColor(secondaryTextColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    // 点开卡片展开核心提炼重点
                    if monitor.expandedTaskId == item.id {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(accentTextColor)
                                Text("核心提炼重点")
                                    .font(.system(size: fs(13), weight: .bold))
                                    .foregroundColor(accentTextColor)
                            }
                            Text(item.highlights.isEmpty ? "（本单据暂无正文摘要）" : item.highlights)
                                .font(.system(size: fs(13), weight: .semibold))
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

    // M6 飞轮真实 Δ 仪表卡（直读 pingloop-health.json 与 pingloop-convergence.jsonl）
    @ViewBuilder
    var autoloopReadyHeroCardView: some View {
        let ds = monitor.deltaState
        let healthFresh = ds.loaded && !ds.isStale
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((healthFresh ? Color(hex: "059669") : Color(hex: "D97706")).opacity(monitor.panelIsDark ? 0.20 : 0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: healthFresh ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: fs(16), weight: .bold))
                    .foregroundColor(healthFresh ? textGreen : textAmber)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(totalPending == 0 ? "全网架构就绪 · 0 积压待办" : "全网链路就绪 · 0 待你验收")
                        .font(.system(size: fs(13), weight: .bold))
                        .foregroundColor(primaryTextColor)
                    Text("•")
                        .foregroundColor(secondaryTextColor)
                    Text(healthFresh ? "体检 \(ds.verdict)" : (ds.loaded ? "快照陈旧(\(ds.healthAgeMin)m)" : "快照待刷新"))
                        .font(.system(size: fs(13), weight: .semibold))
                        .foregroundColor(healthFresh ? textGreen : textAmber)
                }
                .lineLimit(1)
                
                HStack(spacing: 5) {
                    if !ds.loaded || ds.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: fs(12), weight: .semibold))
                            .foregroundColor(textAmber)
                        Text(ds.loaded ? "健康快照超 30m（M4）· \(ds.verifierSummary)" : "健康快照未就绪（M4）· \(ds.verifierSummary)")
                            .font(.system(size: fs(12), weight: .semibold))
                            .foregroundColor(textAmber)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: fs(12), weight: .semibold))
                            .foregroundColor(accentTextColor)
                        Text("核销 +\(ds.todayConfirmed) · 待验 \(ds.confirm)\(ds.confirmDeltaText) · 僵尸 \(ds.zombie) · \(ds.verifierSummary)")
                            .font(.system(size: fs(12), weight: .semibold))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            Button(action: {
                monitor.triggerVerifyAndReconcile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: fs(13), weight: .bold))
                    Text("全网核验")
                        .font(.system(size: fs(13), weight: .bold))
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
        .padding(.vertical, 6)
        .background(squircleCardBackground)
        .help(ds.fullTooltip(tokenTotal: monitor.tokenTotal, cacheRate: monitor.tokenCacheRate))
    }

    // 横向三等分 Agent 平衡卡片 (3 Balanced Cards)
    func agentBalanceCard(icon: String, iconBg: Color, textTint: Color, title: String, subtitle: String, hasPending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(iconBg)
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: fs(13), weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(title)
                        .font(.system(size: fs(13), weight: .bold))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    if hasPending {
                        Circle()
                            .fill(iconBg)
                            .frame(width: 7, height: 7)
                    }
                }
                Text(subtitle)
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(hasPending ? textTint : secondaryTextColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(squircleCardBackground)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
    
    // 四段架构履约轴 (派单 ➔ 接单 ➔ 待验 ➔ 结案)
    func lifecycleStepperView(stage: String) -> some View {
        let isRelay = stage == "relay"
        let hasAccepted = stage == "accepted" || isRelay || stage == "submitted" || stage == "confirmed"
        let hasSubmitted = stage == "submitted" || stage == "confirmed"
        return HStack(spacing: 2) {
            stepperNode(name: "派单", active: true, done: stage != "dispatched")
            Text("›").font(.system(size: fs(11), weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: "接单", active: hasAccepted, done: isRelay || hasSubmitted)
            Text("›").font(.system(size: fs(11), weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: isRelay ? "接力" : "待验", active: isRelay || hasSubmitted, done: stage == "confirmed", highlight: stage == "submitted" || isRelay)
            Text("›").font(.system(size: fs(11), weight: .semibold)).foregroundColor(secondaryTextColor)
            stepperNode(name: "结案", active: stage == "confirmed", done: stage == "confirmed")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func stepperNode(name: String, active: Bool, done: Bool, highlight: Bool = false) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(highlight ? Color(hex: "8B5CF6") : (active ? (done ? Color(hex: "10B981") : accentColor) : secondaryTextColor.opacity(0.35)))
                .frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: fs(11), weight: highlight || done || active ? .bold : .semibold))
                .foregroundColor(highlight ? (monitor.panelIsDark ? Color(hex: "BF5AF2") : Color(hex: "6D28D9")) : (active ? (done ? (monitor.panelIsDark ? Color(hex: "30D158") : Color(hex: "047857")) : primaryTextColor) : secondaryTextColor))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 4)
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
                    .font(.system(size: fs(13), weight: .semibold))
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
        let allTasks = agentTasks(agent)
        let todayPrefix = monitor.todayDatePrefix
        let todayTasksCount = allTasks.filter { $0.date.hasPrefix(todayPrefix) }.count
        let q = monitor.drawerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tasks = allTasks.filter { t in
            if monitor.drawerTodayOnly && !t.date.hasPrefix(todayPrefix) { return false }
            if q.isEmpty { return true }
            return t.title.lowercased().contains(q)
                || t.file.lowercased().contains(q)
                || t.from.lowercased().contains(q)
                || t.to.lowercased().contains(q)
        }
        let dones = agentDoneTasks(agent)
        return VStack(spacing: 8) {
            // Header Row（高对比底座，抗深色壁纸透底）
            HStack {
                Button(action: {
                    monitor.setDrawerAgent(nil)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: fs(13), weight: .bold))
                        Text("返回")
                            .font(.system(size: fs(13), weight: .bold))
                    }
                    .foregroundColor(accentTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(monitor.panelIsDark ? accentColor.opacity(0.24) : Color.white.opacity(0.84))
                    )
                }
                .buttonStyle(PressableScaleButtonStyle())
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle().fill(AgentRoster.identity(for: agent)?.color ?? accentColor)
                        .frame(width: 8, height: 8)
                    Text("\(agentDisplayName(agent)) 收件箱 · \(tasks.count)/\(allTasks.count)")
                        .font(.system(size: fs(13), weight: .bold))
                        .foregroundColor(primaryTextColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.10) : Color.white.opacity(0.78))
                )
                
                Spacer()
                
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "\(monitor.rootPath)/\(agent)"))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: fs(13)))
                        Text("访达")
                            .font(.system(size: fs(13), weight: .semibold))
                    }
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.12) : Color.white.opacity(0.84))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 6)
            .padding(.horizontal, 14)

            // Search + Today filter bar (30pt)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                    TextField("搜索标题 / 文件名 / 发件人…", text: $monitor.drawerSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: fs(12), weight: .semibold))
                        .foregroundColor(primaryTextColor)
                    if !monitor.drawerSearchText.isEmpty {
                        Button(action: { monitor.drawerSearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: fs(12)))
                                .foregroundColor(secondaryTextColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(squircleCardBackground)

                Button(action: { monitor.drawerTodayOnly.toggle() }) {
                    Text("仅看今日 (\(todayTasksCount))")
                        .font(.system(size: fs(12), weight: .bold))
                        .foregroundColor(monitor.drawerTodayOnly ? accentOnColor : secondaryTextColor)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(monitor.drawerTodayOnly ? accentColor : (monitor.panelIsDark ? Color.white.opacity(0.10) : Color.white.opacity(0.78)))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            
            // Task List + Done Feed Section (锁定最大高并加 layoutPriority 防止 100+ 工单顶出页头)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    // 1. Pending Tasks Section (if any)
                    if !tasks.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(tasks) { task in
                                let isRelay = task.stage == "relay"
                                let isOverdue = task.eta.hasPrefix("超时") || task.eta.hasPrefix("滞留")
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(isRelay ? Color(hex: "F59E0B").opacity(0.22) : (task.stage == "accepted" ? Color(hex: "3B82F6").opacity(0.18) : (task.stage == "submitted" ? Color(hex: "8B5CF6").opacity(0.18) : (isOverdue ? Color(hex: "EF4444").opacity(0.18) : Color(hex: "FF9500").opacity(0.18)))))
                                                .frame(width: 24, height: 24)
                                            Image(systemName: isRelay ? "figure.run" : (task.stage == "accepted" ? "bolt.fill" : (task.stage == "submitted" ? "bell.badge.fill" : (isOverdue ? "clock.badge.exclamationmark.fill" : "doc.text.fill"))))
                                                .font(.system(size: fs(13), weight: .bold))
                                                .foregroundColor(isRelay ? textAmber : (task.stage == "accepted" ? textBlue : (task.stage == "submitted" ? Color(hex: "8B5CF6") : (isOverdue ? textRed : textAmber))))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(.system(size: fs(13), weight: .bold))
                                                .foregroundColor(primaryTextColor)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 4) {
                                                lifecycleStepperView(stage: task.stage)
                                                Text("•").font(.system(size: fs(11), weight: .semibold)).foregroundColor(secondaryTextColor)
                                                Text("\(task.from)➔\(task.to)")
                                                    .font(.system(size: fs(11), weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .lineLimit(1)
                                                if !task.eta.isEmpty {
                                                    Text("• \(task.eta)")
                                                        .font(.system(size: fs(11), weight: .bold))
                                                        .foregroundColor(isOverdue ? textRed : (isRelay ? textAmber : textBlue))
                                                        .lineLimit(1)
                                                }
                                            }
                                            if !task.stepNote.isEmpty {
                                                HStack(spacing: 4) {
                                                    Circle().fill(accentColor).frame(width: 4.5, height: 4.5)
                                                    Text(task.stepNote)
                                                        .font(.system(size: fs(11), weight: .semibold))
                                                        .foregroundColor(accentColor)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Action buttons (重点 / 复制 / 已读 / 原文)
                                        HStack(spacing: 4) {
                                            Button(action: {
                                                monitor.toggleTaskExpanded(task.id)
                                            }) {
                                                Text(monitor.expandedTaskId == task.id ? "收起" : "重点")
                                                    .font(.system(size: fs(12), weight: .bold))
                                                    .foregroundColor(monitor.expandedTaskId == task.id ? accentOnColor : accentTextColor)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule().fill(monitor.expandedTaskId == task.id ? accentColor : accentColor.opacity(monitor.panelIsDark ? 0.20 : 0.10))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(task.file)"
                                                let txt = "\(task.title)\n路径：\(path)\n摘要：\(task.highlights.isEmpty ? "（无）" : task.highlights)"
                                                monitor.copyToClipboard(txt, label: "任务摘要")
                                            }) {
                                                Text("复制")
                                                    .font(.system(size: fs(12), weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())

                                            Button(action: {
                                                monitor.markTaskRead(box: agent, file: task.file)
                                            }) {
                                                Text("已读")
                                                    .font(.system(size: fs(12), weight: .bold))
                                                    .foregroundColor(textGreen)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule().fill(Color(hex: "10B981").opacity(monitor.panelIsDark ? 0.18 : 0.12))
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                let path = "\(monitor.rootPath)/\(agent)/\(task.file)"
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            }) {
                                                Text("原文")
                                                    .font(.system(size: fs(12), weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
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
                                                    .font(.system(size: fs(12), weight: .bold))
                                                    .foregroundColor(accentTextColor)
                                                Text("核心提炼重点")
                                                    .font(.system(size: fs(13), weight: .bold))
                                                    .foregroundColor(accentTextColor)
                                            }
                                            Text(task.highlights.isEmpty ? "（本单据暂无正文摘要）" : task.highlights)
                                                .font(.system(size: fs(13), weight: .semibold))
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
                    } else if !allTasks.isEmpty {
                        HStack(spacing: 8) {
                            Text("没有匹配当前筛选条件的未读任务")
                                .font(.system(size: fs(13), weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                            Button(action: {
                                monitor.drawerSearchText = ""
                                monitor.drawerTodayOnly = false
                            }) {
                                Text("清除筛选")
                                    .font(.system(size: fs(12), weight: .bold))
                                    .foregroundColor(accentTextColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(accentColor.opacity(0.12)))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 10)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: fs(13), weight: .bold))
                                .foregroundColor(textGreen)
                            Text("当前无积压待办 · 全员就绪")
                                .font(.system(size: fs(13), weight: .bold))
                                .foregroundColor(textGreen)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 2. Done Feed Section (Recent Completed Replies)
                    if !dones.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: fs(12), weight: .semibold))
                                    .foregroundColor(secondaryTextColor)
                                Text("最新结案回信 · 已办结流")
                                    .font(.system(size: fs(13), weight: .bold))
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
                                                    .font(.system(size: fs(12), weight: .bold))
                                                    .foregroundColor(textGreen)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(done.title)
                                                    .font(.system(size: fs(13), weight: .bold))
                                                    .foregroundColor(primaryTextColor)
                                                    .lineLimit(1)
                                                HStack(spacing: 4) {
                                                    Text("回件: \(done.from) ➔ \(done.to)")
                                                        .font(.system(size: fs(12), weight: .semibold))
                                                        .foregroundColor(secondaryTextColor)
                                                    Text("•").font(.system(size: fs(12), weight: .semibold)).foregroundColor(secondaryTextColor)
                                                    Text(done.date)
                                                        .font(.system(size: fs(12), weight: .semibold))
                                                        .foregroundColor(secondaryTextColor)
                                                }
                                            }
                                            Spacer()
                                            
                                            Button(action: {
                                                monitor.toggleTaskExpanded(done.id)
                                            }) {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: fs(12), weight: .semibold))
                                                    Text(monitor.expandedTaskId == done.id ? "收起" : "重点")
                                                        .font(.system(size: fs(12), weight: .bold))
                                                }
                                                .foregroundColor(monitor.expandedTaskId == done.id ? accentOnColor : accentTextColor)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 4)
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
                                                    .font(.system(size: fs(12), weight: .semibold))
                                                    .foregroundColor(secondaryTextColor)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
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
                                                        .font(.system(size: fs(12), weight: .bold))
                                                        .foregroundColor(accentTextColor)
                                                    Text("核心提炼重点")
                                                        .font(.system(size: fs(13), weight: .bold))
                                                        .foregroundColor(accentTextColor)
                                                }
                                                Text(done.highlights.isEmpty ? "（本回信暂无正文摘要）" : done.highlights)
                                                    .font(.system(size: fs(13), weight: .semibold))
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
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .layoutPriority(1)
            
            // Bottom Guidance Line
            HStack(spacing: 5) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: fs(12), weight: .semibold))
                    .foregroundColor(textAmber)
                Text("露露掌握最高裁决权 · 见真实回信与产物方可收口")
                    .font(.system(size: fs(13), weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(monitor.panelIsDark ? Color.white.opacity(0.08) : Color.white.opacity(0.78))
            )
            .padding(.bottom, 8)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 卡片层（对标 Apple WWDC25 HIG：外层独享原生 NSGlassEffectView，内容层不叠第二层玻璃，改用高区分度明度薄片 + 顶底镜面高光边 + 扎实投影）。
    @ViewBuilder
    var squircleCardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let cardFill: Color = {
            switch monitor.skin {
            case .glass:
                return monitor.panelIsDark
                    ? Color(hex: "141D2E").opacity(0.58)
                    : Color.white.opacity(0.78)
            case .obsidian:
                return Color.white.opacity(0.11)
            case .ceramic:
                return monitor.panelIsDark
                    ? Color(hex: "2A2620").opacity(0.84)
                    : Color(hex: "FBF7EE").opacity(0.90)
            }
        }()
        let borderGradient = LinearGradient(
            stops: monitor.panelIsDark
                ? [
                    .init(color: Color.white.opacity(0.42), location: 0.0),
                    .init(color: Color.white.opacity(0.16), location: 0.45),
                    .init(color: Color.white.opacity(0.09), location: 1.0),
                ]
                : [
                    .init(color: Color.white.opacity(0.96), location: 0.0),
                    .init(color: Color.black.opacity(0.12), location: 0.50),
                    .init(color: Color.black.opacity(0.20), location: 1.0),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        shape
            .fill(cardFill)
            .overlay(
                shape.stroke(borderGradient, lineWidth: 1.0)
            )
            .shadow(
                color: Color.black.opacity(monitor.panelIsDark ? 0.46 : 0.12),
                radius: 4,
                y: 2
            )
    }

    /// 底部资产条：与内容卡片同源高对比薄片，增强底部边界清晰度。
    @ViewBuilder
    var assetsRowBackground: some View {
        squircleCardBackground
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
                ? Color(hex: "0B1526").opacity(usesHighTransmissionGlass ? 0.46 : 0.78)
                : Color(hex: "EAF4FF").opacity(usesHighTransmissionGlass ? 0.28 : 0.34)
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
            // 压薄色罩，把折射留给底层原生 NSGlassEffectView，让外层玻璃与内层卡片形成真实明度分层
            return monitor.panelIsDark
                ? Color(hex: "0C1424").opacity(usesHighTransmissionGlass ? 0.04 : 0.08)
                : Color(hex: "EDF4FF").opacity(usesHighTransmissionGlass ? 0.04 : 0.05)
        case .obsidian:
            return Color(hex: "050506").opacity(monitor.panelIsDark ? 0.78 : 0.88)
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
                ? NSColor(srgbRed: 0.043, green: 0.082, blue: 0.149, alpha: usesHighTransmissionGlass ? 0.12 : 0.24)
                : NSColor(srgbRed: 0.820, green: 0.895, blue: 0.995, alpha: usesHighTransmissionGlass ? 0.08 : 0.14)
        case .obsidian:
            return NSColor(srgbRed: 0.020, green: 0.020, blue: 0.024, alpha: 0.55)
        case .ceramic:
            return monitor.panelIsDark
                ? NSColor(srgbRed: 0.165, green: 0.149, blue: 0.125, alpha: 0.45)
                : NSColor(srgbRed: 0.965, green: 0.945, blue: 0.906, alpha: 0.35)
        }
    }

    // Dynamic Typography Colors（一二级拉开明度层次，同时保持 WCAG ≥4.5:1）
    var primaryTextColor: Color {
        monitor.panelIsDark ? Color.white : Color(hex: "000000")
    }
    
    var secondaryTextColor: Color {
        monitor.panelIsDark ? Color(hex: "D1D5DB") : Color(hex: "374151")
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
        case .notification: return evenCeil(340 * uiScale)
        case .expanded:
            return evenCeil(560 * uiScale)
        }
    }
    
    var contentHeight: CGFloat {
        switch monitor.currentMode {
        case .compact: return evenCeil(40 * uiScale)
        case .notification: return evenCeil(38 * uiScale)
        case .expanded:
            return evenCeil(monitor.expandedContentHeight * uiScale)
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
        if monitor.totalLuluActions > 0 {
            parts.append("\(monitor.totalLuluActions)待你拍板")
        }
        if monitor.totalAgentConfirms > 0 {
            parts.append("\(monitor.totalAgentConfirms)互验")
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
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private static weak var sharedHotKeyDelegate: AppDelegate?

    var hoverTimer: Timer?
    var autoHoverExpanded = false
    var suppressHoverUntilExit = false
    var hoverOutsideSince: Date?
    var hoverInsideSince: Date?
    /// 仅快照自测使用：让定时轮询也采用同一假鼠标点，模拟真实指针停留。
    var hoverOverridePoint: NSPoint?
    private var agentResumeFactsDumped = 0

    var themeAutoItem: NSMenuItem?
    var themeLightItem: NSMenuItem?
    var themeDarkItem: NSMenuItem?
    var minimizeItem: NSMenuItem?
    var dndItem: NSMenuItem?
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
        setupGlobalHotKey()

        monitor.onModeChange = { [weak self] mode in
            guard let self = self else { return }
            if mode == .expanded {
                self.updatePanelFrame(for: .expanded)
                self.islandPanel.orderFrontRegardless()
            } else {
                self.updatePanelFrame(for: .compact)
                if self.monitor.minimizedToMenuBar {
                    self.islandPanel.orderOut(nil)
                }
            }
        }

        monitor.onMinimizeChange = { [weak self] minimized in
            guard let self = self else { return }
            if minimized {
                self.autoHoverExpanded = false
                self.monitor.showSettings = false
                self.monitor.currentMode = .compact
                self.islandPanel.orderOut(nil)
            } else {
                self.updatePanelFrame(for: self.monitor.currentMode)
                self.islandPanel.orderFrontRegardless()
            }
            self.updateMenuCheckmarks()
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
                        if case .compact = self.monitor.currentMode {
                            self.monitor.setMode(.expanded)
                        }
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

    /// 自测取证：把确认条当前实读到的文字/按钮状态落盘（不弹任何系统模态框）。
    private func dumpResumeConfirmFacts() {
        guard let out = ProcessInfo.processInfo.environment["AGENT_ISLAND_ALERT_INFO_OUT"], !out.isEmpty else { return }
        let monitor = self.monitor
        let facts: [String: Any] = [
            "pending": monitor.resumeConfirmPending,
            "backlog_count": monitor.resumeConfirmBacklog,
            "confirm_text": AgentMonitor.resumeConfirmationText(backlogCount: monitor.resumeConfirmBacklog),
            "primary_button": "只重放 \(AgentMonitor.resumeBacklogDefault) 张",
            "secondary_button": "取消（保持暂停）",
            "panel_mode": String(describing: monitor.currentMode),
        ]
        if let d = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: out))
        }
        if agentResumeFactsDumped < 1 { agentResumeFactsDumped += 1 }
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
        _ = NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
        guard NSApp.activationPolicy() == .accessory, !NSApp.isActive else {
            VirtualIslandDisplay.stop("cannot run as a background accessory (policy=\(NSApp.activationPolicy().rawValue), active=\(NSApp.isActive))")
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

        // 「点恢复 → 先出确认条」自测：造出暂停态，再走面板那颗按钮的同一条入口 toggleAgyWakePaused。
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_SELFTEST_TAP_RESUME"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                let pauseURL = self.monitor.stateDirForSelfTest().appendingPathComponent("agy-turn.paused")
                try? FileManager.default.createDirectory(at: pauseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? "paused_by_selftest\n".data(using: .utf8)?.write(to: pauseURL, options: .atomic)
                self.monitor.reloadWakeStateForSelfTest()
                self.monitor.toggleAgyWakePaused()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.dumpResumeConfirmFacts()
                }
            }
        }

        // 机械自测：导出「确认条文案 + 两个按钮的实际效果」，并用桩脚本证明重放参数就是 --max-backlog 1。
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_SELFTEST_RESUME"] == "1",
           let outPath = ProcessInfo.processInfo.environment["AGENT_ISLAND_SELFTEST_OUT"], !outPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self else { return }
                let backlog = AgentMonitor.backlogCount()
                let text = AgentMonitor.resumeConfirmationText(backlogCount: backlog)
                var facts: [String: Any] = [
                    "backlog_count": backlog,
                    "confirm_text": text,
                    "cancel_keeps_paused": AgentMonitor.resumeBacklogDefault,
                    "replay_limit": AgentMonitor.resumeBacklogDefault,
                    "env_pause_marker_before": self.monitor.resumeConfirmPending,
                ]
                // 走一遍「取消」：确认条消失、暂停标记仍在（不会偷偷重放）
                self.monitor.toggleAgyWakePaused()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    facts["pending_after_toggle"] = self.monitor.resumeConfirmPending
                    facts["pause_marker_after_toggle"] = FileManager.default.fileExists(
                        atPath: self.monitor.stateDirForSelfTest().appendingPathComponent("agy-turn.paused").path)
                    self.monitor.cancelResumeConfirmation()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        facts["pending_after_cancel"] = self.monitor.resumeConfirmPending
                        self.monitor.confirmResume()   // 唯一会真重放的那一下
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            let logURL = self.monitor.stateDirForSelfTest().appendingPathComponent("island-resume.log")
                            facts["resume_log"] = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                            facts["pending_after_confirm"] = self.monitor.resumeConfirmPending
                            if let d = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]) {
                                try? d.write(to: URL(fileURLWithPath: outPath))
                            }
                        }
                    }
                }
            }
        }


        monitor.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.updatePanelFrame(for: mode)
            self.verifyVisibleVirtualPanel(phase: "\(mode)", on: self.virtualScreenOrExit(id: id))
        }
        if ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_EXPAND"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.monitor.setMode(.expanded)
                if ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_TOPOLOGY"] == "1" {
                    self.monitor.showTopology = true
                    self.updatePanelFrame(for: .expanded)
                    self.verifyVisibleVirtualPanel(phase: "topology", on: self.virtualScreenOrExit(id: id))
                } else if ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_SETTINGS"] == "1" {
                    self.monitor.showSettings = true
                    self.updatePanelFrame(for: .expanded)
                    self.verifyVisibleVirtualPanel(phase: "settings", on: self.virtualScreenOrExit(id: id))
                } else if let drawer = ProcessInfo.processInfo.environment["AGENT_ISLAND_TEST_DRAWER"], !drawer.isEmpty {
                    self.monitor.selectedDrawerAgent = drawer
                    self.updatePanelFrame(for: .expanded)
                    self.verifyVisibleVirtualPanel(phase: "drawer", on: self.virtualScreenOrExit(id: id))
                }
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
        guard islandPanel != nil, islandPanel.isVisible, !monitor.minimizedToMenuBar else {
            hoverInsideSince = nil
            return
        }
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
        case .compact, .notification:
            // 默认勿扰（仅点击展开）；即使主动开启靠近展开，也禁止拖窗按键时触发并收窄到胶囊本体内部。
            guard monitor.hoverAutoExpand else {
                hoverInsideSince = nil
                suppressHoverUntilExit = false
                return
            }
            guard NSEvent.pressedMouseButtons == 0 else {
                hoverInsideSince = nil
                return
            }
            let hot = frame.insetBy(dx: 4, dy: 4)
            guard hot.contains(mouse) else {
                suppressHoverUntilExit = false
                hoverInsideSince = nil
                return
            }
            guard !suppressHoverUntilExit else { return }
            if hoverInsideSince == nil { hoverInsideSince = Date() }
            // 胶囊本体内停留 0.45s 再展开，彻底避免划过/关网页/拖窗误触
            if Date().timeIntervalSince(hoverInsideSince ?? Date()) >= 0.45 {
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
        menu.addItem(makeItem("打开/收起中控台 (⌥I)", "rectangle.topthird.inset.filled", #selector(toggleIsland)))
        let minIt = makeItem("最小化到菜单栏（隐藏胶囊）", "eye.slash", #selector(toggleMinimizedToMenuBar), key: "m")
        menu.addItem(minIt)
        minimizeItem = minIt
        let dndIt = makeItem("勿扰模式（仅点击展开）", "moon.zzz", #selector(toggleDoNotDisturb), key: "d")
        menu.addItem(dndIt)
        dndItem = dndIt
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
        for sc in AgentMonitor.allowedScales {
            let percent = Int((sc * 100).rounded())
            let label = percent == 100 ? "标准 100%" : (percent == 110 ? "舒适 110%" : "大字 120%")
            let it = makeItem(label, "arrow.up.left.and.arrow.down.right", #selector(setUIScaleAction(_:)))
            it.tag = percent
            appearanceMenu.addItem(it)
            scaleMenuItems[percent] = it
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
        if !monitor.minimizedToMenuBar {
            islandPanel.orderFrontRegardless()
        }
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
        
        let scale = CGFloat(monitor.uiScale)
        switch mode {
        case .compact:
            windowWidth = monitor.preferredCompactWidth + 24
            windowHeight = evenCeil(40 * scale) + 8
        case .notification:
            windowWidth = evenCeil(340 * scale) + 24
            windowHeight = evenCeil(38 * scale) + 8
        case .expanded:
            windowWidth = evenCeil(560 * scale) + 24
            windowHeight = evenCeil(monitor.expandedContentHeight * scale) + 16
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
    
    private func setupGlobalHotKey() {
        guard virtualDisplayID == nil else { return }
        AppDelegate.sharedHotKeyDelegate = self
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    AppDelegate.sharedHotKeyDelegate?.toggleIsland()
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &hotKeyHandler
        )
        let hotKeyID = EventHotKeyID(signature: 0x41494C44, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_I),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    @objc func toggleIsland() {
        if monitor.currentMode == .expanded {
            monitor.setMode(.compact)
        } else {
            monitor.setMode(.expanded)
            if !islandPanel.isVisible {
                updatePanelFrame(for: .expanded)
                islandPanel.orderFrontRegardless()
            }
            if virtualDisplayID == nil {
                islandPanel.makeKey()
            }
        }
    }

    @objc func toggleMinimizedToMenuBar() {
        monitor.setMinimizedToMenuBar(!monitor.minimizedToMenuBar)
        updateMenuCheckmarks()
    }

    @objc func toggleDoNotDisturb() {
        monitor.setHoverAutoExpand(!monitor.hoverAutoExpand)
        updateMenuCheckmarks()
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
        minimizeItem?.state = monitor.minimizedToMenuBar ? .on : .off
        dndItem?.state = !monitor.hoverAutoExpand ? .on : .off
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
        if let hk = hotKeyRef { UnregisterEventHotKey(hk) }
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }
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
