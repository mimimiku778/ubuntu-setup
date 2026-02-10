#!/usr/bin/env bash
# setup-tiling-thirds.sh
#
# 画面を3分割するタイリング用 GNOME Shell 拡張をインストールする。
#
# Usage:
#   bash setup-tiling-thirds.sh
#
# What it does:
#   1. GNOME Shell バージョンを確認 (45以上が必要)
#   2. カスタム GNOME Shell 拡張 (tiling-thirds) をインストール
#   3. デフォルトの Super+Left/Right/Up キーバインドを解除
#   4. 拡張を有効化
#
# Keybindings:
#   Super+Left  → 画面の左 1/3
#   Super+Up    → 画面の中央 1/3
#   Super+Right → 画面の右 1/3
#
# Requirements:
#   - GNOME Shell 45+

set -euo pipefail

EXT_UUID="tiling-thirds@ubuntu-setup"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
SCHEMAS_DIR="$EXT_DIR/schemas"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# ─── 1. GNOME Shell バージョン確認 ───────────────────────
if ! command -v gnome-shell &>/dev/null; then
    error "GNOME Shell が見つかりません。GNOME デスクトップ環境で実行してください。"
fi

GNOME_VER=$(gnome-shell --version | grep -oP '[0-9]+' | head -1)
info "GNOME Shell $GNOME_VER を検出"

if (( GNOME_VER < 45 )); then
    error "GNOME Shell 45 以上が必要です (現在: $GNOME_VER)"
fi

# ─── 2. 拡張のインストール ───────────────────────────────
if [ -d "$EXT_DIR" ]; then
    info "既存の拡張を更新中..."
else
    info "拡張をインストール中..."
fi

mkdir -p "$SCHEMAS_DIR"

# metadata.json
cat > "$EXT_DIR/metadata.json" << METAEOF
{
    "name": "Tiling Thirds",
    "description": "Tile windows to thirds of the screen",
    "uuid": "$EXT_UUID",
    "shell-version": ["$GNOME_VER", "$((GNOME_VER + 1))", "$((GNOME_VER + 2))"],
    "settings-schema": "org.gnome.shell.extensions.tiling-thirds"
}
METAEOF

# extension.js
cat > "$EXT_DIR/extension.js" << 'JSEOF'
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class TilingThirdsExtension extends Extension {
    enable() {
        this._settings = this.getSettings();

        for (const name of ['tile-left-third', 'tile-center-third', 'tile-right-third']) {
            Main.wm.addKeybinding(
                name,
                this._settings,
                Meta.KeyBindingFlags.NONE,
                Shell.ActionMode.NORMAL,
                () => this._tileWindow(name),
            );
        }

        Main.wm.addKeybinding(
            'restore-window',
            this._settings,
            Meta.KeyBindingFlags.NONE,
            Shell.ActionMode.NORMAL,
            () => this._restoreWindow(),
        );

        // Restore original size when user starts dragging a tiled window
        this._grabBeginId = global.display.connect('grab-op-begin', (display, window, op) => {
            if (op !== Meta.GrabOp.MOVING || !window?._tilingThirdsRect)
                return;

            const r = window._tilingThirdsRect;
            const rect = window.get_frame_rect();

            // Calculate pointer position ratio within the tiled window
            const [pointerX] = global.get_pointer();
            const ratioX = (pointerX - rect.x) / rect.width;

            // Restore original size, keeping pointer at the same relative position
            const newX = Math.round(pointerX - r.width * ratioX);
            window.move_resize_frame(true, newX, r.y, r.width, r.height);
            delete window._tilingThirdsRect;
        });
    }

    _tileWindow(name) {
        const window = global.display.focus_window;
        if (!window || window.window_type !== Meta.WindowType.NORMAL)
            return;

        // Save geometry before tiling
        if (!window._tilingThirdsRect) {
            const rect = window.get_frame_rect();
            window._tilingThirdsRect = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
        }

        if (window.maximized_horizontally || window.maximized_vertically)
            window.unmaximize(Meta.MaximizeFlags.BOTH);

        const workspace = window.get_workspace();
        const monitor = window.get_monitor();
        const area = workspace.get_work_area_for_monitor(monitor);
        const third = Math.round(area.width / 3);

        let x;
        if (name === 'tile-left-third')
            x = area.x;
        else if (name === 'tile-center-third')
            x = area.x + third;
        else
            x = area.x + area.width - third;

        window.move_resize_frame(false, x, area.y, third, area.height);
    }

    _restoreWindow() {
        const window = global.display.focus_window;
        if (!window || window.window_type !== Meta.WindowType.NORMAL)
            return;

        if (window._tilingThirdsRect) {
            const r = window._tilingThirdsRect;
            window.move_resize_frame(false, r.x, r.y, r.width, r.height);
            delete window._tilingThirdsRect;
        } else if (window.maximized_horizontally || window.maximized_vertically) {
            window.unmaximize(Meta.MaximizeFlags.BOTH);
        }
    }

    disable() {
        if (this._grabBeginId) {
            global.display.disconnect(this._grabBeginId);
            this._grabBeginId = 0;
        }

        for (const name of ['tile-left-third', 'tile-center-third', 'tile-right-third', 'restore-window'])
            Main.wm.removeKeybinding(name);
        this._settings = null;
    }
}
JSEOF

