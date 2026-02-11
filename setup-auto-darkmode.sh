#!/bin/bash
# setup-auto-darkmode.sh
#
# 日の出・日没に基づいて GNOME のダークモード/ライトモードを自動切替する
# systemd ユーザータイマーをセットアップする。
#
# Usage:
#   bash setup-auto-darkmode.sh              # インストール
#   bash setup-auto-darkmode.sh --uninstall  # アンインストール
#
# What it does:
#   1. 位置情報の設定 (IPジオロケーションで自動取得、または手動設定)
#   2. systemd ユーザーサービス/タイマーのインストール
#   3. タイマーの有効化と初回実行
#
# Requirements:
#   - python3 (標準ライブラリのみ使用)
#   - GNOME デスクトップ環境

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DARKMODE_DIR="${SCRIPT_DIR}/auto-darkmode"
CONFIG_DIR="${HOME}/.config/auto-darkmode"
CONFIG_FILE="${CONFIG_DIR}/location.conf"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# --- アンインストール ---
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "[INFO] ダークモード自動切替をアンインストール中..."

    if systemctl --user is-active auto-darkmode.timer &>/dev/null; then
        systemctl --user stop auto-darkmode.timer
        echo "[OK] auto-darkmode.timer を停止"
    fi

    if systemctl --user is-enabled auto-darkmode.timer &>/dev/null; then
        systemctl --user disable auto-darkmode.timer
        echo "[OK] auto-darkmode.timer を無効化"
    fi

    for UNIT in auto-darkmode.service auto-darkmode.timer; do
        if [ -f "${SYSTEMD_USER_DIR}/${UNIT}" ]; then
            rm "${SYSTEMD_USER_DIR}/${UNIT}"
            echo "[OK] ${UNIT} を削除"
        fi
    done

    systemctl --user daemon-reload

    echo ""
    echo "[OK] アンインストール完了"
    echo "     位置情報は残してあります: ${CONFIG_FILE}"
    echo "     完全に削除するには: rm -r ${CONFIG_DIR}"
    exit 0
fi

# --- 1. 位置情報の設定 ---
echo "[INFO] 位置情報を設定中..."

if [ -f "$CONFIG_FILE" ]; then
    echo "[SKIP] 位置情報は既に設定済み: ${CONFIG_FILE}"
    grep -E "^(latitude|longitude)" "$CONFIG_FILE" | sed 's/^/       /'
else
    mkdir -p "$CONFIG_DIR"

    # IPジオロケーションで自動取得を試みる
    AUTO_LAT=""
    AUTO_LON=""
    AUTO_CITY=""
    if command -v curl &>/dev/null; then
        echo "[INFO] IPアドレスから位置情報を自動取得中..."
        GEO_JSON=$(curl -s --max-time 5 "http://ip-api.com/json/?fields=lat,lon,city,country" 2>/dev/null || true)
        if [ -n "$GEO_JSON" ]; then
            AUTO_LAT=$(echo "$GEO_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('lat',''))" 2>/dev/null || true)
            AUTO_LON=$(echo "$GEO_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('lon',''))" 2>/dev/null || true)
            AUTO_CITY=$(echo "$GEO_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('city','')}, {d.get('country','')}\")" 2>/dev/null || true)
        fi
    fi

    if [ -n "$AUTO_LAT" ] && [ -n "$AUTO_LON" ]; then
        echo "[INFO] 検出された位置: ${AUTO_CITY} (緯度: ${AUTO_LAT}, 経度: ${AUTO_LON})"
        read -rp "       この位置を使用しますか？ [Y/n] " CONFIRM
        CONFIRM="${CONFIRM:-Y}"
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            LAT="$AUTO_LAT"
            LON="$AUTO_LON"
        fi
    fi

    if [ -z "${LAT:-}" ] || [ -z "${LON:-}" ]; then
        echo "[INFO] 緯度と経度を手動で入力してください"
        echo "       (例: 東京 = 35.6762, 139.6503)"
        read -rp "       緯度: " LAT
        read -rp "       経度: " LON
    fi

    cat > "$CONFIG_FILE" << EOF
[location]
latitude = ${LAT}
longitude = ${LON}
EOF
    echo "[OK] 位置情報を保存: ${CONFIG_FILE}"
fi

# --- 2. systemd ユーザーサービス/タイマーのインストール ---
echo ""
echo "[INFO] systemd ユーザーサービスをインストール中..."

mkdir -p "$SYSTEMD_USER_DIR"

NEEDS_RELOAD=false

for UNIT in auto-darkmode.service auto-darkmode.timer; do
    SRC="${DARKMODE_DIR}/${UNIT}"
    DST="${SYSTEMD_USER_DIR}/${UNIT}"
    if [ -f "$DST" ] && diff -q "$SRC" "$DST" &>/dev/null; then
        echo "[SKIP] ${UNIT} は最新"
    else
        cp "$SRC" "$DST"
        echo "[OK] ${UNIT} をインストール"
        NEEDS_RELOAD=true
    fi
done

if [ "$NEEDS_RELOAD" = true ]; then
    systemctl --user daemon-reload
    echo "[OK] systemd daemon-reload"
fi

# --- 3. タイマーの有効化と初回実行 ---
echo ""
echo "[INFO] タイマーを有効化中..."

if systemctl --user is-enabled auto-darkmode.timer &>/dev/null; then
    echo "[SKIP] auto-darkmode.timer は既に有効"
else
    systemctl --user enable auto-darkmode.timer
    echo "[OK] auto-darkmode.timer を有効化"
fi

if systemctl --user is-active auto-darkmode.timer &>/dev/null; then
    echo "[SKIP] auto-darkmode.timer は既に起動中"
else
    systemctl --user start auto-darkmode.timer
    echo "[OK] auto-darkmode.timer を起動"
fi

# 初回実行
echo ""
echo "[INFO] 初回実行中..."
python3 "${DARKMODE_DIR}/darkmode-switch.py"

# --- 完了 ---
echo ""
echo "[OK] ダークモード自動切替のセットアップが完了しました"
echo "     5分ごとに日の出/日没をチェックしてテーマを切り替えます"
echo ""
echo "     手動確認:  systemctl --user status auto-darkmode.timer"
echo "     手動実行:  python3 ${DARKMODE_DIR}/darkmode-switch.py"
echo "     位置変更:  ${CONFIG_FILE} を編集"
