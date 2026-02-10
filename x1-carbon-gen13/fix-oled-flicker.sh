#!/bin/bash
# fix-oled-flicker.sh
#
# X1 Carbon Gen 13 OLED のちらつきを修正する。
# GPU を制御しているドライバ（i915 または xe）を自動検出し、
# PSR 関連パラメータをトグルする。
#
# Usage:
#   sudo bash fix-oled-flicker.sh [disable|enable|status]
#
#   disable  PSR 関連パラメータをすべて無効化する（デフォルト）
#   enable   PSR 関連パラメータをすべて有効化する（元に戻す）
#   status   現在の設定を表示する
#
# PSR パラメータ (ドライバに応じて i915. または xe. プレフィックス):
#   enable_psr=0              Panel Self Refresh
#   enable_psr2_sel_fetch=0   PSR2 Selective Fetch
#
# Note:
#   PSR 無効化によりバッテリー消費が 0.5〜1.5W 程度増加する可能性があります。

set -euo pipefail

GRUB_DEFAULT="/etc/default/grub"

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
PSR_PARAMS=("${GPU_DRIVER}.enable_psr" "${GPU_DRIVER}.enable_psr2_sel_fetch")
# 旧ドライバのパラメータ（クリーンアップ用）
if [[ "$GPU_DRIVER" == "i915" ]]; then
    OLD_PARAMS=("xe.enable_psr" "xe.enable_psr2_sel_fetch")
else
    OLD_PARAMS=("i915.enable_psr" "i915.enable_psr2_sel_fetch")
fi
ALL_PSR_PARAMS=("${PSR_PARAMS[@]}" "${OLD_PARAMS[@]}")

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }
error_noexit() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ─── 使い方 ──────────────────────────────────────────────
usage() {
    echo "Usage: sudo bash $0 [disable|enable|status]"
    echo ""
    echo "  disable  PSR を無効化してちらつきを抑える（デフォルト）"
    echo "  enable   PSR を有効化して省電力に戻す"
    echo "  status   現在の設定を表示"
    exit 1
}

# ─── 現在の状態を取得 ────────────────────────────────────
get_grub_cmdline() {
    grep -oP 'GRUB_CMDLINE_LINUX_DEFAULT="\K[^"]*' "$GRUB_DEFAULT"
}

# ─── 現在の状態を表示 ────────────────────────────────────
show_status() {
    info "検出されたドライバ: ${GPU_DRIVER}"
    echo ""

    info "GRUB 設定 (/etc/default/grub):"
    local cmdline
    cmdline=$(get_grub_cmdline)
    for param in "${PSR_PARAMS[@]}"; do
        if echo "$cmdline" | grep -q "${param}=0"; then
            warn "  ${param}=0 (無効)"
        else
            ok "  ${param} (デフォルト/有効)"
        fi
    done
    # 旧ドライバのパラメータが残っていたら警告
    for param in "${OLD_PARAMS[@]}"; do
        if echo "$cmdline" | grep -q "${param}="; then
            error_noexit "  ${param} が残っています（ドライバは ${GPU_DRIVER} なので効果なし）"
        fi
    done

    echo ""
    info "カーネルパラメータ (/proc/cmdline):"
    local boot_cmdline
    boot_cmdline=$(cat /proc/cmdline)
    for param in "${PSR_PARAMS[@]}"; do
        if echo "$boot_cmdline" | grep -q "${param}=0"; then
            warn "  ${param}=0 (無効・反映済み)"
        else
            ok "  ${param} (デフォルト/有効・反映済み)"
        fi
    done

    echo ""
    info "ドライバパラメータ (/sys/module/${GPU_DRIVER}/parameters/):"
    for param in "${PSR_PARAMS[@]}"; do
        local sysfs_name="${param#${GPU_DRIVER}.}"
        local val
        val=$(cat "/sys/module/${GPU_DRIVER}/parameters/${sysfs_name}" 2>/dev/null || echo "読み取り不可")
        if [[ "$val" == "0" || "$val" == "N" ]]; then
            warn "  ${sysfs_name} = ${val} (無効)"
        else
            ok "  ${sysfs_name} = ${val} (有効)"
        fi
    done
}

# ─── GRUB からパラメータを削除（旧ドライバのパラメータも含む）───
remove_psr_params() {
    local cmdline
    cmdline=$(get_grub_cmdline)
    local new_cmdline="$cmdline"
    for param in "${ALL_PSR_PARAMS[@]}"; do
        new_cmdline=$(echo "$new_cmdline" | sed "s/ *${param}=[^ ]*//g")
    done
    # 重複スペースを除去
    new_cmdline=$(echo "$new_cmdline" | sed 's/  */ /g; s/^ //; s/ $//')
    sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmdline}\"|" "$GRUB_DEFAULT"
}

# ─── GRUB にパラメータを追加 ─────────────────────────────
add_psr_params() {
    for param in "${PSR_PARAMS[@]}"; do
        local cmdline
        cmdline=$(get_grub_cmdline)
        if ! echo "$cmdline" | grep -q "${param}=0"; then
            sed -i "s|\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)|\1 ${param}=0|" "$GRUB_DEFAULT"
        fi
    done
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

if [[ "$ACTION" != "disable" && "$ACTION" != "enable" ]]; then
    usage
fi

# ─── バックアップ ─────────────────────────────────────────
backup="${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
cp "$GRUB_DEFAULT" "$backup"
info "バックアップ作成: $backup"

# ─── トグル実行 ──────────────────────────────────────────
case "$ACTION" in
    disable)
        info "検出されたドライバ: ${GPU_DRIVER}"
        info "PSR 関連パラメータを無効化中..."
        # 既存のPSRパラメータを一度削除してからすべて追加（旧ドライバ分もクリーンアップ）
        remove_psr_params
        add_psr_params
        ;;
    enable)
        info "検出されたドライバ: ${GPU_DRIVER}"
        info "PSR 関連パラメータを有効化中（パラメータを削除）..."
        remove_psr_params
        ;;
esac

# ─── 結果確認 ────────────────────────────────────────────
info "変更後の GRUB_CMDLINE_LINUX_DEFAULT:"
info "  $(get_grub_cmdline)"

# ─── update-grub ──────────────────────────────────────────
info "update-grub を実行中..."
update-grub
ok "GRUB 設定を更新しました"

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$ACTION" == "disable" ]]; then
    ok "PSR 無効化完了! (ちらつき対策 ON)"
else
    ok "PSR 有効化完了! (省電力モード)"
fi
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "反映するには再起動が必要です:"
info "  sudo reboot"
echo ""
info "元に戻す場合:"
info "  sudo cp $backup $GRUB_DEFAULT"
info "  sudo update-grub && sudo reboot"
