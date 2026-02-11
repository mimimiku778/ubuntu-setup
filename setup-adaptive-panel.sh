#!/usr/bin/env bash
# setup-adaptive-panel.sh
#
# OLED 焼付き防止: パネル色をダーク/ライトモード・最大化ウィンドウに
# 応じて動的に変更する GNOME Shell 拡張をインストールする。
#
# Usage:
#   bash setup-adaptive-panel.sh             # インストール
#   bash setup-adaptive-panel.sh --uninstall # アンインストール
#
# What it does:
#   1. GNOME Shell バージョンを確認 (49+)
#   2. カスタム GNOME Shell 拡張 (adaptive-panel) をインストール
#   3. 拡張を有効化
#
# Features:
#   - ライトモード時: 明るい背景 + 暗い文字/アイコン
#   - ダークモード時: 暗い背景 + 明るい文字/アイコン
#   - 最大化ウィンドウ時: ヘッダーバーの色にパネルを同期
#   - 文字/アイコン色は背景の明暗で自動切替
#
# Requirements:
#   - GNOME Shell 49+

set -euo pipefail

EXT_UUID="adaptive-panel@ubuntu-setup"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# ─── アンインストール ─────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    info "adaptive-panel 拡張をアンインストール中..."
    gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
    rm -rf "$EXT_DIR"
    ok "拡張を削除: $EXT_DIR"
    echo ""
    info "反映するには GNOME Shell を再起動してください:"
    info "  Wayland: ログアウト → ログイン"
    exit 0
fi

# ─── 1. GNOME Shell バージョン確認 ───────────────────────
if ! command -v gnome-shell &>/dev/null; then
    error "GNOME Shell が見つかりません。GNOME デスクトップ環境で実行してください。"
fi

GNOME_VER=$(gnome-shell --version | grep -oP '[0-9]+' | head -1)
info "GNOME Shell $GNOME_VER を検出"

if (( GNOME_VER < 49 )); then
    error "GNOME Shell 49 以上が必要です (現在: $GNOME_VER)"
fi

# ─── 2. 拡張のインストール ───────────────────────────────
if [ -d "$EXT_DIR" ]; then
    info "既存の拡張を更新中..."
else
    info "拡張をインストール中..."
fi

mkdir -p "$EXT_DIR"

# metadata.json
cat > "$EXT_DIR/metadata.json" << METAEOF
{
    "name": "Adaptive Panel",
    "description": "OLED burn-in protection: panel color adapts to dark/light mode and maximized window header",
    "uuid": "$EXT_UUID",
    "shell-version": ["$GNOME_VER"]
}
METAEOF

# extension.js
cat > "$EXT_DIR/extension.js" << 'JSEOF'
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Shell from 'gi://Shell';
import Meta from 'gi://Meta';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

Gio._promisify(Shell.Screenshot.prototype, 'pick_color', 'pick_color_finish');

export default class AdaptivePanelExtension extends Extension {
    enable() {
        this._signals = [];
        this._windowSignals = new Map();
        this._debounceId = 0;
        this._generation = 0;

        this._ifaceSettings = new Gio.Settings({
            schema_id: 'org.gnome.desktop.interface',
        });

        this._connectTo(this._ifaceSettings, 'changed::color-scheme',
            () => this._scheduleUpdate());
        this._connectTo(global.display, 'notify::focus-window',
            () => this._onFocusChanged());
        this._connectTo(global.display, 'window-created',
            (_d, w) => this._trackWindow(w));
        this._connectTo(global.workspace_manager, 'active-workspace-changed',
            () => this._scheduleUpdate());
        this._connectTo(Main.overview, 'showing',
            () => this._scheduleUpdate());
        this._connectTo(Main.overview, 'hiding',
            () => this._scheduleUpdate());

        for (const a of global.get_window_actors())
            this._trackWindow(a.meta_window);

        this._scheduleUpdate();
    }

