#!/bin/bash
# setup-oled-color-profile.sh
#
# Samsung ATNA40HQ02-0 OLED パネル (100% DCI-P3) に sRGB クランプ用
# ICC カラープロファイルをインストールし、colord で適用する。
#
# VCGT (Video Card Gamma Table) 付きプロファイルを gnome-settings-daemon が
# 読み取り、ディスプレイのガンマランプに適用することで、DCI-P3 の広色域を
# sRGB 相当に補正する。
#
# Usage:
#   bash setup-oled-color-profile.sh
#
# Requirements:
#   - sudo 権限
#   - python3
#   - GNOME + colord (gnome-settings-daemon が VCGT を適用)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICC_NAME="samsung-oled-srgb-clamped.icc"
ICC_SRC="$SCRIPT_DIR/$ICC_NAME"
ICC_DEST="/usr/share/color/icc/colord/$ICC_NAME"
DEVICE_ID="xrandr-Samsung Display Corp.-ATNA40HQ02-0 -0x00000000"

# --- 1. ICC プロファイルを生成 ---
echo "[INFO] ICC プロファイルを生成中..."
python3 "$SCRIPT_DIR/generate-oled-srgb-profile.py" "$ICC_SRC"

# --- 2. システムにインストール ---
echo ""
echo "[INFO] ICC プロファイルをインストール中..."
sudo cp "$ICC_SRC" "$ICC_DEST"
echo "[OK] $ICC_DEST にインストール"

# 生成した一時ファイルを削除
rm -f "$ICC_SRC"

# colord がファイルを認識するまで少し待つ
sleep 1

# --- 3. colord でデバイスに割り当て ---
echo ""
echo "[INFO] colord でプロファイルを適用中..."

PROFILE_PATH=$(LANG=C colormgr find-profile-by-filename "$ICC_DEST" 2>/dev/null | grep "Object Path:" | awk '{print $NF}') || true
if [ -z "$PROFILE_PATH" ]; then
    echo "[ERROR] colord でプロファイルが見つかりません"
    echo "        GNOME 設定 → カラー から手動でインポートしてください: $ICC_DEST"
    exit 1
fi

DEVICE_PATH=$(LANG=C colormgr find-device "$DEVICE_ID" 2>/dev/null | grep "Object Path:" | awk '{print $NF}') || true
if [ -z "$DEVICE_PATH" ]; then
    echo "[WARN] colord でディスプレイデバイスが見つかりません (外部モニター接続時等)"
    echo "       GNOME 設定 → カラー から手動で適用してください"
    exit 0
fi

colormgr device-add-profile "$DEVICE_PATH" "$PROFILE_PATH" 2>/dev/null || true
colormgr device-make-profile-default "$DEVICE_PATH" "$PROFILE_PATH" 2>/dev/null

echo "[OK] プロファイルを適用: $(LANG=C colormgr device-get-default-profile "$DEVICE_PATH" 2>/dev/null | grep "Title:" | sed 's/.*Title: *//')"

# --- 完了 ---
echo ""
echo "[OK] OLED カラープロファイルのセットアップが完了しました"
echo "     DCI-P3 → sRGB のガンマ補正が有効になります"
