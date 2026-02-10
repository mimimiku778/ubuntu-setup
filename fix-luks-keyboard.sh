#!/bin/bash
# fix-luks-keyboard.sh
#
# LUKS解除画面（initramfs）のキーボードレイアウトをUSに設定する。
# /etc/default/keyboard の XKBLAYOUT を "us" に変更し、initramfs を再生成する。
#
# Usage:
#   sudo bash fix-luks-keyboard.sh
#
# What it does:
#   1. /etc/default/keyboard の XKBLAYOUT を "us" に変更
#   2. initramfs を再生成して反映
#
# Note:
#   この変更はコンソール (tty) と initramfs に影響する。
#   GNOME デスクトップの入力ソース設定には影響しない。
#
# Requirements:
#   - root 権限 (sudo)

set -euo pipefail

# --- root チェック ---
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] root 権限が必要です。sudo bash $0 で実行してください。" >&2
    exit 1
fi

KEYBOARD_CONF="/etc/default/keyboard"

# --- 1. /etc/default/keyboard の XKBLAYOUT を "us" に変更 ---
if ! [[ -f "$KEYBOARD_CONF" ]]; then
    echo "[ERROR] $KEYBOARD_CONF が見つかりません" >&2
    exit 1
fi

CURRENT_LAYOUT=$(grep '^XKBLAYOUT=' "$KEYBOARD_CONF" | sed 's/XKBLAYOUT="\?\([^"]*\)"\?/\1/')

if [[ "$CURRENT_LAYOUT" == "us" ]]; then
    echo "[SKIP] XKBLAYOUT は既に \"us\" に設定済み"
else
    sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="us"/' "$KEYBOARD_CONF"
    echo "[OK] XKBLAYOUT を \"$CURRENT_LAYOUT\" → \"us\" に変更"
fi

# --- 2. initramfs を再生成 ---
echo "[INFO] initramfs を再生成中..."
update-initramfs -u
echo "[OK] initramfs を再生成完了"

# --- 完了 ---
echo ""
echo "[OK] 次回起動時から LUKS 解除画面で US キーボード配列が使用されます"
