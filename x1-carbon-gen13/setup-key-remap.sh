#!/bin/bash
# setup-key-remap.sh
#
# ThinkPad X1 Carbon Gen 13 のキーリマッピングを設定する。
# keyd を使用して Wayland / X11 両対応のキーリマッピングを実現。
#
# Usage:
#   sudo bash setup-key-remap.sh
#
# What it does:
#   1. keyd をインストール (未インストールの場合)
#   2. udev hwdb で ThinkPad Extra Buttons のキーをリマップ:
#      - F7  Display Switch (KEY_SWITCHVIDEOMODE) → F16
#      - F10 Snipping Tool (KEY_SELECTIVE_SCREENSHOT) → F14
#      - F11 Phone Link (KEY_LINK_PHONE) → F15
#      - F12 Bookmarks (KEY_BOOKMARKS) → F17
#   3. 以下のキーリマッピングを設定:
#      - 左 Alt → 単独押しで無変換 (Muhenkan) / 他キーとの組み合わせで Alt / 300ms 長押しで Alt
#      - 右 Alt → 変換 (Henkan)
#      - CapsLock → F13
#      - Shift + CapsLock → CapsLock
#      - Copilot ボタン (F23) → Alt
#   4. keyd サービスを有効化・再起動
#
# Requirements:
#   - root 権限 (sudo)
#   - Linux kernel 6.14 以降 (F23 スキャンコード 0x6e のサポート)

set -euo pipefail

KEYD_CONF="/etc/keyd/default.conf"
MARKER="# Managed by setup-key-remap.sh"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
fi

# ─── カーネルバージョンチェック ────────────────────────────
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)
if [[ "$KERNEL_MAJOR" -lt 6 ]] || { [[ "$KERNEL_MAJOR" -eq 6 ]] && [[ "$KERNEL_MINOR" -lt 14 ]]; }; then
    warn "カーネル $(uname -r) は 6.14 未満です。"
    warn "Copilot キー (F23 スキャンコード 0x6e) が正しく動作しない可能性があります。"
fi

# ─── keyd インストール ────────────────────────────────────
if command -v keyd &>/dev/null || command -v keyd.rvaiya &>/dev/null; then
    ok "keyd はインストール済み"
else
    info "keyd をインストール中..."
    apt-get update -qq
    apt-get install -y -qq keyd
    ok "keyd をインストール完了"
fi

# ─── keyd バイナリのパスを特定 ────────────────────────────
KEYD_BIN=""
if command -v keyd &>/dev/null; then
    KEYD_BIN="keyd"
elif command -v keyd.rvaiya &>/dev/null; then
    KEYD_BIN="keyd.rvaiya"
else
    # dpkg から探す
    KEYD_BIN=$(dpkg -L keyd 2>/dev/null | grep -E '/bin/keyd' | head -1) || true
    if [[ -z "$KEYD_BIN" || ! -x "$KEYD_BIN" ]]; then
        error "keyd バイナリが見つかりません"
    fi
fi

ok "keyd バイナリ: $KEYD_BIN"

# ─── udev hwdb: ThinkPad Extra Buttons リマップ ──────────
# GNOME が特殊扱いするキーや keyd が認識できない新しいキーコードを
# F14-F17 にリマップする。
HWDB_FILE="/etc/udev/hwdb.d/90-thinkpad-x1c-gen13.hwdb"
HWDB_MARKER="# Managed by setup-key-remap.sh"

if [[ -f "$HWDB_FILE" ]] && grep -qF "$HWDB_MARKER" "$HWDB_FILE"; then
    skip "$HWDB_FILE は既に設定済み"
else
    info "udev hwdb ルールを作成中..."
    mkdir -p /etc/udev/hwdb.d
    cat > "$HWDB_FILE" << 'HWDB_EOF'
# Managed by setup-key-remap.sh
# ThinkPad X1 Carbon Gen 13 - keyd 未対応・GNOME 特殊扱いキーのリマップ
# F7  Display Switch (KEY_SWITCHVIDEOMODE scan=0x06) -> F16
# F10 Snipping Tool (KEY_SELECTIVE_SCREENSHOT scan=0x46) -> F14
# F11 Phone Link (KEY_LINK_PHONE scan=0x1402) -> F15
# F12 Bookmarks (KEY_BOOKMARKS scan=0x45) -> F17
evdev:name:ThinkPad Extra Buttons:*
 KEYBOARD_KEY_06=f16
 KEYBOARD_KEY_46=f14
 KEYBOARD_KEY_1402=f15
 KEYBOARD_KEY_45=f17
