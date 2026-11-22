#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gate_app_hygiene.py — AgentIsland build.sh 前置静态门禁（Tier 2）。

把 2026-11-21 三轮真机事故固化为编译前硬门，杜绝同类复发：
  1. PIPE_WAIT_BEFORE_READ  — Process+Pipe 严禁先 waitUntilExit() 再 readDataToEndOfFile()（64KB 死锁）
  2. PIPE_STDERR_UNREAD     — 严禁 standardError = Pipe() 无人读取（应使用 FileHandle.nullDevice）
  3. SCALE_EFFECT_ON_PANEL  — 严禁整窗 .scaleEffect(monitor.uiScale) GPU 拉伸（2K 1x 屏文字必糊）
  4. FONT_SUB_HIG_OR_ROUNDED — 严禁 design: .rounded、字号 < 11pt 或 .minimumScaleFactor( 压缩
  5. V4_DELTA_SNAPSHOT_CONTRACT — 消费 M4/M5/M6 快照及 isStale 陈旧守卫
  6. V4_BATCH_C2_CONTRACT    — M1/M2/M3 决策卡、打回、已读与剪贴板支持
  7. V4_BATCH_C3_CONTRACT    — ⌥I 全局热键、底部快发、M7 决定档案及可自定义快捷资产
  8. V4_MEITUAN_CLOSED_LOOP_CONTRACT — 美团全链阶段识别（Step 2 / 需前台接力）及抽屉顶栏防裁切
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_APP_SWIFT = Path(__file__).resolve().parent.parent / "Sources" / "AgentIsland" / "App.swift"


def strip_line_comment(line: str) -> str:
    idx = line.find("//")
    if idx == -1:
        return line
    # Preserve URLs inside string literals (e.g. "http://...")
    prefix = line[:idx]
    if prefix.count('"') % 2 == 1:
        return line
    return prefix


def check_app_swift(path: Path) -> dict:
    if not path.is_file():
        return {
            "verdict": "FAIL",
            "file": str(path),
            "error": f"file not found: {path}",
            "findings": [],
            "counts": {},
        }

    raw_lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    code_lines = [strip_line_comment(ln) for ln in raw_lines]

    findings: list[dict] = []
    counts = {
        "PIPE_WAIT_BEFORE_READ": 0,
        "PIPE_STDERR_UNREAD": 0,
        "SCALE_EFFECT_ON_PANEL": 0,
        "FONT_SUB_HIG_OR_ROUNDED": 0,
        "V4_DELTA_SNAPSHOT_CONTRACT": 0,
        "V4_BATCH_C2_CONTRACT": 0,
        "V4_BATCH_C3_CONTRACT": 0,
        "V4_MEITUAN_CLOSED_LOOP_CONTRACT": 0,
        "NOTIFICATION_INTERACTION_CONTRACT": 0,
        "COMPACT_WIDTH_CAP": 0,
    }

    def add_finding(rule: str, line_no: int, snippet: str) -> None:
        counts[rule] += 1
        findings.append({"rule": rule, "line": line_no, "snippet": snippet.strip()[:120]})

    # Rule 1: PIPE_WAIT_BEFORE_READ
    for i, code in enumerate(code_lines):
        if "standardOutput" in code and "pipe" in code.lower():
            wait_line = None
            read_line = None
            for j in range(i + 1, min(len(code_lines), i + 25)):
                c = code_lines[j]
                if re.search(r"\bProcess\s*\(\s*\)", c) or re.search(r"\bfunc\s+\w+", c):
                    break
                if wait_line is None and ".waitUntilExit()" in c:
                    wait_line = j + 1
                if read_line is None and ".readDataToEndOfFile()" in c:
                    read_line = j + 1
                if wait_line is not None and read_line is not None:
                    break
            if wait_line is not None and read_line is not None and wait_line < read_line:
                add_finding(
                    "PIPE_WAIT_BEFORE_READ",
                    wait_line,
                    f"waitUntilExit()@L{wait_line} precedes readDataToEndOfFile()@L{read_line}",
                )

    # Rules 2, 3, 4: per-line checks
    re_stderr_pipe = re.compile(r"\bstandardError\s*=\s*Pipe\s*\(\s*\)")
    re_scale_panel = re.compile(r"\.scaleEffect\(\s*monitor\.uiScale\b")
    re_rounded = re.compile(r"\bdesign:\s*\.rounded\b")
    re_sub_11 = re.compile(r"\.font\(\s*\.system\(\s*size:\s*(?:[1-9](?:\.\d+)?|10(?:\.\d+)?)\b")
    re_min_scale = re.compile(r"\.minimumScaleFactor\(")

    for idx, code in enumerate(code_lines, 1):
        if not code.strip():
            continue
        if re_stderr_pipe.search(code):
            add_finding("PIPE_STDERR_UNREAD", idx, raw_lines[idx - 1])
        if re_scale_panel.search(code):
            add_finding("SCALE_EFFECT_ON_PANEL", idx, raw_lines[idx - 1])
        if re_rounded.search(code) or re_sub_11.search(code) or re_min_scale.search(code):
            add_finding("FONT_SUB_HIG_OR_ROUNDED", idx, raw_lines[idx - 1])

    # Rule 5: V4_DELTA_SNAPSHOT_CONTRACT (M4/M5/M6 snapshot consumption + freshness guard)
    joined_code = "\n".join(code_lines)
    required_anchors = [
        ('"pingloop-health.json"', "missing pingloop-health.json M6 snapshot reader"),
        ('"pingloop-convergence.jsonl"', "missing pingloop-convergence.jsonl M6 reader"),
        ('"alma-turn.json"', "missing alma-turn.json M5 dual-backend reader"),
        ("isStale", "missing M4 snapshot freshness guard (isStale)"),
    ]
    for token, desc in required_anchors:
        if token not in joined_code:
            add_finding("V4_DELTA_SNAPSHOT_CONTRACT", 1, desc)

    # Rule 6: V4_BATCH_C2_CONTRACT (M1/M2/M3 decision card, reject, ack, clipboard)
    c2_anchors = [
        ("func rejectTask(", "missing C2 rejectTask action"),
        ("NSPasteboard", "missing C2 NSPasteboard copy support"),
        ("func markTaskRead(", "missing C2 markTaskRead .ack action"),
        ('"a-verifier-decisions"', "missing C2 a-verifier-decisions reader"),
    ]
    for token, desc in c2_anchors:
        if token not in joined_code:
            add_finding("V4_BATCH_C2_CONTRACT", 1, desc)

    # Rule 7: V4_BATCH_C3_CONTRACT (⌥I hotkey, quick send, M7 decisions-archive, custom assets)
    c3_anchors = [
        ("RegisterEventHotKey", "missing C3 global hotkey RegisterEventHotKey"),
        ("func quickSendMessage(", "missing C3 quickSendMessage Funnel action"),
        ('decisions-archive.md"', "missing C3 M7 decisions-archive.md default quick asset"),
        ('"agent_island_quick_assets"', "missing C3 customizable quick assets UserDefaults key"),
    ]
    for token, desc in c3_anchors:
        if token not in joined_code:
            add_finding("V4_BATCH_C3_CONTRACT", 1, desc)

    # Rule 8: V4_MEITUAN_CLOSED_LOOP_CONTRACT (real Step2/relay stage + drawer clip guard)
    r8_anchors = [
        ("需前台接力", "missing Step2.5 foreground relay stage support"),
        ("【Step 2", "missing inline/hand-written Step 2 stage detection in fetchInboxesJSON"),
        (".layoutPriority(1)", "missing drawer ScrollView layoutPriority(1) clip guard"),
    ]
    for token, desc in r8_anchors:
        if token not in joined_code:
            add_finding("V4_MEITUAN_CLOSED_LOOP_CONTRACT", 1, desc)
    pending_line = next((i + 1 for i, c in enumerate(code_lines) if "cur_status" in c and "待确认" in c), None)
    accepted_line = next((i + 1 for i, c in enumerate(code_lines) if "or has_inline_step2" in c), None)
    if pending_line is None or accepted_line is None or pending_line > accepted_line:
        add_finding(
            "V4_MEITUAN_CLOSED_LOOP_CONTRACT",
            pending_line or 1,
            f"stage inversion: 待确认 check@{pending_line} must precede has_inline_step2 check@{accepted_line}",
        )

    # Rule 9: NOTIFICATION_INTERACTION_CONTRACT (click + hover during .notification)
    notif_m = re.search(r"func\s+notificationView\b[\s\S]{0,1600}?\n\s{4}\}", joined_code)
    if not notif_m or ".onTapGesture" not in notif_m.group(0):
        add_finding("NOTIFICATION_INTERACTION_CONTRACT", 1, "notificationView missing .onTapGesture expand action")
    hover_m = re.search(r"func\s+evaluateHover\b[\s\S]{0,2000}?switch\s+monitor\.currentMode", joined_code)
    if not hover_m or "case .compact, .notification:" not in joined_code:
        add_finding("NOTIFICATION_INTERACTION_CONTRACT", 1, "evaluateHover missing case .compact, .notification:")

    # Rule 10: COMPACT_WIDTH_CAP (prevent runaway compact pill width > 400pt)
    cw_m = re.search(r"var\s+preferredCompactWidth\s*:\s*CGFloat\s*\{([\s\S]{0,400}?)\}", joined_code)
    if not cw_m:
        add_finding("COMPACT_WIDTH_CAP", 1, "missing preferredCompactWidth")
    else:
        cap_m = re.search(r"\bmin\(\s*(\d+(?:\.\d+)?)\s*\*\s*s\b", cw_m.group(1))
        if not cap_m or float(cap_m.group(1)) > 400:
            add_finding("COMPACT_WIDTH_CAP", 1, f"preferredCompactWidth cap > 400pt: {cap_m.group(0) if cap_m else 'missing'}")

    verdict = "PASS" if not findings else "FAIL"
    return {
        "verdict": verdict,
        "file": str(path),
        "total_findings": len(findings),
        "counts": counts,
        "findings": findings[:25],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="AgentIsland App.swift 静态门禁")
    ap.add_argument("--file", default=str(DEFAULT_APP_SWIFT))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    res = check_app_swift(Path(args.file))
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(
            f"GATE_APP_HYGIENE={res['verdict']} "
            f"findings={res.get('total_findings', 0)} counts={res['counts']}"
        )
        for item in res.get("findings", [])[:12]:
            print(f"  - [{item['rule']}] L{item['line']}: {item['snippet']}")
    return 0 if res["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
