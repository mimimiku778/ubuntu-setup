#!/bin/bash
# setup-tiling-edge-drag.sh
#
# Ubuntu Enhanced Tiling (tiling-assistant) のドラッグタイリングを
# 左右のみ有効にし、上下端のスナップを無効化する。
#
# Usage:
#   bash setup-tiling-edge-drag.sh
#
# What it does:
#   1. tiling-assistant 拡張を有効化
#   2. 上下端のドラッグ検出を無効化 (vertical-preview-area = -9999)
#   3. 上端の最大化トグルタイマーを無効化

set -euo pipefail

if ! gsettings list-schemas | grep -q org.gnome.shell.extensions.tiling-assistant; then
    echo "[ERROR] tiling-assistant 拡張が見つかりません"
    exit 1
fi

gnome-extensions enable tiling-assistant@ubuntu.com 2>/dev/null || true

# 上下端のドラッグ検出を無効化 (-9999 で判定が常に false になる)
gsettings set org.gnome.shell.extensions.tiling-assistant vertical-preview-area "-9999"

# 上端ホールド時の最大化/上半分切り替えタイマーを無効化
gsettings set org.gnome.shell.extensions.tiling-assistant toggle-maximize-tophalf-timer 0

echo "[OK] ドラッグタイリングを左右のみに設定"
