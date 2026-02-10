#!/bin/bash
# setup-gnome-desktop.sh
#
# gnome-tweaks をインストールし、GNOME デスクトップの各種設定を行う。
#
# Usage:
#   bash setup-gnome-desktop.sh
#
# What it does:
#   1. gnome-tweaks をインストール (未インストールの場合)
#   2. キーボードのリピート速度と長押し判定時間を設定
#
# Requirements:
#   - sudo 権限 (パッケージインストール時)

set -euo pipefail

# --- 1. gnome-tweaks のインストール ---
if dpkg -s gnome-tweaks &>/dev/null; then
    echo "[SKIP] gnome-tweaks は既にインストール済み"
else
    echo "[INFO] gnome-tweaks をインストール中..."
    sudo apt-get update -qq
    sudo apt-get install -y gnome-tweaks
    echo "[OK] gnome-tweaks をインストール"
fi

# --- 2. キーボードのリピート速度と長押し判定時間を設定 ---
REPEAT_INTERVAL=16   # リピート間隔 (ms) — 小さいほど速い
DELAY=232             # 長押し判定時間 (ms) — キーを押してからリピートが始まるまでの時間

current_interval=$(gsettings get org.gnome.desktop.peripherals.keyboard repeat-interval)
current_delay=$(gsettings get org.gnome.desktop.peripherals.keyboard delay)

if [[ "$current_interval" == "uint32 $REPEAT_INTERVAL" && "$current_delay" == "uint32 $DELAY" ]]; then
    echo "[SKIP] キーボードのリピート設定は既に適用済み (repeat-interval=${REPEAT_INTERVAL}ms, delay=${DELAY}ms)"
else
    gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval "$REPEAT_INTERVAL"
    gsettings set org.gnome.desktop.peripherals.keyboard delay "$DELAY"
    echo "[OK] キーボードのリピート設定を適用 (repeat-interval=${REPEAT_INTERVAL}ms, delay=${DELAY}ms)"
fi

echo ""
echo "[OK] GNOME デスクトップのセットアップが完了しました"
