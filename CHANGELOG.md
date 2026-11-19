# Changelog / 更新日志

All notable changes to **AgentIsland** will be documented in this file.
本文档记录 **AgentIsland** 的重要版本更新与演进。

---

## [v1.6.0] - 2026-11-19

### 🚴 Meituan Delivery Live Activity & Stepper / 美团外卖实时履约与四态灵动岛重构

- **🚴 深度对标美团外卖实时履约模型（Meituan Live Activity Stepper）**
  - 彻底抛弃粗暴的“待办 vs 办结”二值模型，全面升级为美团 4 阶段状态机：`①派单 (dispatched)` ➔ `②接单 (accepted)` ➔ `③送达待验 (submitted)` ➔ `④结案核销 (confirmed)`；
  - 任务列表每笔工单原位引入【美团四段式 Stepper 履约指示灯】，履约推进到哪一步，哪一步高亮，黑箱状态彻底清零。
- **📦 交付待验高光专区（Pending Confirmation Shelf · 骑手已送达）**
  - 彻底修复将 `status: 待确认` 单据误报进已办结流的严重漏洞；
  - 当检测到任何任务处于交付待验状态时，抽屉与控制中心顶部常驻醒目的【美团待验收专区】极光紫高亮卡片；
  - 显示交付物路径，并提供 `[查看单据]` 与 `[✅ 一键结案 (confirm)]` 快捷操作，实现桌面端直接一键收货核销。
- **🔔 顶部胶囊（Compact Island）四态动态变色与呼吸**
  - **待验收高光**：存在待确认任务时，胶囊点亮极光紫（`#8B5CF6`），显示 `🔔 N 单待验收`；
  - **履约推进中**：Agent 正在接单跑代码时，胶囊点亮动感蓝（`#3B82F6`），显示 `⚡ N 单履约中`；
  - **待接单等待**：工单未接单时，胶囊点亮琥珀黄（`#F59E0B`），显示 `📦 N 单待接单`；
  - **全员妥投就绪**：全部结案且通道健康时，点亮薄荷绿（`#10B981`），显示 `3 Agents • 全员就绪 (0 积压)`。
- **🛠️ 底座健壮性补强**：
  - 修复 `scripts/handoff.py` 中 `target.resolve().relative_to(HANDOFFS_ROOT.resolve())` 相对路径崩错问题；
  - 增加 `--artifacts` 物理文件存在性校验，杜绝虚假产物挂账。

---

## [v1.5.0] - 2026-11-19

### 🕒 Done Feed & Real-Time Accountability / 已办结流与成果透明化

- **🕒 最新结案回信 · 已办结流（Done Feed & Reply Transparency）**
  - 彻底攻克“回信销账后在界面上消失蒸发、看不到最终完成情况”的认知断层；
  - 展开任意 Agent 抽屉时，在待办下方（或无待办时）新增【最新结案回信 · 已办结流 (Done Feed)】模块；
  - 实时提取呈现该 Agent 最近 3 笔已结案回信的标题、完成时间戳与发回件流向；
  - 每笔回信提供「查看回信」按钮，一键调出 Obsidian 回信原件核查，露露随时掌握最终交付成果。
- **🚀 60 秒极速跨机闭环实测通过（Sub-2-Minute Cross-Machine Roundtrip）**
  - 全网定时任务与巡检全面调至 60 秒（1分钟），实测 Alma 本地唤醒 51 秒、Ping 远端唤醒 52 秒；
  - 跨端端到端往返从过去的 15 分钟暴缩至 2 分钟以内，实测往返总耗时仅 129 秒，彻底告别时滞黑洞。

---

## [v1.4.0] - 2026-11-19

### 🎨 Theme Customization & Light Mode Parity / 状态栏调色盘与浅色模式原厂重构

- **🎨 原生状态栏主题切换与 5 色调色盘（Native Theme & Accent Palette）**
  - 在菜单栏 `🏝️ 3A` 原生菜单中深度植入【🌓 外观模式】与【🎨 主题强调色】两大级联子菜单；
  - **三态外观模式**：随时切换 `⚙️ 跟随系统` / `☀️ 浅色模式` / `🌙 深色模式`，带系统原生 `✓` 勾选标记，即点即变；
  - **5 档主题强调色（对齐 context-viewer 调色盘）**：支持切换 **🔵 经典蓝 (Apple Blue)** / **🟣 极光紫 (Context Purple)** / **🟡 琥珀黄 (Warm Amber)** / **🟢 薄荷绿 (Fresh Green)** / **🔴 珊瑚红 (Coral Red)**，全局主图标与光晕实时联动换色；
  - **本地永久记忆（UserDefaults）**：用户的外观与色彩配置自动持久化落盘，开机与重启后永久保留。
- **💎 浅色模式原生白瓷玉石质感深度重构（Light Mode Ceramic Parity）**
  - 彻底攻克浅色顶栏下胶囊“发黑发虚”问题；
  - 浅色模式采用 `92% 高透白瓷玉质底`（`#FFFFFF`）＋ `#1D1D1F` 纯黑深字 ＋ `#059669` 透亮森林绿，完美融入 macOS 浅色系统菜单栏。
- **🛑 原生撤单通知智能闭环（Cancel Notice Interception）**
  - 引入 `cancel-*.md` 撤单通知原生拦截引擎；
  - 对方发送的“任务取消不用做了”通知单，系统自动识别并直接结案，绝不再误标为待办，同时自动闭环关联的原任务单。
- **📝 机械化总账流水留痕（Automated Ledger Logging）**
  - 在 `handoff.py` 底层植入发单与回单自动记账门禁，落盘瞬间自动向 `handoffs/交流.md` 追加标准流水，彻底消灭“靠自觉写总账”的漏洞。

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
