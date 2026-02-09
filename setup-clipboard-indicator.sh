#!/usr/bin/env bash
# setup-clipboard-indicator.sh
#
# Clipboard Indicator GNOME拡張のインストール＆カスタマイズ
#   - GNOME Extensions アプリがなければインストール
#   - Clipboard Indicator 拡張がなければインストール
#   - アイコンをトップバーのセンターに配置
#   - display-mode=3 (Neither) を透明1pxに改良（ショートカット経由で使えるように）
#   - dconf設定を適用
#
# パターンマッチベースのパッチなのでバージョンアップにもある程度追従可能

set -euo pipefail

EXT_UUID="clipboard-indicator@tudmotu.com"
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

# ─── 3. Clipboard Indicator インストール ──────────────────
if [ ! -d "$EXT_DIR" ]; then
    info "Clipboard Indicator をインストール中..."

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
    ok "Clipboard Indicator インストール完了"
else
    ok "Clipboard Indicator は既にインストール済み: $EXT_DIR"
fi

# 拡張を有効化
gnome-extensions enable "$EXT_UUID" 2>/dev/null || true

# ─── 4. extension.js の存在確認 ──────────────────────────
[ -f "$EXT_JS" ] || error "$EXT_JS が見つかりません"

# バックアップ作成
BACKUP="$EXT_JS.bak.$(date +%Y%m%d%H%M%S)"
cp "$EXT_JS" "$BACKUP"
info "バックアップ作成: $BACKUP"

# ─── 5. パッチ: addToStatusArea をセンターに変更 ─────────
# オリジナル: addToStatusArea('clipboardIndicator', this.clipboardIndicator, 1);
# ↓
# 変更後:    addToStatusArea('clipboardIndicator', this.clipboardIndicator, 1, 'center');
#
# 既に 'center' が含まれていたらスキップ
if grep -q "addToStatusArea.*clipboardIndicator.*0,\s*'center'" "$EXT_JS"; then
    ok "センター配置パッチは適用済み（時計の左側）"
elif grep -q "addToStatusArea.*'clipboardIndicator'" "$EXT_JS"; then
    # addToStatusArea の位置を 0 に変更し、'center' を追加（時計の左側に配置）
    # パターン: addToStatusArea('clipboardIndicator', this.clipboardIndicator, <数字>)
    # → addToStatusArea('clipboardIndicator', this.clipboardIndicator, 0, 'center')
    sed -i -E \
        "s/addToStatusArea\('clipboardIndicator',\s*this\.clipboardIndicator,\s*[0-9]+\)/addToStatusArea('clipboardIndicator', this.clipboardIndicator, 0, 'center')/" \
        "$EXT_JS"
    ok "センター配置パッチを適用（時計の左側）"
else
    warn "addToStatusArea の行が見つかりません（拡張のバージョン変更の可能性）"
fi

# ─── 6. パッチ: mode 3 を透明1pxに改良 ──────────────────
# オリジナル:
#   if (TOPBAR_DISPLAY_MODE === 3) {
#       this.hide();
#   }
# ↓
# 変更後:
#   if (TOPBAR_DISPLAY_MODE === 3) {
#       this.icon.visible = false;
#       this._buttonText.visible = false;
#       this._buttonImgPreview.visible = false;
#       this._downArrow.visible = false;
#       this.set_width(1);
#       this.set_opacity(0);
#       this.show();
#   }

if grep -q "TOPBAR_DISPLAY_MODE === 3" "$EXT_JS" && grep -q "this.reactive = false" "$EXT_JS"; then
    ok "mode 3 透明化パッチは適用済み"
elif grep -Pzo "TOPBAR_DISPLAY_MODE === 3\) \{\s*\n\s*this\.hide\(\)" "$EXT_JS" &>/dev/null; then
    # this.hide() を透明1px化コードに置換
    python3 -c "
import re, sys

with open('$EXT_JS', 'r') as f:
    content = f.read()

old = re.compile(
    r'(if\s*\(TOPBAR_DISPLAY_MODE\s*===\s*3\)\s*\{)\s*\n(\s*)this\.hide\(\);',
    re.MULTILINE
)

def replacement(m):
    indent = m.group(2)
    return (
        m.group(1) + '\n'
        + indent + 'this.icon.visible = false;\n'
        + indent + 'this._buttonText.visible = false;\n'
        + indent + 'this._buttonImgPreview.visible = false;\n'
        + indent + 'this._downArrow.visible = false;\n'
        + indent + 'this.set_width(1);\n'
        + indent + 'this.set_opacity(0);\n'
        + indent + 'this.reactive = false;\n'
        + indent + 'this.show();'
    )

new_content = old.sub(replacement, content)
if new_content == content:
    print('WARN: パターンにマッチしませんでした', file=sys.stderr)
    sys.exit(1)

