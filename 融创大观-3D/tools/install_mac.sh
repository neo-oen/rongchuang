#!/bin/bash
# SketchUp MCP — Mac 安装脚本（项目级）
# 用法: bash 融创大观-3D/tools/install_mac.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_SRC="$SCRIPT_DIR/BearNetwork-SketchUp-MCP"
PLUGINS="$HOME/Library/Application Support/SketchUp 2026/SketchUp/Plugins"

echo "==> 检查依赖..."
command -v uvx >/dev/null || { echo "请先安装 uv: pip install uv"; exit 1; }
[ -d "/Applications/SketchUp 2026" ] || { echo "未找到 SketchUp 2026，请确认已安装"; exit 1; }

echo "==> 安装 SketchUp 插件..."
mkdir -p "$PLUGINS"
ln -sf "$MCP_SRC/su_mcp.rb" "$PLUGINS/su_mcp.rb"
ln -sf "$MCP_SRC/su_mcp" "$PLUGINS/su_mcp"
echo "    插件已链接到: $PLUGINS"

echo "==> 验证 Python MCP 服务..."
uvx --from "$MCP_SRC" sketchup-mcp &
PID=$!
sleep 3
if kill -0 $PID 2>/dev/null; then
  kill $PID 2>/dev/null || true
  echo "    MCP 服务启动正常"
else
  echo "    警告: MCP 服务未能启动，请检查 Python/uv 环境"
fi

echo ""
echo "==> 安装完成！"
echo ""
echo "MCP 配置位于项目 .cursor/mcp.json（仅在本项目生效）"
echo ""
echo "每次使用前："
echo "  1. 打开 SketchUp 2026 并加载 .skp 模型"
echo "  2. 菜单: 扩展 > Sketchup MCP > Start Server"
echo "  3. 重启 Cursor 或 Reload Window"
echo ""
echo "检查端口: lsof -nP -iTCP:9876 -sTCP:LISTEN"