    _connectTo(obj, signal, handler) {
        const id = obj.connect(signal, handler);
        this._signals.push({obj, id});
    }

    _trackWindow(window) {
        if (this._windowSignals.has(window))
            return;
        const ids = [
            window.connect('notify::maximized-horizontally',
                () => this._scheduleUpdate()),
            window.connect('notify::maximized-vertically',
                () => this._scheduleUpdate()),
            window.connect('size-changed',
                () => this._scheduleUpdate()),
            window.connect('unmanaging', () => {
                this._untrackWindow(window);
                this._scheduleUpdate();
            }),
        ];
        this._windowSignals.set(window, ids);
    }

    _untrackWindow(window) {
        const ids = this._windowSignals.get(window);
        if (!ids) return;
        for (const id of ids)
            window.disconnect(id);
        this._windowSignals.delete(window);
    }

    _onFocusChanged() {
        const w = global.display.focus_window;
        if (w) this._trackWindow(w);
        this._scheduleUpdate();
    }

    _scheduleUpdate() {
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        this._debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            this._debounceId = 0;
            this._updatePanel();
            return GLib.SOURCE_REMOVE;
        });
    }

    async _updatePanel() {
        const gen = ++this._generation;

        // Overview / lock screen → theme-based color
        if (Main.overview.visible ||
            Main.sessionMode.currentMode === 'unlock-dialog' ||
            Main.sessionMode.currentMode === 'lock-screen') {
            this._applyThemeColor();
            return;
        }

        // Maximized window on primary monitor → pick its header bar color
        const maxWin = this._findMaximizedWindow();
        if (maxWin)
            await this._pickAndApply(gen);
        else
            this._applyThemeColor();
    }

    _findMaximizedWindow() {
        const pri = Main.layoutManager.primaryIndex;
        return global.get_window_actors()
            .map(a => a.meta_window)
            .filter(w =>
                w.get_monitor() === pri &&
                !w.minimized &&
                w.window_type === Meta.WindowType.NORMAL &&
                w.maximized_horizontally && w.maximized_vertically)
            .at(-1) ?? null;
    }

    async _pickAndApply(gen) {
        try {
            const screenshot = new Shell.Screenshot();
            const panelH = Main.panel.get_height();
            const mon = Main.layoutManager.primaryMonitor;
            // Sample just below the panel, inside the header bar
            const y = mon.y + panelH + 5;

            const colors = [];
            for (const frac of [0.25, 0.50, 0.75]) {
                if (gen !== this._generation) return;
                const x = mon.x + Math.round(mon.width * frac);
                const [color] = await screenshot.pick_color(x, y);
                colors.push({
                    r: Math.round(color.get_red() * 255),
                    g: Math.round(color.get_green() * 255),
                    b: Math.round(color.get_blue() * 255),
                });
            }

            if (gen !== this._generation) return;

            // Use median by luminance to avoid outliers (e.g. a button)
            colors.sort((a, b) => this._lum(a) - this._lum(b));
            const {r, g, b} = colors[1];
            this._applyColor(r, g, b);
        } catch (e) {
            this._applyThemeColor();
        }
    }

    _lum({r, g, b}) {
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    _applyThemeColor() {
        const isDark =
            this._ifaceSettings.get_string('color-scheme') === 'prefer-dark';
        if (isDark)
            this._applyColor(0x13, 0x13, 0x13);
        else
            this._applyColor(0xFA, 0xFA, 0xFA);
    }

    _applyColor(r, g, b) {
        const light = this._lum({r, g, b}) > 128;
        const fg = light ? '#3D3D3D' : '#f2f2f2';

        // Panel background + text color with smooth transition
        Main.panel.set_style(
            `background-color: rgb(${r},${g},${b}); ` +
            `color: ${fg}; ` +
            `transition-duration: 350ms;`
        );

        // Toggle style class for hover/active styling in stylesheet.css
        if (light) {
            Main.panel.remove_style_class_name('adaptive-panel-dark');
            Main.panel.add_style_class_name('adaptive-panel-light');
        } else {
            Main.panel.remove_style_class_name('adaptive-panel-light');
            Main.panel.add_style_class_name('adaptive-panel-dark');
        }

        // Apply foreground color to panel buttons (overrides theme color)
        for (const box of [Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox]) {
            if (!box) continue;
            for (const child of box.get_children())
                child.set_style(`color: ${fg};`);
        }
    }

    _resetStyle() {
        Main.panel.set_style(null);
        Main.panel.remove_style_class_name('adaptive-panel-light');
        Main.panel.remove_style_class_name('adaptive-panel-dark');
        for (const box of [Main.panel._leftBox, Main.panel._centerBox, Main.panel._rightBox]) {
            if (!box) continue;
            for (const child of box.get_children())
                child.set_style(null);
        }
    }

    disable() {
        if (this._debounceId) {
            GLib.source_remove(this._debounceId);
            this._debounceId = 0;
        }

        this._resetStyle();

        for (const {obj, id} of this._signals)
            obj.disconnect(id);
        this._signals = [];

        for (const [w, ids] of this._windowSignals) {
            for (const id of ids) {
                try { w.disconnect(id); } catch (e) { /* window already gone */ }
            }
        }
        this._windowSignals.clear();

        this._ifaceSettings = null;
    }
}
JSEOF

