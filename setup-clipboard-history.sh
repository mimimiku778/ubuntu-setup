#!/usr/bin/env bash
# setup-clipboard-history.sh
#
# Clipboard History GNOME拡張 (clipboard-history@alexsaveau.dev) のインストール＆カスタマイズ
#
# 機能:
#   - GNOME Extensions アプリがなければインストール
#   - Clipboard History 拡張がなければインストール
#   - 左右キーで隣のトレイアイコンメニューに移動しないようブロック
#   - dconf設定を適用 (Super+V でトグル)
#
# パターンマッチベースのパッチなのでバージョンアップにもある程度追従可能

set -euo pipefail

EXT_UUID="clipboard-history@alexsaveau.dev"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
EXT_JS="$EXT_DIR/extension.js"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# ─── 1. GNOME Shell 確認 ─────────────────────────────────
if ! command -v gnome-shell &>/dev/null; then
    error "GNOME Shell が見つかりません。GNOME デスクトップ環境で実行してください。"
fi
info "GNOME Shell $(gnome-shell --version)"

# ─── 2. Extension Manager (GUI) インストール ──────────────
if ! dpkg -l gnome-shell-extension-manager &>/dev/null; then
    info "gnome-shell-extension-manager をインストール中..."
    sudo apt update && sudo apt install -y gnome-shell-extension-manager
    ok "Extension Manager インストール完了"
else
    ok "Extension Manager は既にインストール済み"
fi

# ─── 3. Clipboard History インストール ────────────────────
if [ ! -d "$EXT_DIR" ]; then
    info "Clipboard History をインストール中..."

    # pipx 経由で gnome-extensions-cli (gext) を使う
    if ! command -v pipx &>/dev/null; then
        info "pipx をインストール中..."
        sudo apt install -y pipx
        pipx ensurepath
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if ! command -v gext &>/dev/null; then
        info "gnome-extensions-cli (gext) をインストール中..."
        pipx install gnome-extensions-cli
        export PATH="$HOME/.local/bin:$PATH"
    fi

    gext install "$EXT_UUID"
    ok "Clipboard History インストール完了"
else
    ok "Clipboard History は既にインストール済み: $EXT_DIR"
fi

# 拡張を有効化
gnome-extensions enable "$EXT_UUID" 2>/dev/null || true

# ─── 4. extension.js の存在確認 ──────────────────────────
[ -f "$EXT_JS" ] || error "$EXT_JS が見つかりません"

# バックアップ作成
BACKUP="$EXT_JS.bak.$(date +%Y%m%d%H%M%S)"
cp "$EXT_JS" "$BACKUP"
info "バックアップ作成: $BACKUP"

# ─── 5. パッチ: 左右キーで隣のメニューに移動しないようにする ─
if grep -q "Block Left/Right arrow key navigation" "$EXT_JS"; then
    ok "左右キーブロックパッチは適用済み"
elif grep -q "this._buildMenu();" "$EXT_JS"; then
    python3 - "$EXT_JS" << 'PYEOF'
import re, sys

ext_js = sys.argv[1]

with open(ext_js, 'r') as f:
    content = f.read()

# Ensure Clutter import exists
if 'gi://Clutter' not in content:
    if "import GLib from 'gi://GLib'" in content:
        content = content.replace(
            "import GLib from 'gi://GLib';",
            "import GLib from 'gi://GLib';\nimport Clutter from 'gi://Clutter';",
            1
        )
    else:
        m = re.search(r"(.*from\s+'gi://GLib'.*;\n)", content)
        if m:
            content = content[:m.end()] + "import Clutter from 'gi://Clutter';\n" + content[m.end():]

anchor = 'this._buildMenu();'
if anchor not in content:
    print('WARN: anchor not found', file=sys.stderr)
    sys.exit(1)

code = """
    // Block Left/Right arrow key navigation to adjacent panel menus
    this.menu.actor.connect('captured-event', (actor, event) => {
        if (event.type() === Clutter.EventType.KEY_PRESS) {
            const symbol = event.get_key_symbol();
            if (symbol === Clutter.KEY_Left || symbol === Clutter.KEY_Right) {
                return Clutter.EVENT_STOP;
            }
        }
        return Clutter.EVENT_PROPAGATE;
    });"""

content = content.replace(anchor, anchor + code, 1)

with open(ext_js, 'w') as f:
    f.write(content)
print('OK')
PYEOF
    ok "左右キーブロックパッチを適用"
else
    warn "_buildMenu() の行が見つかりません"
fi

# ─── 6. Ubuntu デフォルトの Super+V (通知トレイ) を解除 ──
info "既存の Super+V キーバインドを解除中..."
gsettings set org.gnome.shell.keybindings toggle-message-tray '[]'
ok "通知トレイの Super+V を解除"

# ─── 7. dconf 設定適用 ──────────────────────────────────
info "dconf 設定を適用中..."
DCONF_PATH="/org/gnome/shell/extensions/clipboard-history"
dconf write "$DCONF_PATH/display-mode" 3
dconf write "$DCONF_PATH/enable-keybindings" true
dconf write "$DCONF_PATH/toggle-menu" "['<Super>v']"

ok "dconf 設定完了 (display-mode=3, keybindings=true, toggle=Super+V)"

# ─── 8. 完了 ────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "セットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "反映するにはGNOME Shellを再起動してください:"
info "  X11:    Alt+F2 → r → Enter"
info "  Wayland: ログアウト → ログイン"
echo ""
info "使い方: Super+V でクリップボード履歴を表示"
