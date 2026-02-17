#!/bin/bash
# setup-gpu-power-limit.sh
#
# RX 5600 XT の Power Cap を Silent相当 (135W) に制限する
# systemd サービスをセットアップする。
#
# Usage:
#   sudo bash setup-gpu-power-limit.sh              # インストール
#   sudo bash setup-gpu-power-limit.sh --uninstall  # アンインストール
#
# What it does:
#   1. gpu-power-limit.sh を /usr/local/bin/ にインストール
#   2. systemd サービスを /etc/systemd/system/ にインストール
#   3. サービスの有効化と初回実行
#
# Requirements:
#   - root 権限 (sudo)
#   - RX 5600 XT (Navi 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPU_DIR="${SCRIPT_DIR}/rx5600xt"
UNIT_NAME="gpu-power-limit.service"
INSTALL_SCRIPT="/usr/local/bin/gpu-power-limit.sh"
SYSTEMD_DIR="/etc/systemd/system"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
fi

# ─── アンインストール ─────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    info "GPU Power Limit サービスをアンインストール中..."

    if systemctl is-active --quiet "$UNIT_NAME" 2>/dev/null; then
        systemctl stop "$UNIT_NAME"
        ok "$UNIT_NAME を停止"
    fi

    if systemctl is-enabled --quiet "$UNIT_NAME" 2>/dev/null; then
        systemctl disable "$UNIT_NAME"
        ok "$UNIT_NAME を無効化"
    fi

    if [[ -f "${SYSTEMD_DIR}/${UNIT_NAME}" ]]; then
        rm "${SYSTEMD_DIR}/${UNIT_NAME}"
        ok "${UNIT_NAME} を削除"
        systemctl daemon-reload
    fi

    if [[ -f "$INSTALL_SCRIPT" ]]; then
        rm "$INSTALL_SCRIPT"
        ok "$INSTALL_SCRIPT を削除"
    fi

    # Power Cap をデフォルトに戻す
    if [[ -f "${GPU_DIR}/gpu-power-limit.sh" ]]; then
        bash "${GPU_DIR}/gpu-power-limit.sh" off 2>/dev/null || true
    fi

    echo ""
    ok "アンインストール完了"
    exit 0
fi

# ─── 1. スクリプトのインストール ──────────────────────────
info "gpu-power-limit.sh をインストール中..."

if [[ -f "$INSTALL_SCRIPT" ]] && diff -q "${GPU_DIR}/gpu-power-limit.sh" "$INSTALL_SCRIPT" &>/dev/null; then
    skip "$INSTALL_SCRIPT は最新"
else
    cp "${GPU_DIR}/gpu-power-limit.sh" "$INSTALL_SCRIPT"
    chmod +x "$INSTALL_SCRIPT"
    ok "$INSTALL_SCRIPT をインストール"
fi

# ─── 2. systemd サービスのインストール ────────────────────
info "systemd サービスをインストール中..."

SCRIPT_PATH="$(dirname "$INSTALL_SCRIPT")"
GENERATED=$(sed "s|@@SCRIPT_PATH@@|${SCRIPT_PATH}|g" "${GPU_DIR}/${UNIT_NAME}")
DST="${SYSTEMD_DIR}/${UNIT_NAME}"

NEEDS_RELOAD=false

if [[ -f "$DST" ]] && [[ "$GENERATED" = "$(cat "$DST")" ]]; then
    skip "${UNIT_NAME} は最新"
else
    echo "$GENERATED" > "$DST"
    ok "${UNIT_NAME} をインストール"
    NEEDS_RELOAD=true
fi

if [[ "$NEEDS_RELOAD" = true ]]; then
    systemctl daemon-reload
    ok "systemd daemon-reload"
fi

# ─── 3. サービスの有効化と初回実行 ────────────────────────
info "サービスを有効化中..."

if systemctl is-enabled --quiet "$UNIT_NAME" 2>/dev/null; then
    skip "${UNIT_NAME} は既に有効"
else
    systemctl enable "$UNIT_NAME"
    ok "${UNIT_NAME} を有効化"
fi

# 初回実行
info "Power Cap を適用中..."
bash "$INSTALL_SCRIPT" on

if bash "$INSTALL_SCRIPT" status 2>/dev/null | grep -q "Silent"; then
    ok "Power Cap 適用成功"
else
    error "Power Cap の適用に失敗しました"
fi

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "GPU Power Limit セットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "起動時に自動で Power Cap 135W (Silent相当) が適用されます"
echo ""
info "  状態確認:     sudo gpu-power-limit.sh status"
info "  手動で解除:   sudo gpu-power-limit.sh off"
info "  サービス確認: systemctl status $UNIT_NAME"
info "  アンインストール: sudo bash $0 --uninstall"
echo ""