HWDB_EOF
    systemd-hwdb update
    udevadm trigger /dev/input/event*
    ok "udev hwdb ルール作成・適用完了: $HWDB_FILE"
fi

# ─── 設定ディレクトリ確認 ─────────────────────────────────
mkdir -p /etc/keyd

# ─── 冪等性チェック ───────────────────────────────────────
if [[ -f "$KEYD_CONF" ]] && grep -qF "$MARKER" "$KEYD_CONF"; then
    skip "$KEYD_CONF は既に設定済み"
    info "再設定する場合は、先に $KEYD_CONF を削除してから再実行してください。"
    exit 0
fi

# ─── 既存設定のバックアップ ───────────────────────────────
if [[ -f "$KEYD_CONF" ]]; then
    backup="${KEYD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$KEYD_CONF" "$backup"
    info "既存設定をバックアップ: $backup"
fi

# ─── keyd 設定ファイル作成 ────────────────────────────────
info "keyd 設定ファイルを作成中..."

cat > "$KEYD_CONF" << 'EOF'
# Managed by setup-key-remap.sh
# ThinkPad X1 Carbon Gen 13 キーリマッピング
#
# - 左 Alt     → 単独押しで無変換 (Muhenkan) / 他キーと組み合わせで Alt / 300ms 長押しで Alt
# - 右 Alt     → 変換 (Henkan)
# - CapsLock   → F13
# - Shift + CapsLock → CapsLock
# - Copilot    → Alt 修飾キー

[ids]

*

[main]

# 左 Alt: 単独押し → 無変換 / 他キーとの組み合わせ → Alt / 300ms 長押し → Alt
# overloadt2: 押下時は何も送信せず、他キーのタップで Alt 解決 (Alt リーク防止)
# タイムアウト 300ms: 長押しで Alt として確定 (Alt 単体使用に対応)
leftalt = overloadt2(alt, muhenkan, 300)

# 右 Alt → 変換
rightalt = henkan

# CapsLock → F13
capslock = f13

# Copilot ボタン (Meta+Shift+F23) → Alt
leftmeta+leftshift+f23 = leftalt

[shift]

# Shift + CapsLock → CapsLock (物理キー名で指定)
capslock = capslock

EOF

ok "設定ファイル作成: $KEYD_CONF"

# ─── keyd サービス有効化・再起動 ──────────────────────────
info "keyd サービスを再起動中..."
systemctl enable keyd
systemctl restart keyd

if systemctl is-active --quiet keyd; then
    ok "keyd サービスが稼働中"
else
    error "keyd サービスの起動に失敗しました。journalctl -u keyd で確認してください。"
fi

# ─── 検証 ────────────────────────────────────────────────
info "設定を検証中..."

if [[ -f "$KEYD_CONF" ]] && grep -q "leftalt = overloadt2(alt, muhenkan, 300)" "$KEYD_CONF" \
    && grep -q "rightalt = henkan" "$KEYD_CONF" \
    && grep -q "capslock = f13" "$KEYD_CONF" \
    && grep -q "leftmeta+leftshift+f23 = leftalt" "$KEYD_CONF"; then
    ok "設定ファイルの内容が正しいことを確認"
else
    error "設定ファイルの内容が不正です"
fi

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "キーリマッピングのセットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "リマッピング内容:"
info "  - 左 Alt     → 単独押しで無変換 / 他キーと組み合わせで Alt / 300ms 長押しで Alt"
info "  - 右 Alt     → 変換 (Henkan)"
info "  - CapsLock   → F13"
info "  - Shift+CapsLock → CapsLock"
info "  - Copilot    → Alt"
info "  - F7  Display Switch → F16 (hwdb)"
info "  - F10 Snipping Tool → F14 (hwdb)"
info "  - F11 Phone Link   → F15 (hwdb)"
info "  - F12 Bookmarks    → F17 (hwdb)"
echo ""
info "即座に反映されます。再起動は不要です。"
echo ""
info "動作確認:"
info "  sudo $KEYD_BIN monitor"
info "  でキー入力をリアルタイム確認できます (Ctrl+C で終了)。"
echo ""
info "元に戻す場合:"
info "  sudo rm $KEYD_CONF"
info "  sudo systemctl restart keyd"
