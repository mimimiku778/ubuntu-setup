#!/usr/bin/env bash
# uninstall.sh — libscroll-speed のアンインストール
#
# ld.so.preload からエントリを削除し、ライブラリと設定ファイルを除去します。
# 反映にはログアウト→再ログインが必要です。

set -euo pipefail

LIB_PATH="/usr/local/lib/x86_64-linux-gnu/libscroll-speed.so"
PRELOAD="/etc/ld.so.preload"
CONF="/etc/scroll-speed.conf"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

# ── ld.so.preload からエントリ削除 ──
if grep -q 'libscroll-speed' "$PRELOAD" 2>/dev/null; then
    sudo sed -i '/libscroll-speed/d' "$PRELOAD"
    ok "ld.so.preload からエントリを削除"
else
    info "ld.so.preload にエントリなし（スキップ）"
fi

# ── ライブラリ削除 ──
if [[ -f "$LIB_PATH" ]]; then
    sudo rm -f "$LIB_PATH"
    ok "ライブラリを削除: $LIB_PATH"
else
    info "ライブラリなし: $LIB_PATH（スキップ）"
fi

# ── 設定ファイル削除 ──
if [[ -f "$CONF" ]]; then
    sudo rm -f "$CONF"
    ok "設定ファイルを削除: $CONF"
else
    info "設定ファイルなし（スキップ）"
fi

echo ""
ok "アンインストール完了"
warn "反映にはログアウト→再ログインが必要です"
