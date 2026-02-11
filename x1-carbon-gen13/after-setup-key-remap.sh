#!/bin/bash
# after-setup-key-remap.sh
#
# keyd セットアップ後に必要な追加設定を行う。
#
# Usage:
#   sudo bash after-setup-key-remap.sh
#
# What it does:
#   1. libinput quirks を作成し、keyd 仮想キーボードを内蔵キーボードとして認識させる
#      → DWT (disable-while-typing / 入力中にタッチパッド無効) が正常に機能するようになる
#
# Background:
#   keyd は物理キーボードのイベントを横取りし、仮想キーボード (usb:0fac:0ade) から
#   再送信する。libinput はこの仮想キーボードを USB 外部デバイスと認識するため、
#   DWT のペアリング対象から除外してしまう。quirks ファイルで AttrKeyboardIntegration=internal
#   を指定することで、内蔵キーボードとして扱わせる。
#
# Requirements:
#   - root 権限 (sudo)
#   - keyd がインストール・稼働済み (setup-key-remap.sh を先に実行)
#
# Note:
#   反映には再ログインが必要 (mutter が libinput デバイスを再初期化するため)

set -euo pipefail

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
fi

# ─── keyd 稼働チェック ────────────────────────────────────
if ! systemctl is-active --quiet keyd; then
    error "keyd が稼働していません。先に setup-key-remap.sh を実行してください。"
fi

# ─── libinput quirks: keyd DWT 修正 ──────────────────────
QUIRKS_DIR="/etc/libinput"
QUIRKS_FILE="$QUIRKS_DIR/local-overrides.quirks"
QUIRKS_SECTION="[keyd virtual keyboard]"

if [[ -f "$QUIRKS_FILE" ]] && grep -qF "$QUIRKS_SECTION" "$QUIRKS_FILE"; then
    skip "libinput quirks は既に設定済み: $QUIRKS_FILE"
else
    info "libinput quirks を作成中..."
    mkdir -p "$QUIRKS_DIR"
    cat > "$QUIRKS_FILE" << 'QUIRKS_EOF'
[keyd virtual keyboard]
MatchUdevType=keyboard
MatchName=keyd virtual keyboard
AttrKeyboardIntegration=internal
QUIRKS_EOF
    ok "libinput quirks 作成完了: $QUIRKS_FILE"
fi

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "keyd 後処理セットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "設定内容:"
info "  - libinput quirks: keyd 仮想キーボードを内蔵として認識 → DWT 有効化"
echo ""
info "反映には再ログインが必要です。"
echo ""
