#!/bin/bash
# setup-xhci-resume-fix.sh
#
# s2idle (S0ix) スタンバイからの復帰後に Synaptics 指紋リーダー等の
# USB デバイスが "endpoint stalled" で認識不能になる問題のワークアラウンド。
#
# カーネルパラメータ xhci_hcd.quirks=0x80 (RESET_ON_RESUME) を追加し、
# レジューム時に xHCI コントローラを完全に再初期化させる。
#
# Usage:
#   sudo bash setup-xhci-resume-fix.sh
#
# What it does:
#   1. /etc/default/grub の GRUB_CMDLINE_LINUX_DEFAULT に xhci_hcd.quirks=0x80 を追加
#   2. update-grub を実行
#
# Requirements:
#   - root 権限 (sudo)
#   - GRUB ブートローダー
#
# References:
#   - https://bbs.archlinux.org/viewtopic.php?id=304768
#   - https://bbs.archlinux.org/viewtopic.php?id=307641

set -euo pipefail

GRUB_FILE="/etc/default/grub"
QUIRK="xhci_hcd.quirks=0x80"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
fi

# ─── 前提条件チェック ─────────────────────────────────────
if [[ ! -f "$GRUB_FILE" ]]; then
    error "$GRUB_FILE が見つかりません。"
fi

if ! command -v update-grub &>/dev/null; then
    error "update-grub が見つかりません。"
fi

# ─── 冪等性チェック ───────────────────────────────────────
if grep -q "$QUIRK" "$GRUB_FILE"; then
    skip "$QUIRK は既に設定済みです。"
    exit 0
fi

# ─── バックアップ ─────────────────────────────────────────
backup="${GRUB_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$GRUB_FILE" "$backup"
info "バックアップ作成: $backup"

# ─── GRUB_CMDLINE_LINUX_DEFAULT に追記 ────────────────────
sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)/\1 $QUIRK/" "$GRUB_FILE"

if ! grep -q "$QUIRK" "$GRUB_FILE"; then
    error "パラメータの追加に失敗しました。"
fi

ok "GRUB_CMDLINE_LINUX_DEFAULT に $QUIRK を追加"

# ─── update-grub ──────────────────────────────────────────
info "update-grub を実行中..."
update-grub
ok "GRUB 設定を更新"

# ─── 検証 ─────────────────────────────────────────────────
info "設定を検証中..."
current=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE")
ok "現在の設定: $current"

# ─── 完了 ─────────────────────────────────────────────────
echo ""
ok "xHCI RESET_ON_RESUME ワークアラウンドを設定しました。"
info "再起動後に有効になります。"
info ""
info "元に戻す場合:"
info "  sudo sed -i 's/ $QUIRK//' $GRUB_FILE && sudo update-grub"
