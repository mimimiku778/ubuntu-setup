#!/bin/bash
# setup-amdgpu-stability.sh
#
# RX 5600 XT (Navi 10 / RDNA1) の安定性向上のためのカーネルパラメータを設定する。
#
# RDNA1 世代は amdgpu ドライバの電力管理（クロック遷移）周りで
# "amdgpu: ring gfx_0.0.0 timeout" が発生しやすい既知の問題がある。
# ppfeaturemask=0xffffffff で電力管理の全機能を有効にし、遷移を安定させる。
#
# Usage:
#   bash setup-amdgpu-stability.sh
#
# What it does:
#   1. GRUB に amdgpu.ppfeaturemask=0xffffffff を追加
#   2. update-grub を実行
#
# Requirements:
#   - sudo 権限
#
# Note:
#   再起動後に有効になる。

set -euo pipefail

GRUB_FILE="/etc/default/grub"
PARAM="amdgpu.ppfeaturemask=0xffffffff"

# --- 現在の設定を確認 ---
CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE")

if echo "$CURRENT" | grep -q "$PARAM"; then
    echo "[SKIP] $PARAM は既に設定済み"
    exit 0
fi

# --- パラメータを追加 ---
echo "[INFO] $PARAM を GRUB に追加中..."
sudo sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)/\1 $PARAM/" "$GRUB_FILE"

# --- 確認 ---
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"

# --- GRUB 更新 ---
echo "[INFO] update-grub を実行中..."
sudo update-grub

echo ""
echo "[OK] $PARAM を設定しました。再起動後に有効になります。"
