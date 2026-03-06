#!/bin/bash
# setup-oled-color-profile.sh
#
# Samsung ATNA40YK20-0 / ATNA40HQ02-0 OLED パネル (100% DCI-P3) に
# X-Rite i1Pro 3 キャリブレーション済み ICC プロファイルを適用する。
#
# プロファイル元: NotebookCheck (ThinkPad X1 Carbon Gen 13 レビュー)
# VCGT (Video Card Gamma Table) 付きで gnome-settings-daemon がガンマランプに
# 適用し、全アプリの表示を sRGB 相当に補正する。
#
# Usage:
#   bash setup-oled-color-profile.sh
#
# Requirements:
#   - sudo 権限
#   - GNOME + colord (gnome-settings-daemon が VCGT を適用)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICC_NAME="ATNA40YK20_0.icm"
ICC_SRC="$SCRIPT_DIR/$ICC_NAME"
ICC_DEST="/usr/share/color/icc/colord/$ICC_NAME"
DEVICE_ID="xrandr-Samsung Display Corp.-ATNA40HQ02-0 -0x00000000"

# --- 1. システムにインストール ---
if [ ! -f "$ICC_SRC" ]; then
    echo "[ERROR] プロファイルが見つかりません: $ICC_SRC"
    exit 1
fi

echo "[INFO] ICC プロファイルをインストール中..."
sudo cp "$ICC_SRC" "$ICC_DEST"
echo "[OK] $ICC_DEST にインストール"

# colord がファイルを認識するまで少し待つ
sleep 1

# --- 2. colord でデバイスに割り当て ---
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
echo "     X-Rite i1Pro 3 キャリブレーション済み VCGT が有効になります"
