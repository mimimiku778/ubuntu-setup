#!/bin/bash
# setup-keyd-henkan-longpress.sh
#
# デスクトップキーボード用: 物理変換キーの長押しでフォーカス再サイクルを行う。
# fcitx5-mozc が直接入力モードに陥った場合の復帰用。
#
# Usage:
#   sudo bash setup-keyd-henkan-longpress.sh
#
# What it does:
#   1. keyd をインストール (未インストールの場合)
#   2. /usr/local/bin/keyd-refocus スクリプトを作成
#   3. /etc/keyd/default.conf に変換キーの timeout 設定を追加:
#      - 短押し → 変換 (Henkan)
#      - 300ms 長押し → Activities 開閉でフォーカス再サイクル
#   4. keyd サービスを有効化・再起動
#
# Note:
#   x1-carbon-gen13/setup-key-remap.sh とは排他。
#   ThinkPad X1 Carbon Gen 13 では setup-key-remap.sh を使用すること。
#
# Requirements:
#   - root 権限 (sudo)

set -euo pipefail

KEYD_CONF="/etc/keyd/default.conf"
MARKER="# Managed by setup-keyd-henkan-longpress.sh"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
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

# ─── フォーカス再サイクルスクリプト作成 ─────────────────────
REFOCUS_SCRIPT="/usr/local/bin/keyd-refocus"
info "フォーカス再サイクルスクリプトを作成中..."

cat > "$REFOCUS_SCRIPT" << 'REFOCUS_EOF'
#!/bin/bash
# Activities を一瞬開閉してフォーカスを再サイクルする
# keyd command() から呼ばれる (root 権限)
KEYD_BIN=$(command -v keyd.rvaiya || command -v keyd)
"$KEYD_BIN" do 'leftmeta 250ms escape'
REFOCUS_EOF

chmod +x "$REFOCUS_SCRIPT"
ok "フォーカス再サイクルスクリプト作成: $REFOCUS_SCRIPT"

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
# Managed by setup-keyd-henkan-longpress.sh
# デスクトップキーボード: 変換キー長押しでフォーカス再サイクル (強制ひらがな復帰)

[ids]

*

[main]

# 変換キー → 短押し: 変換 / 300ms 長押し: Activities 開閉でフォーカス再サイクル
henkan = timeout(henkan, 300, command(/usr/local/bin/keyd-refocus))

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

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "変換キー長押し設定完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "リマッピング内容:"
info "  - 変換キー短押し → 変換 (Henkan)"
info "  - 変換キー300ms長押し → フォーカス再サイクル (強制ひらがな復帰)"
echo ""
