#!/bin/bash
# gpu-power-limit.sh
#
# RX 5600 XT (Navi 10) の Power Cap をソフトウェアで切り替える。
#
# Sapphire Pulse RX 5600 XT の物理BIOSスイッチを切り替えずに
# Silent モード相当の電力制限を適用する。
# Navi 10 世代の gfx ring timeout / TDR 対策として
# GPU負荷を下げることでハングの頻度を減らす目的。
#
# Usage:
#   sudo bash gpu-power-limit.sh on      # Silent相当 (135W) に制限
#   sudo bash gpu-power-limit.sh off     # デフォルト (150W) に戻す
#   sudo bash gpu-power-limit.sh status  # 現在の状態を表示
#
# Note:
#   - 再起動するとデフォルトに戻る
#   - 永続化したい場合は systemd service 等で起動時に実行する

set -euo pipefail

POWER_CAP=$(echo /sys/class/drm/card1/device/hwmon/hwmon*/power1_cap)

SILENT_CAP=135000000   # 135W (Silent BIOS相当)
DEFAULT_CAP=150000000  # 150W (Performance BIOSデフォルト)

if [[ ! -f "$POWER_CAP" ]]; then
    echo "[ERROR] power1_cap が見つかりません"
    exit 1
fi

show_status() {
    local current
    current=$(cat "$POWER_CAP")
    local watts=$((current / 1000000))
    if [[ "$current" -le "$SILENT_CAP" ]]; then
        echo "[STATUS] Power Cap: ${watts}W (Silent相当)"
    else
        echo "[STATUS] Power Cap: ${watts}W (Performance)"
    fi
}

case "${1:-status}" in
    on)
        echo "$SILENT_CAP" > "$POWER_CAP"
        echo "[OK] Power Cap を 135W (Silent相当) に設定しました"
        ;;
    off)
        echo "$DEFAULT_CAP" > "$POWER_CAP"
        echo "[OK] Power Cap を 150W (Performance) に戻しました"
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: sudo bash $0 {on|off|status}"
        exit 1
        ;;
esac
