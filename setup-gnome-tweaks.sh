#!/bin/bash
# setup-gnome-tweaks.sh
#
# gnome-tweaks をインストールし、タイトルバーのダブルクリックで
# ウィンドウの最大化/元に戻すを切り替えるように設定する。
#
# Usage:
#   bash setup-gnome-tweaks.sh
#
# What it does:
#   1. gnome-tweaks をインストール (未インストールの場合)
#   2. タイトルバーのダブルクリック動作を toggle-maximize に設定
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

# --- 2. タイトルバーのダブルクリック動作を設定 ---
CURRENT=$(gsettings get org.gnome.desktop.wm.preferences action-double-click-titlebar 2>/dev/null || echo "")

if [[ "$CURRENT" == "'toggle-maximize'" ]]; then
    echo "[SKIP] ダブルクリック動作は既に toggle-maximize に設定済み"
else
    gsettings set org.gnome.desktop.wm.preferences action-double-click-titlebar 'toggle-maximize'
    echo "[OK] タイトルバーのダブルクリック動作を toggle-maximize に設定"
fi

# --- 完了 ---
echo ""
echo "[OK] gnome-tweaks のセットアップが完了しました"
echo "     タイトルバーをダブルクリックでウィンドウの最大化/元に戻すが切り替わります"
