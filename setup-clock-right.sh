#!/bin/bash
# setup-clock-right.sh
#
# GNOME トップバーの時計を最右端（システムトレイより右）に移動する。
# macOS / Windows のように画面の一番右に時計を表示する。
#
# Usage:
#   bash setup-clock-right.sh
#
# What it does:
#   1. 最小限の GNOME Shell 拡張をインストール
#   2. 拡張を有効化
#
# 反映にはログアウト→ログインが必要。

set -euo pipefail

EXTENSION_UUID="move-clock-right@custom"
EXTENSION_DIR="$HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID"

# --- 拡張機能のインストール ---
if [ -d "$EXTENSION_DIR" ]; then
    echo "[SKIP] 拡張 $EXTENSION_UUID は既にインストール済み"
else
    echo "[INFO] 拡張 $EXTENSION_UUID をインストール中..."

    # 一時ディレクトリでファイルを作成して zip → gnome-extensions install
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    # metadata.json
    cat > "$TMPDIR/metadata.json" << 'METADATA'
{
    "uuid": "move-clock-right@custom",
    "name": "Move Clock to Far Right",
    "description": "Moves the clock to the rightmost position on the top panel (after system indicators)",
    "shell-version": ["45", "46", "47", "48", "49"],
    "version": 1
}
METADATA

    # extension.js (ESM format for GNOME 45+)
    cat > "$TMPDIR/extension.js" << 'EXTJS'
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class MoveClockRightExtension extends Extension {
    enable() {
        this._dateMenu = Main.panel.statusArea.dateMenu;
        if (!this._dateMenu) return;

        const container = this._dateMenu.container;
        const parent = container.get_parent();
        if (parent) {
            parent.remove_child(container);
        }
        // _rightBox の末尾に追加 → システムトレイより右になる
        Main.panel._rightBox.add_child(container);
    }

    disable() {
        if (!this._dateMenu) return;

        const container = this._dateMenu.container;
        const parent = container.get_parent();
        if (parent) {
            parent.remove_child(container);
        }
        // 元の位置（中央）に戻す
        Main.panel._centerBox.add_child(container);
    }
}
EXTJS

    # zip にまとめて gnome-extensions install でインストール
    (cd "$TMPDIR" && zip -q extension.zip metadata.json extension.js)
    gnome-extensions install "$TMPDIR/extension.zip" --force

    echo "[OK] 拡張 $EXTENSION_UUID をインストール"
fi

# --- 拡張の有効化 ---
# GNOME Shell が拡張を認識していない場合（初回インストール直後）は
# enable が失敗する → ログアウト後に自動的に有効になるよう gsettings で直接設定
if gnome-extensions info "$EXTENSION_UUID" 2>/dev/null | grep -q "State: ENABLED"; then
    echo "[SKIP] 拡張 $EXTENSION_UUID は既に有効"
elif gnome-extensions enable "$EXTENSION_UUID" 2>/dev/null; then
    echo "[OK] 拡張 $EXTENSION_UUID を有効化"
else
    # gnome-extensions enable が失敗した場合、gsettings で直接有効化リストに追加
    CURRENT=$(gsettings get org.gnome.shell enabled-extensions)
    if echo "$CURRENT" | grep -q "$EXTENSION_UUID"; then
        echo "[SKIP] 拡張 $EXTENSION_UUID は有効化リストに登録済み"
    else
        # @as [] (空) の場合
        if [ "$CURRENT" = "@as []" ]; then
            gsettings set org.gnome.shell enabled-extensions "['$EXTENSION_UUID']"
        else
            # 既存リストの末尾に追加
            NEW=$(echo "$CURRENT" | sed "s/]$/, '$EXTENSION_UUID']/")
            gsettings set org.gnome.shell enabled-extensions "$NEW"
        fi
        echo "[OK] 拡張 $EXTENSION_UUID を有効化リストに追加"
    fi
fi

# --- multi-monitors-bar のパッチ（サブモニター対応）---
MM_PANEL="$HOME/.local/share/gnome-shell/extensions/multi-monitors-bar@frederykabryan/mmpanel.js"
if [ -f "$MM_PANEL" ]; then
    if grep -q '_ensureDateMenuRightmost' "$MM_PANEL"; then
        echo "[SKIP] multi-monitors-bar は既にパッチ済み（dateMenu 最右端）"
    else
        echo "[INFO] multi-monitors-bar にサブモニター用パッチを適用中..."

        # _updatePanel に _ensureDateMenuRightmost() 呼び出しを追加
        sed -i 's/this._ensureQuickSettingsRightmost();/this._ensureQuickSettingsRightmost();\n            this._ensureDateMenuRightmost();/' "$MM_PANEL"

        # _ensureDateMenuRightmost メソッドを export 文の直前に追加
        sed -i '/^export { StatusIndicatorsController/i\
// Ensure the dateMenu is placed at the absolute far right (after quickSettings)\
// This mirrors the behavior of move-clock-right@custom for secondary monitors\
MultiMonitorsPanel.prototype._ensureDateMenuRightmost = function () {\
    const role = '"'"'dateMenu'"'"';\
    const indicator = this.statusArea[role];\
    if (!indicator) return;\
\
    const container = indicator.container || indicator;\
    const rightChildren = this._rightBox.get_children();\
\
    // Already last? Skip\
    if (rightChildren.length > 0 && rightChildren[rightChildren.length - 1] === container) return;\
\
    const parent = container.get_parent();\
    if (parent) parent.remove_child(container);\
    this._rightBox.add_child(container);\
};\
' "$MM_PANEL"

        echo "[OK] multi-monitors-bar にパッチを適用"
    fi
else
    echo "[SKIP] multi-monitors-bar が見つからない（サブモニターパッチ不要）"
fi

echo ""
echo "[OK] 時計を最右端に移動する設定が完了しました"
echo "[INFO] 反映にはログアウト→ログインが必要です"
