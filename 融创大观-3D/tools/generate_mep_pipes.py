#!/usr/bin/env python3
"""读取 mep_topology.json，调用 SketchUp MCP 生成 MEP 管线。"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOPO = ROOT / "模型/全屋/方案推敲/mep_topology.json"
RUBY = Path(__file__).resolve().parent / "rebuild_mep_pipes_only.rb"
FH_RUBY = Path(__file__).resolve().parent / "rebuild_floor_heating_only.rb"
CLEAR = Path(__file__).resolve().parent / "clear_mep_pipes.rb"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sketchup_exec import send_ruby  # noqa: E402


def load_topo() -> dict:
    return json.loads(TOPO.read_text(encoding="utf-8"))


def run_rebuild() -> dict:
    code = RUBY.read_text(encoding="utf-8")
    resp = send_ruby(code, timeout=120)
    if "error" in resp:
        raise RuntimeError(resp["error"])
    text = resp["result"]["content"][0]["text"]
    return json.loads(text)


def run_clear() -> dict:
    code = CLEAR.read_text(encoding="utf-8")
    resp = send_ruby(code, timeout=60)
    if "error" in resp:
        raise RuntimeError(resp["error"])
    return json.loads(resp["result"]["content"][0]["text"])


def run_floor_heating(loop_filter: str | None = None) -> dict:
    code = FH_RUBY.read_text(encoding="utf-8")
    if loop_filter:
        code = f"FH_FILTER = {json.dumps(loop_filter, ensure_ascii=False)}\n" + code
    resp = send_ruby(code, timeout=120)
    if "error" in resp:
        raise RuntimeError(resp["error"])
    return json.loads(resp["result"]["content"][0]["text"])


def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "rebuild"
    if action == "clear":
        result = run_clear()
    elif action == "topo":
        print(json.dumps(load_topo(), ensure_ascii=False, indent=2))
        return
    elif action == "floor":
        loop_filter = sys.argv[2] if len(sys.argv) > 2 else None
        result = run_floor_heating(loop_filter=loop_filter)
        send_ruby("Sketchup.active_model.save", timeout=30)
    else:
        topo = load_topo()
        print(f"topology: {topo['version']}")
        print(f"  floor loops: {len(topo['floor_loops'])}")
        print(f"  ac loops: {len(topo['ac_loops'])}")
        print(f"  room drops: {len(topo['room_drops'])}")
        result = run_rebuild()
        send_ruby("Sketchup.active_model.save", timeout=30)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
