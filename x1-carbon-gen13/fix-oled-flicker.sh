#!/bin/bash
# fix-oled-flicker.sh
#
# X1 Carbon Gen 13 OLED のちらつきを修正する。
#
# debugfs 経由で PSR を無効化する。カーネルパラメータ (i915.enable_psr=0) を
# 使う従来の方法は GPU の runtime PM を完全に無効化してしまい、s2idle 時の
# バッテリー消費が大幅に増加する (2%/h 程度)。debugfs 経由なら runtime PM を
# 維持したまま PSR だけ無効化できる。
#
# Usage:
#   sudo bash fix-oled-flicker.sh [disable|enable|status]
#
#   disable  PSR を無効化してちらつきを抑える（デフォルト）
#   enable   PSR を有効化して省電力に戻す
#   status   現在の設定を表示する
#
# 仕組み:
#   - systemd サービスで起動時に debugfs の i915_edp_psr_debug を設定
#   - GRUB のカーネルパラメータには触れない (runtime PM を壊さない)

set -euo pipefail

GRUB_DEFAULT="/etc/default/grub"
SERVICE_NAME="x1-psr-disable"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ─── ドライバ自動検出 ─────────────────────────────────────
detect_driver() {
    local driver
    driver=$(lspci -k -s 00:02.0 2>/dev/null | grep "Kernel driver in use:" | awk '{print $NF}')
    if [[ "$driver" == "xe" || "$driver" == "i915" ]]; then
        echo "$driver"
    elif [[ -d /sys/module/xe ]] && [[ ! -d /sys/module/i915 ]]; then
        echo "xe"
    else
        echo "i915"
    fi
}

GPU_DRIVER=$(detect_driver)

# PSR debugfs パスを検出
find_psr_debug() {
    for d in /sys/kernel/debug/dri/*/; do
        if [[ -f "${d}i915_edp_psr_debug" ]]; then
            echo "${d}i915_edp_psr_debug"
            return
        fi
    done
    echo ""
}

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── 使い方 ──────────────────────────────────────────────
usage() {
    echo "Usage: sudo bash $0 [disable|enable|status]"
    echo ""
    echo "  disable  PSR を無効化してちらつきを抑える（デフォルト）"
    echo "  enable   PSR を有効化して省電力に戻す"
    echo "  status   現在の設定を表示"
    exit 1
}

# ─── GRUB から旧 PSR パラメータを削除 ────────────────────
cleanup_grub_params() {
    local cmdline
    cmdline=$(grep -oP 'GRUB_CMDLINE_LINUX_DEFAULT="\K[^"]*' "$GRUB_DEFAULT")
    local new_cmdline="$cmdline"
    local params=("i915.enable_psr" "i915.enable_psr2_sel_fetch" "xe.enable_psr" "xe.enable_psr2_sel_fetch")
    local changed=false
    for param in "${params[@]}"; do
        if echo "$new_cmdline" | grep -q "${param}="; then
            new_cmdline=$(echo "$new_cmdline" | sed "s/ *${param}=[^ ]*//g")
            changed=true
        fi
    done
    if [[ "$changed" == "true" ]]; then
        new_cmdline=$(echo "$new_cmdline" | sed 's/  */ /g; s/^ //; s/ $//')
        sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmdline}\"|" "$GRUB_DEFAULT"
        update-grub 2>/dev/null
        ok "GRUB から旧 PSR パラメータを削除 (再起動後反映)"
    fi
}

