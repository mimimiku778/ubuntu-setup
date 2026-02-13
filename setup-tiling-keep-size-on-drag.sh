#!/bin/bash
# setup-tiling-keep-size-on-drag.sh
#
# タイリングや縦方向最大化したウィンドウをドラッグしたとき、
# 元のサイズに戻さず現在のサイズを維持するようにする。
#
# Usage:
#   bash setup-tiling-keep-size-on-drag.sh
#
# What it does:
#   tiling-assistant 拡張の moveHandler.js をパッチして、
#   _restoreSizeAndRestartGrab() 内の Twm.untile() (元サイズ復元) を
#   現在のサイズを維持したまま状態クリアする処理に置き換える。
#
# 対象の挙動:
#   - Super+F で縦方向最大化 → ドラッグしてもサイズ維持
#   - 左右エッジタイリング → ドラッグしてもサイズ維持
#
# Requirements:
#   - sudo 権限
#   - tiling-assistant 拡張がインストール済み
#   - GNOME Shell 再起動 (X11: Alt+F2 → r, Wayland: ログアウト→ログイン)

set -euo pipefail

MOVE_HANDLER="/usr/share/gnome-shell/extensions/tiling-assistant@ubuntu.com/src/extension/moveHandler.js"

if [ ! -f "$MOVE_HANDLER" ]; then
    echo "[ERROR] moveHandler.js が見つかりません: $MOVE_HANDLER"
    exit 1
fi

# パッチ済みかチェック
if grep -q 'Keep current size instead of restoring pre-tile size' "$MOVE_HANDLER"; then
    echo "[SKIP] moveHandler.js は既にパッチ済み"
    exit 0
fi

# バックアップ作成
BACKUP="${MOVE_HANDLER}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp "$MOVE_HANDLER" "$BACKUP"
echo "[OK] バックアップ作成: $BACKUP"

# _restoreSizeAndRestartGrab メソッドをパッチ
# 元のコード:
#   Twm.untile(window, { restoreFullPos: false, skipAnim: this._wasMaximizedOnStart });
#   this._onMoveStarted(window, grabOp);
# ↓ 置換後: 現在のサイズを維持したまま tiled/maximized 状態をクリア
sudo sed -i '/_restoreSizeAndRestartGrab(window, grabOp) {/,/^    }/c\
    _restoreSizeAndRestartGrab(window, grabOp) {\
        // Keep current size instead of restoring pre-tile size\
        const currRect = new Rect(window.get_frame_rect());\
\
        // Clear maximized state without restoring size\
        if (window.maximizedHorizontally || window.maximizedVertically) {\
            if (window.get_maximized)\
                window.unmaximize(window.get_maximized());\
            else\
                window.unmaximize();\
        }\
\
        // Clear window constraints\
        if (window.override_constraints) {\
            window.override_constraints(Meta.WindowConstraint.NONE,\
                Meta.WindowConstraint.NONE, Meta.WindowConstraint.NONE,\
                Meta.WindowConstraint.NONE);\
        }\
\
        // Clear tiling state\
        if (window.tiledRect) {\
            Twm.clearTilingProps(window.get_id());\
            window.isTiled = false;\
            window.tiledRect = null;\
            window.untiledRect = null;\
            Twm.deleteTilingState(window);\
        }\
\
        // Force window to keep its current size\
        window.move_resize_frame(true, currRect.x, currRect.y, currRect.width, currRect.height);\
\
        this._onMoveStarted(window, grabOp);\
    }' "$MOVE_HANDLER"

# パッチが正しく適用されたか検証
if grep -q 'Keep current size instead of restoring pre-tile size' "$MOVE_HANDLER"; then
    echo "[OK] moveHandler.js をパッチ適用"
else
    echo "[ERROR] パッチ適用に失敗。バックアップから復元します"
    sudo cp "$BACKUP" "$MOVE_HANDLER"
    exit 1
fi

echo ""
echo "[OK] パッチ完了"
echo "[INFO] GNOME Shell を再起動してください:"
echo "  X11:    Alt+F2 → r → Enter"
echo "  Wayland: ログアウト → ログイン"
