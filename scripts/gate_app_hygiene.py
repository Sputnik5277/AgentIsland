#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gate_app_hygiene.py — AgentIsland build.sh 前置静态门禁（Tier 2）。

把 2026-11-21 三轮真机事故固化为编译前硬门，杜绝同类复发：
  1. PIPE_WAIT_BEFORE_READ  — Process+Pipe 严禁先 waitUntilExit() 再 readDataToEndOfFile()（64KB 死锁）
  2. PIPE_STDERR_UNREAD     — 严禁 standardError = Pipe() 无人读取（应使用 FileHandle.nullDevice）
  3. SCALE_EFFECT_ON_PANEL  — 严禁整窗 .scaleEffect(monitor.uiScale) GPU 拉伸（2K 1x 屏文字必糊）
  4. FONT_SUB_HIG_OR_ROUNDED — 严禁 design: .rounded、字号 < 11pt 或 .minimumScaleFactor( 压缩
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
