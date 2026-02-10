#!/bin/bash
# setup-gnome-tweaks.sh
#
# gnome-tweaks をインストールする。
#
# Usage:
#   bash setup-gnome-tweaks.sh
#
# What it does:
#   1. gnome-tweaks をインストール (未インストールの場合)
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

echo ""
echo "[OK] gnome-tweaks のセットアップが完了しました"