with open('$EXT_JS', 'w') as f:
    f.write(new_content)
print('OK')
"
    ok "mode 3 透明化パッチを適用 (this.hide() → 透明1px)"
else
    warn "mode 3 の this.hide() パターンが見つかりません（既に変更済み or バージョン変更）"
fi

# ─── 7. パッチ: _updateTopbarLayout 先頭にリセット追加 ──
# mode 3 から他モードに切り替えたとき width/opacity を戻すためのリセット
if grep -q "set_width(-1)" "$EXT_JS"; then
    ok "width/opacity リセットは適用済み"
elif grep -q "_updateTopbarLayout" "$EXT_JS"; then
    python3 -c "
import re

with open('$EXT_JS', 'r') as f:
    content = f.read()

old = re.compile(
    r'(_updateTopbarLayout\s*\(\)\s*\{)\s*\n',
    re.MULTILINE
)

def replacement(m):
    # 関数の最初のif文のインデントを推測
    return (
        m.group(1) + '\n'
        + '        // Reset width/opacity/reactive in case we are switching away from mode 3\n'
        + '        this.set_width(-1);\n'
        + '        this.set_opacity(255);\n'
        + '        this.reactive = true;\n'
        + '\n'
    )

new_content = old.sub(replacement, content, count=1)
with open('$EXT_JS', 'w') as f:
    f.write(new_content)
print('OK')
"
    ok "width/opacity リセットを _updateTopbarLayout 先頭に追加"
fi

# ─── 8. パッチ: 下矢印がmode 3を上書きしないようにガード ─
# オリジナル:
#   if(!DISABLE_DOWN_ARROW) {
#       this._downArrow.visible = true;
#   } else {
#       this._downArrow.visible = false;
#   }
# ↓
# 変更後:
#   if (TOPBAR_DISPLAY_MODE !== 3) {
#       this._downArrow.visible = !DISABLE_DOWN_ARROW;
#   }
if grep -q "TOPBAR_DISPLAY_MODE !== 3" "$EXT_JS"; then
    ok "下矢印ガードは適用済み"
elif grep -Pzo "DISABLE_DOWN_ARROW\)\s*\{\s*\n\s*this\._downArrow\.visible\s*=\s*true;" "$EXT_JS" &>/dev/null; then
    python3 -c "
import re

with open('$EXT_JS', 'r') as f:
    content = f.read()

old = re.compile(
    r'if\s*\(\s*!DISABLE_DOWN_ARROW\s*\)\s*\{\s*\n'
    r'\s*this\._downArrow\.visible\s*=\s*true;\s*\n'
    r'\s*\}\s*else\s*\{\s*\n'
    r'\s*this\._downArrow\.visible\s*=\s*false;\s*\n'
    r'\s*\}',
    re.MULTILINE
)

replacement = (
    'if (TOPBAR_DISPLAY_MODE !== 3) {\n'
    '            this._downArrow.visible = !DISABLE_DOWN_ARROW;\n'
    '        }'
)

new_content = old.sub(replacement, content, count=1)
with open('$EXT_JS', 'w') as f:
    f.write(new_content)
print('OK')
"
    ok "下矢印ガードを適用"
else
    warn "下矢印パターンが見つかりません（既に変更済み or バージョン変更）"
fi

# ─── 9. パッチ: メニューを画面中央に表示 ─────────────────
# open-state-changed ハンドラにメニュー中央配置コードを追加
# メニューが開いた後に画面中央に set_translation で移動させる
if grep -q "Center the menu on screen" "$EXT_JS"; then
    ok "メニュー中央配置パッチは適用済み"
elif grep -Pzo "that\.menu\.connect\('open-state-changed',\s*\(self,\s*open\)\s*=>\s*\{\s*\n\s*this\._setFocusOnOpenTimeout" "$EXT_JS" &>/dev/null; then
    python3 -c "
import re

with open('$EXT_JS', 'r') as f:
    content = f.read()

old = re.compile(
    r\"(that\.menu\.connect\('open-state-changed',\s*\(self,\s*open\)\s*=>\s*\{)\s*\n(\s*)(this\._setFocusOnOpenTimeout)\",
    re.MULTILINE
)