# GSettings schema
cat > "$SCHEMAS_DIR/org.gnome.shell.extensions.tiling-thirds.gschema.xml" << 'SCHEMAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <schema id="org.gnome.shell.extensions.tiling-thirds"
          path="/org/gnome/shell/extensions/tiling-thirds/">
    <key name="tile-left-third" type="as">
      <default><![CDATA[['<Super>Left']]]></default>
      <summary>Tile window to left third</summary>
    </key>
    <key name="tile-center-third" type="as">
      <default><![CDATA[['<Super>Up']]]></default>
      <summary>Tile window to center third</summary>
    </key>
    <key name="tile-right-third" type="as">
      <default><![CDATA[['<Super>Right']]]></default>
      <summary>Tile window to right third</summary>
    </key>
    <key name="restore-window" type="as">
      <default><![CDATA[['<Super>Down']]]></default>
      <summary>Restore window to pre-tiled size</summary>
    </key>
  </schema>
</schemalist>
SCHEMAEOF

# GSettings スキーマのコンパイル
glib-compile-schemas "$SCHEMAS_DIR"
ok "拡張をインストール: $EXT_DIR"

# ─── 3. デフォルトのキーバインドを解除 ───────────────────
info "デフォルトのタイリング/最大化キーバインドを解除中..."

# Mutter の Super+Left/Right (半分タイリング) を解除
if gsettings list-keys org.gnome.mutter.keybindings 2>/dev/null | grep -q toggle-tiled-left; then
    gsettings set org.gnome.mutter.keybindings toggle-tiled-left "[]"
    gsettings set org.gnome.mutter.keybindings toggle-tiled-right "[]"
    ok "Mutter タイリング (Super+Left/Right) を解除"
fi

# WM の最大化キーバインドを解除
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "[]"
gsettings set org.gnome.desktop.wm.keybindings maximize "[]"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "[]"
ok "最大化/復元 (Super+Up/Down) を解除"

# Ubuntu Tiling Assistant 拡張の競合キーバインドを解除
if gsettings list-schemas | grep -q org.gnome.shell.extensions.tiling-assistant; then
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-left-half "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-right-half "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-maximize "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant restore-window "[]"
    ok "Tiling Assistant の競合キーバインド (Super+Left/Right/Up/Down) を解除"
fi

# ─── 4. 拡張の有効化 ─────────────────────────────────────
gnome-extensions enable "$EXT_UUID" 2>/dev/null || true
ok "拡張を有効化: $EXT_UUID"

# ─── 完了 ─────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "1/3 タイリングのセットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "キーバインド:"
info "  Super+Left  → 画面の左 1/3"
info "  Super+Up    → 画面の中央 1/3"
info "  Super+Right → 画面の右 1/3"
info "  Super+Down  → 元のサイズに復元"
info "  ドラッグ移動 → 自動で元のサイズに復元"
echo ""
info "反映するには GNOME Shell を再起動してください:"
info "  X11:    Alt+F2 → r → Enter"
info "  Wayland: ログアウト → ログイン"