# stylesheet.css
cat > "$EXT_DIR/stylesheet.css" << 'CSSEOF'
/* ─── Light panel: dark text/icons ─── */

.adaptive-panel-light .panel-button {
    color: #3D3D3D !important;
}
.adaptive-panel-light .panel-button:hover {
    background-color: rgba(61, 61, 61, 0.10) !important;
    color: #3D3D3D !important;
}
.adaptive-panel-light .panel-button:active,
.adaptive-panel-light .panel-button:checked {
    background-color: rgba(61, 61, 61, 0.18) !important;
    color: #3D3D3D !important;
}
.adaptive-panel-light .panel-button .clock {
    color: #3D3D3D !important;
}

/* ─── Dark panel: light text/icons ─── */

.adaptive-panel-dark .panel-button {
    color: #f2f2f2 !important;
}
.adaptive-panel-dark .panel-button:hover {
    background-color: rgba(242, 242, 242, 0.17) !important;
    color: #f2f2f2 !important;
}
.adaptive-panel-dark .panel-button:active,
.adaptive-panel-dark .panel-button:checked {
    background-color: rgba(242, 242, 242, 0.25) !important;
    color: #f2f2f2 !important;
}
.adaptive-panel-dark .panel-button .clock {
    color: #f2f2f2 !important;
}

/* ─── Workspace dots ─── */

.adaptive-panel-light .workspace-dot {
    background-color: rgba(61, 61, 61, 0.40) !important;
}
.adaptive-panel-light .workspace-dot.active {
    background-color: #3D3D3D !important;
}
.adaptive-panel-dark .workspace-dot {
    background-color: rgba(242, 242, 242, 0.40) !important;
}
.adaptive-panel-dark .workspace-dot.active {
    background-color: #f2f2f2 !important;
}
CSSEOF

ok "拡張をインストール: $EXT_DIR"

# ─── 3. 拡張の有効化 ─────────────────────────────────────
gnome-extensions enable "$EXT_UUID" 2>/dev/null || true
ok "拡張を有効化: $EXT_UUID"

# ─── 完了 ─────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "Adaptive Panel のセットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "機能:"
info "  - ライトモード → 明るいパネル + 暗い文字"
info "  - ダークモード → 暗いパネル + 明るい文字"
info "  - 最大化ウィンドウ → ヘッダーバーの色に同期"
echo ""
info "反映するには GNOME Shell を再起動してください:"
info "  Wayland: ログアウト → ログイン"
echo ""
info "アンインストール:"
info "  bash setup-adaptive-panel.sh --uninstall"
