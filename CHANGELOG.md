# Changelog / 更新日志

All notable changes to **AgentIsland** will be documented in this file.
本文档记录 **AgentIsland** 的重要版本更新与演进。

---

## [v1.3.0] - 2026-11-19

### 🚀 Architecture Evolution / 架构升级与双核中控

- **⚡ 3 天滑动冷热归档体系（Hot-to-Cold Eviction Engine）**
  - 建立标准 `handoffs/archive/<YYYY-MM>/<box>/` 自动化退火体系；
  - 凡修改时间超过 72 小时（3 天保鲜期）且已在 `.ack/` 结案的历史老单，由系统自动原子迁移至归档冷区；
  - 彻底终结单据无限堆积痛点，确保收件箱极速保鲜，磁盘扫描 I/O 永远控制在 10ms 以内。
- **🌐 跨箱全网反向索引（Cross-Box Reply Penetration）**
  - 彻底打破单箱孤岛假设，实现全网三箱的 `reply_to` 全局反向穿透映射；
  - 远端节点（Ping）跨箱投递到发起人（AGY/Alma）收件箱的回信，中控台自动识别并对齐消单，杜绝假待办。
- **🪙 Antigravity 双核遥测底座（Deep Telemetry & Ledger Integration）**
  - 吸纳 `antigravity-context-viewer` 的两级账本机制，无锁非侵入式读取本地 `token_usage_archive_v2.json`；
  - 在控制中心 Hero Card 实时呈现 **本月 Token 消耗（3.46B 🪙）· Cache 命中率（94%）· 主力模型分布**，实现“任务待办流 ＋ AI 运行态”双核管控。
- **🔍 一键核验与归档（Verify & Archive）一体化**
  - 核心操作升级为【🔍 全网核验与归档】，跨箱关联消单与历史老单自动退火合二为一，具备真实物理闭环。

---

## [v1.2.0] - 2026-11-19

### 🛡️ Core Correction & Reconcile / 核心交互纠偏与合规核验

- **🛑 废除盲目抹平，重构为主按钮【🔍 全网核验与对齐 (Verify & Reconcile)】**
  - **绝不造假账**：彻底剔除“不论任务是否做完、点一下就强行将收件箱全量写入 acked”的恶劣伪完成逻辑。
  - **三硬门合规收口（T1 物理交付底线）**：
    1. **真完成（True Done）**：收件箱中真实存在有效 `-reply.md` 回信且物理产物真实落盘；
    2. **被高阶单据覆盖（Superseded）**：同一链路已有更高阶终结单据（如 Syncthing 结案单）；
    3. **露露亲口批复作废（Cancelled by Lulu）**：经授权标记作废。
  - **未完成事项坚决不碰**：正在进行或未回复的任务（如新派发的 `create-space-request`），堂堂正正亮黄灯挂在待办，绝不擅自抹杀。
- **📊 待办真相与诚实亮灯（Truth in Numbers）**
  - 诚实反映现实，当前中控台真实呈现 **Ping 11 待办 / AGY 2 待办**，全网共 13 笔真实流转任务，杜绝自欺欺人的虚假 0 待办。
- **🗂️ 智能体待办下钻抽屉（Task Transparency Drawer）**
  - 点击任意 Agent 药丸卡片，中控台原地展开丝滑的**真待办任务抽屉**；
  - 逐项呈现真实单据标题、发起方（`from → to`）、派单时间与文件路径；
  - 每笔任务提供「**查看单据**」一键在 Obsidian 中打开原单核查，露露掌握最高知情权与裁决权；点击「← 返回」平滑复原中控台。

---

## [v1.1.0] - 2026-11-19

### 🚀 New Features / 新增功能

- **🩺 Interactive Channel Self-Healing / 通道红灯点击自愈**
  - **Nutstore / 坚果云**：离线红灯时点击一键自动唤醒 `/Applications/Nutstore.app` 并自愈变绿；在线时点击直达同步根目录。
  - **Funnel 64M**：离线红灯时点击自动执行 `launchctl kickstart` 热启服务，并调起 `/v1/health` 网页诊断；在线时点击直接查看服务健康状态。
  - **Tailscale**：点击直接唤起 `/Applications/Tailscale.app` 面板。
- **📂 Agent Capsule Drilldown / 智能体收件箱下钻**
  - 白 / AGY、Alma、Ping 药丸卡片全部升级为交互式按钮（带 Apple 原生触感缩放动画 `PressableScaleButtonStyle`）。
  - 当智能体有待办积压（>0）时，卡片右上角显示显目橙色指示；点击任意卡片**一秒在 Finder 中打开对应收件箱目录**（`handoffs/ping`、`handoffs/agy` 等），待办单单一清二楚。
- **📝 Ledger Quick Access / 交流台账直达**
  - 中控台第二栏快捷动作新增「**交流台账**」按钮（一键打开 `handoffs/交流.md`）。
  - 顶部状态栏菜单同步加入 `📝 打开《交流.md》` 与 `🌐 检查 Funnel 健康状态` 入口。
- **⚡ 5-Inbox Full Sweep / 全网待办收口扩容**
  - `triggerSweepAll`（一键全网收口）由 3 箱扩容至全局 5 大收件箱全覆盖：`["ping", "agy", "alma", "codex", "claude-desktop"]`。

### 🐛 Bug Fixes & Polish / 体验与稳定性修复

- **🖱️ First-Mouse Single Click Fix / 修复必须双击与首击吞咽**
  - 自建 `FirstMouseHostingView: NSHostingView`，强制开启 `acceptsFirstMouse = true`。彻底攻克了 macOS 对非激活悬浮窗吞掉第一次点击的底层机制，实现**任意状态下单次单击即开**。
- **🛡️ Anti-Flicker & Debounce / 消除连击抽搐与闪退**
  - 将展开手势范围严格限定在 `.compact` 胶囊，展开后控制中心内部点击不再触发意外收缩（仅点关闭按钮或点窗口外部收起）。
  - 增加 350ms 防抖门禁，即使狂点也不会发生“展开瞬间被秒收起”的现象。
- **📐 Animation Bounds Race Fix / 消除动画期误杀**
  - 物理窗口尺寸边界瞬间到位，由 SwiftUI 原生 spring 物理引擎负责丝滑平滑过渡，彻底解决 AppKit 几何缩放过程中本地点击监视器将内部点击误判为“点在窗口外”而强制收起的时序竞态。
- **🌐 Localization & Bundle ID Fix / 修复坚果云假红灯**
  - 适配 macOS 中文环境下坚果云真实 Bundle Identifier（`net.nutstore.osxapp`）及本地化名称（`"坚果云"`），确保三通道精准全绿。

---

## [v1.0.0] - 2026-11-19

### 🎉 Initial Release / 初始版本发布

- 💎 **Apple Liquid Glass Design**：基于原生 `NSVisualEffectView` 的高拟真液态玻璃设计与实时高斯模糊背景。
- 🎛️ **1:1 Control Center Layout**：高度对齐 macOS Sequoia 控制中心栅格布局。
- ⚡ **1-Click Sweep Action**：一键全网收口与待办核销。
- 🖥️ **Active Display Tracking**：智能感知鼠标位置，多显示器焦点自动跟随。
- 🌓 **Instant Theme Adaptation**：macOS 深色/浅色外观毫秒级自动随动。
- 🛡️ **Zero Token & 100% Offline**：纯本地轮询，0 Token 消耗，内存占用约 15MB。