def replacement(m):
    indent = m.group(2)
    return (
        m.group(1) + '\n'
        + indent + '// Center the menu on screen\n'
        + indent + 'if (open) {\n'
        + indent + '    this.menu.actor.set_opacity(255);\n'
        + indent + '    this.menu.actor.visible = true;\n'
        + indent + '    this.menu.actor.set_translation(0, 0, 0);\n'
        + indent + '    this._centerMenuTimeout = setTimeout(() => {\n'
        + indent + '        let actor = this.menu.actor;\n'
        + indent + '        let [menuX] = actor.get_transformed_position();\n'
        + indent + '        let menuWidth = actor.get_width();\n'
        + indent + '        let monitor = Main.layoutManager.primaryMonitor;\n'
        + indent + '        let targetX = monitor.x + (monitor.width - menuWidth) / 2;\n'
        + indent + '        actor.set_translation(targetX - menuX, 0, 0);\n'
        + indent + '    }, 0);\n'
        + indent + '} else {\n'
        + indent + '    // Hide instantly to prevent position jump during close animation\n'
        + indent + '    this.menu.actor.visible = false;\n'
        + indent + '    this.menu.actor.set_translation(0, 0, 0);\n'
        + indent + '    if (this._centerMenuTimeout) {\n'
        + indent + '        clearTimeout(this._centerMenuTimeout);\n'
        + indent + '        this._centerMenuTimeout = null;\n'
        + indent + '    }\n'
        + indent + '}\n'
        + '\n'
        + indent + m.group(3)
    )

new_content = old.sub(replacement, content, count=1)
if new_content == content:
    print('WARN: パターンにマッチしませんでした', file=sys.stderr)
    import sys; sys.exit(1)

with open('$EXT_JS', 'w') as f:
    f.write(new_content)
print('OK')
"
    ok "メニュー中央配置パッチを適用"
else
    warn "open-state-changed ハンドラが見つかりません（既に変更済み or バージョン変更）"
fi

# _centerMenuTimeout のクリーンアップを #clearTimeouts に追加
if grep -q "_centerMenuTimeout" "$EXT_JS" && grep -q "clearTimeout(this._centerMenuTimeout)" "$EXT_JS"; then
    # clearTimeouts にも追加されているか確認
    if grep -Pzo "#clearTimeouts.*?_centerMenuTimeout" "$EXT_JS" &>/dev/null; then
        ok "centerMenuTimeout クリーンアップは適用済み"
    else
        sed -i 's/if (this._imagePreviewTimeout) clearTimeout(this._imagePreviewTimeout);/if (this._centerMenuTimeout) clearTimeout(this._centerMenuTimeout);\n        if (this._imagePreviewTimeout) clearTimeout(this._imagePreviewTimeout);/' "$EXT_JS"
        ok "centerMenuTimeout クリーンアップを #clearTimeouts に追加"
    fi
fi

# ─── 9b. パッチ: メニュー閉じるときのズレ修正 ────────────
# 既にセンター配置パッチが当たっている環境向け
# close 時に即座に opacity=0 にしてアニメーション中の位置ズレを防止
if grep -q "Center the menu on screen" "$EXT_JS" && ! grep -q "Hide instantly" "$EXT_JS"; then
    python3 -c "
import re

with open('$EXT_JS', 'r') as f:
    content = f.read()

# } else { の直後、_centerMenuTimeout チェックの前に opacity=0 と translation リセットを挿入
old = re.compile(
    r'(\}\s*else\s*\{)\s*\n'
    r'(\s*)(if\s*\(this\._centerMenuTimeout\)\s*\{\s*\n'
    r'\s*clearTimeout\(this\._centerMenuTimeout\);\s*\n'
    r'\s*this\._centerMenuTimeout\s*=\s*null;)',
    re.MULTILINE
)

def replacement(m):
    indent = m.group(2)
    return (
        m.group(1) + '\n'
        + indent + '// Hide instantly to prevent position jump during close animation\n'
        + indent + 'this.menu.actor.visible = false;\n'
        + indent + 'this.menu.actor.set_translation(0, 0, 0);\n'
        + indent + m.group(3)
    )

new_content = old.sub(replacement, content, count=1)
if new_content == content:
    print('WARN: パターンにマッチしませんでした', file=sys.stderr)
    import sys; sys.exit(1)

with open('$EXT_JS', 'w') as f:
    f.write(new_content)
print('OK')
"
    ok "メニュー閉じるときのズレ修正を適用"
elif grep -q "Hide instantly" "$EXT_JS"; then
    ok "メニュー閉じるときのズレ修正は適用済み"
fi

# ─── 10. dconf 設定適用 ──────────────────────────────────
info "dconf 設定を適用中..."
dconf write /org/gnome/shell/extensions/clipboard-indicator/display-mode 3
dconf write /org/gnome/shell/extensions/clipboard-indicator/enable-keybindings true
# Super+V でメニュー表示（既にデフォルトのはず）
dconf write /org/gnome/shell/extensions/clipboard-indicator/toggle-menu "['<Super>v']"

ok "dconf 設定完了 (display-mode=3, keybindings=true, toggle=Super+V)"

# ─── 11. 完了 ────────────────────────────────────────────
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
