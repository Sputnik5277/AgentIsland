# Changelog / 更新日志

All notable changes to **AgentIsland** will be documented in this file.
本文档记录 **AgentIsland** 的重要版本更新与演进。

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
