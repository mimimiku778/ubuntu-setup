#!/bin/bash
# setup-power-saving.sh
#
# X1 Carbon Gen 13 (Core Ultra / Arrow Lake-U) 向け省電力設定。
# power-profiles-daemon が処理しないカーネルチューニングを追加で適用する。
#
# Usage:
#   sudo bash setup-power-saving.sh [enable|disable|status]
#
#   enable   省電力設定を適用する（デフォルト）
#   disable  設定を削除してカーネルデフォルトに戻す
#   status   現在の設定を表示する
#
# 適用される設定:
#   - NMI watchdog 無効化 (深い C-state 遷移を阻害する割り込みを停止)
#   - snd_hda_intel power_save を明示的に 1 秒に設定
#
# 前提:
#   - power-profiles-daemon が active であること (TLP と併用不可)
#   - intel_pstate ドライバが使用されていること

set -euo pipefail

SYSCTL_CONF="/etc/sysctl.d/90-x1-power.conf"
MODPROBE_CONF="/etc/modprobe.d/x1-power-audio.conf"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── 使い方 ──────────────────────────────────────────────
usage() {
    echo "Usage: sudo bash $0 [enable|disable|status]"
    echo ""
    echo "  enable   省電力設定を適用する（デフォルト）"
    echo "  disable  設定を削除してカーネルデフォルトに戻す"
    echo "  status   現在の設定を表示する"
    exit 1
}

# ─── 環境チェック ─────────────────────────────────────────
check_env() {
    if ! systemctl is-active --quiet power-profiles-daemon 2>/dev/null; then
        warn "power-profiles-daemon が動いていません"
    fi
    local driver
    driver=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown")
    if [[ "$driver" != "intel_pstate" ]]; then
        warn "CPU ドライバが intel_pstate ではありません: $driver"
    fi
}

# ─── 値の表示ヘルパー ────────────────────────────────────
show_value() {
    local label="$1" current="$2" optimal="$3" default="$4"
    if [[ "$current" == "$optimal" ]]; then
        ok "$label = $current (最適)"
    elif [[ "$current" == "$default" ]]; then
        warn "$label = $current (デフォルト → $optimal 推奨)"
    else
        info "$label = $current"
    fi
}

# ─── 現在の状態を表示 ────────────────────────────────────
show_status() {
    check_env
    echo ""

    info "=== カーネルチューニング ==="
    local nmi audio

    nmi=$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null || echo "?")
    show_value "kernel.nmi_watchdog" "$nmi" "0" "1"

    audio=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null || echo "?")
    show_value "snd_hda_intel.power_save" "$audio" "1" "0"

    echo ""
    info "=== 設定ファイル ==="
    if [[ -f "$SYSCTL_CONF" ]]; then
        ok "$SYSCTL_CONF (存在)"
    else
        warn "$SYSCTL_CONF (なし)"
    fi
    if [[ -f "$MODPROBE_CONF" ]]; then
        ok "$MODPROBE_CONF (存在)"
    else
        warn "$MODPROBE_CONF (なし)"
    fi

    echo ""
    info "=== 電力モニタリング ==="
    local governor epp profile
    governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?")
    epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "?")
    profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "?")
    info "CPU governor: $governor"
    info "Energy perf preference: $epp"
    info "Platform profile: $profile"

    if command -v upower &>/dev/null; then
        local rate
        rate=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null \
            | grep "energy-rate" | awk '{print $2, $3}')
        if [[ -n "$rate" ]]; then
            info "現在の消費電力: $rate"
        fi
    fi

    echo ""
    info "=== ツール ==="
    if command -v powertop &>/dev/null; then
        ok "powertop: インストール済み"
    else
        warn "powertop: 未インストール (sudo apt install powertop)"
    fi
    if command -v turbostat &>/dev/null; then
        ok "turbostat: インストール済み"
    else
        warn "turbostat: 未インストール (sudo apt install linux-tools-\$(uname -r))"
    fi
}

# ─── 有効化 ──────────────────────────────────────────────
do_enable() {
    check_env

    info "省電力設定を適用中..."
    echo ""

    # ── sysctl 設定 ──
    info "sysctl 設定を書き込み: $SYSCTL_CONF"
    cat > "$SYSCTL_CONF" <<'SYSCTL'
# X1 Carbon Gen 13 省電力チューニング
# setup-power-saving.sh で生成

# NMI watchdog 無効化
# - 定期的な NMI 割り込みを停止し、CPU が深い C-state に遷移できるようにする
# - デバッグ用の機能でありノート PC では不要
kernel.nmi_watchdog = 0
SYSCTL
    ok "sysctl 設定を作成"

    # ── 即時適用 ──
    sysctl -p "$SYSCTL_CONF" > /dev/null
    ok "sysctl 設定を即時反映"

    # ── Audio power save ──
    info "Audio power save 設定を書き込み: $MODPROBE_CONF"
    cat > "$MODPROBE_CONF" <<'MODPROBE'
# X1 Carbon Gen 13 オーディオ省電力設定
# setup-power-saving.sh で生成

# HDA Intel オーディオの自動パワーオフ (1秒無音後にサスペンド)
options snd_hda_intel power_save=1 power_save_controller=Y
MODPROBE
    ok "Audio power save 設定を作成 (次回起動から有効)"

    # ── Audio power save 即時適用 ──
    if [[ -w /sys/module/snd_hda_intel/parameters/power_save ]]; then
        echo 1 > /sys/module/snd_hda_intel/parameters/power_save
        ok "Audio power save を即時反映"
    fi

    # ── 診断ツール ──
    echo ""
    if ! command -v powertop &>/dev/null; then
        info "powertop をインストール中..."
        apt-get install -y -qq powertop > /dev/null 2>&1 && ok "powertop インストール完了" \
            || warn "powertop インストール失敗 (手動で: sudo apt install powertop)"
    fi

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "省電力設定を適用しました"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "設定は即時反映済みです (再起動不要)"
    info "元に戻す場合: sudo bash $0 disable"
}

# ─── 無効化 ──────────────────────────────────────────────
do_disable() {
    info "省電力設定をデフォルトに戻します..."
    echo ""

    # ── sysctl 設定削除 ──
    if [[ -f "$SYSCTL_CONF" ]]; then
        rm "$SYSCTL_CONF"
        ok "$SYSCTL_CONF を削除"
    else
        info "$SYSCTL_CONF は存在しません (スキップ)"
    fi

    # ── カーネルデフォルトに即時復元 ──
    echo 1 > /proc/sys/kernel/nmi_watchdog
    ok "kernel.nmi_watchdog = 1 (デフォルト)"

    # ── Audio 設定削除 ──
    if [[ -f "$MODPROBE_CONF" ]]; then
        rm "$MODPROBE_CONF"
        ok "$MODPROBE_CONF を削除 (次回起動からデフォルトに戻る)"
    else
        info "$MODPROBE_CONF は存在しません (スキップ)"
    fi

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "カーネルデフォルトに戻しました"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "sysctl 設定は即時反映済みです"
    info "Audio 設定は次回起動で反映されます"
}

# ─── メイン ──────────────────────────────────────────────
ACTION="${1:-enable}"

if [[ "$ACTION" == "status" ]]; then
    show_status
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 $ACTION で実行してください。"
fi

case "$ACTION" in
    enable)  do_enable ;;
    disable) do_disable ;;
    *)       usage ;;
esac