# ─── 現在の状態を表示 ────────────────────────────────────
show_status() {
    info "検出されたドライバ: ${GPU_DRIVER}"
    echo ""

    # debugfs PSR 状態
    info "=== PSR 状態 (debugfs) ==="
    local psr_debug
    psr_debug=$(find_psr_debug)
    if [[ -n "$psr_debug" ]]; then
        local psr_status_file="${psr_debug%_debug}_status"
        if [[ -f "$psr_status_file" ]]; then
            local mode
            mode=$(grep "^PSR mode:" "$psr_status_file" 2>/dev/null | awk -F: '{print $2}' | xargs)
            if [[ "$mode" == "disabled" ]]; then
                ok "PSR mode: disabled (ちらつき対策 ON)"
            else
                warn "PSR mode: $mode (ちらつきが出る可能性あり)"
            fi
        fi
        local debug_val
        debug_val=$(cat "$psr_debug" 2>/dev/null)
        info "i915_edp_psr_debug: $debug_val"
    else
        warn "PSR debugfs が見つかりません"
    fi

    # systemd サービス
    echo ""
    info "=== systemd サービス ==="
    if [[ -f "$SERVICE_FILE" ]]; then
        ok "$SERVICE_FILE (存在)"
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            ok "${SERVICE_NAME}: enabled"
        else
            warn "${SERVICE_NAME}: disabled"
        fi
    else
        warn "$SERVICE_FILE (なし)"
    fi

    # GPU runtime PM
    echo ""
    info "=== GPU runtime PM ==="
    local gpu_rt
    gpu_rt=$(cat /sys/class/drm/card1/device/power/runtime_status 2>/dev/null || echo "?")
    if [[ "$gpu_rt" == "suspended" || "$gpu_rt" == "active" ]]; then
        ok "GPU runtime_status: $gpu_rt"
    elif [[ "$gpu_rt" == "unsupported" ]]; then
        warn "GPU runtime_status: unsupported (s2idle 消費が増大)"
        warn "  GRUB に i915.enable_psr=0 が残っている可能性があります"
    else
        info "GPU runtime_status: $gpu_rt"
    fi

    # GRUB に旧パラメータが残っていないか確認
    echo ""
    info "=== GRUB カーネルパラメータ ==="
    local boot_cmdline
    boot_cmdline=$(cat /proc/cmdline)
    if echo "$boot_cmdline" | grep -qE "(i915|xe)\.enable_psr="; then
        warn "カーネルパラメータに PSR 設定が残っています (runtime PM に悪影響)"
        warn "  $(echo "$boot_cmdline" | grep -oE "(i915|xe)\.[^ ]*psr[^ ]*")"
    else
        ok "カーネルパラメータに PSR 設定なし (正常)"
    fi
}

# ─── 有効化 (PSR ON = 省電力) ────────────────────────────
do_enable() {
    info "PSR を有効化中..."
    echo ""

    # systemd サービス削除
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
        rm "$SERVICE_FILE"
        systemctl daemon-reload
        ok "systemd サービスを削除"
    else
        info "systemd サービスは存在しません (スキップ)"
    fi

    # GRUB の旧パラメータも掃除
    cleanup_grub_params

    # debugfs で即時有効化 (値 -1 で元に戻す)
    local psr_debug
    psr_debug=$(find_psr_debug)
    if [[ -n "$psr_debug" ]]; then
        echo 0xffffffff > "$psr_debug" 2>/dev/null
        ok "PSR を即時有効化 (debugfs)"
    fi

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "PSR 有効化完了 (省電力モード)"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─── 無効化 (PSR OFF = ちらつき対策) ─────────────────────
do_disable() {
    info "PSR を無効化中 (debugfs 方式)..."
    echo ""

    # GRUB の旧パラメータを削除 (runtime PM を壊さないため)
    cleanup_grub_params

    # systemd サービス作成
    info "systemd サービスを作成: $SERVICE_FILE"
    cat > "$SERVICE_FILE" <<'SERVICE'
[Unit]
Description=Disable i915 PSR via debugfs (OLED flicker fix)
After=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for f in /sys/kernel/debug/dri/*/i915_edp_psr_debug; do [ -f "$f" ] && echo 0x1 > "$f"; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    ok "systemd サービスを有効化 (起動時に PSR を無効化)"

    # debugfs で即時無効化
    local psr_debug
    psr_debug=$(find_psr_debug)
    if [[ -n "$psr_debug" ]]; then
        echo 0x1 > "$psr_debug" 2>/dev/null
        ok "PSR を即時無効化 (debugfs)"
    fi

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "PSR 無効化完了 (ちらつき対策 ON)"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "GPU runtime PM は維持されます (s2idle 消費に影響なし)"
    info "元に戻す場合: sudo bash $0 enable"
}

# ─── メイン ──────────────────────────────────────────────
ACTION="${1:-disable}"

if [[ "$ACTION" == "status" ]]; then
    show_status
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 $ACTION で実行してください。"
fi

case "$ACTION" in
    disable) do_disable ;;
    enable)  do_enable ;;
    *)       usage ;;
esac
