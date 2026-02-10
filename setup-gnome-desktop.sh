#!/bin/bash
# setup-gnome-desktop.sh
#
# gnome-tweaks をインストールし、GNOME デスクトップの各種設定を行う。
#
# Usage:
#   bash setup-gnome-desktop.sh
#
# What it does:
#   1. gnome-tweaks をインストール (未インストールの場合)
#   2. キーボードのリピート速度と長押し判定時間を設定
#   3. ショートカットキーの設定
#   4. Dock の設定
#   5. インターフェースの設定
#   6. デスクトップアイコンの設定
#
# Requirements:
#   - sudo 権限 (パッケージインストール時)

set -euo pipefail

# --- 1. gnome-tweaks のインストール ---
if dpkg -s gnome-tweaks &>/dev/null; then
    echo "[SKIP] gnome-tweaks は既にインストール済み"
else
    echo "[INFO] gnome-tweaks をインストール中..."
    sudo apt-get update -qq
    sudo apt-get install -y gnome-tweaks
    echo "[OK] gnome-tweaks をインストール"
fi

# --- 2. キーボードのリピート速度と長押し判定時間を設定 ---
REPEAT_INTERVAL=16   # リピート間隔 (ms) — 小さいほど速い
DELAY=232             # 長押し判定時間 (ms) — キーを押してからリピートが始まるまでの時間

current_interval=$(gsettings get org.gnome.desktop.peripherals.keyboard repeat-interval)
current_delay=$(gsettings get org.gnome.desktop.peripherals.keyboard delay)

if [[ "$current_interval" == "uint32 $REPEAT_INTERVAL" && "$current_delay" == "uint32 $DELAY" ]]; then
    echo "[SKIP] キーボードのリピート設定は既に適用済み (repeat-interval=${REPEAT_INTERVAL}ms, delay=${DELAY}ms)"
else
    gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval "$REPEAT_INTERVAL"
    gsettings set org.gnome.desktop.peripherals.keyboard delay "$DELAY"
    echo "[OK] キーボードのリピート設定を適用 (repeat-interval=${REPEAT_INTERVAL}ms, delay=${DELAY}ms)"
fi

# --- 3. ショートカットキーの設定 ---
echo ""
echo "[INFO] ショートカットキーを設定中..."

# ウィンドウ管理キーバインド
gsettings set org.gnome.desktop.wm.keybindings maximize-vertically "['<Super>f']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>Down']"

# Super+Left/Right/Up は tiling-thirds 拡張で 1/3 タイリングに使用するため解除
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "[]"
gsettings set org.gnome.desktop.wm.keybindings maximize "[]"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "[]"
gsettings set org.gnome.mutter.keybindings toggle-tiled-left "[]" 2>/dev/null || true
gsettings set org.gnome.mutter.keybindings toggle-tiled-right "[]" 2>/dev/null || true

# Ubuntu Tiling Assistant の競合キーバインドを解除
if gsettings list-schemas | grep -q org.gnome.shell.extensions.tiling-assistant; then
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-left-half "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-right-half "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant tile-maximize "[]"
    gsettings set org.gnome.shell.extensions.tiling-assistant restore-window "[]"
fi

# Alt+Tab でウィンドウ単位の切り替え (アプリ単位ではなく)
gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"

# メディアキー
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['<Super>t']"

# Shell キーバインド
gsettings set org.gnome.shell.keybindings toggle-message-tray "[]"
gsettings set org.gnome.shell.keybindings screenshot "['<Shift>Print']"
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print']"
gsettings set org.gnome.shell.keybindings show-screen-recording-ui "['<Ctrl><Shift><Alt>R']"

echo "[OK] ショートカットキーを設定"

# --- 4. Dock の設定 ---
echo ""
echo "[INFO] Dock を設定中..."

gsettings set org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces true
gsettings set org.gnome.shell.extensions.dash-to-dock click-action "'focus-minimize-or-previews'"
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 52
gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false
gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false
gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-at-top false
gsettings set org.gnome.shell.extensions.dash-to-dock show-windows-preview true
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.80000000000000004

echo "[OK] Dock を設定"

# --- Dock サムネイルプレビューのパッチ ---
# サムネイルクリック時にプレビューを閉じず、フォーカス/最小化をトグルする
PREVIEW_JS="/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/windowPreview.js"
if [ -f "$PREVIEW_JS" ]; then
    if grep -q 'this._getTopMenu().close()' "$PREVIEW_JS"; then
        sudo sed -i '/        Main.activateWindow(this._window);/{
N
s|        Main.activateWindow(this._window);\n        this._getTopMenu().close();|        if (this._window.has_focus()) {\n            this._window.minimize();\n        } else {\n            Main.activateWindow(this._window);\n        }|
}' "$PREVIEW_JS"
        echo "[OK] Dock サムネイルプレビューをパッチ適用"
    else
        echo "[SKIP] Dock サムネイルプレビューは既にパッチ済み"
    fi
fi

# --- 5. インターフェースの設定 ---
echo ""
echo "[INFO] インターフェースを設定中..."

# カーソルサイズ (デフォルト24 → 32)
gsettings set org.gnome.desktop.interface cursor-size 32

# 中クリック貼り付けを無効化
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false

echo "[OK] インターフェースを設定"

# --- 6. デスクトップアイコンの設定 ---
echo ""
echo "[INFO] デスクトップアイコンを設定中..."

gsettings set org.gnome.shell.extensions.ding show-home false

echo "[OK] デスクトップアイコンを設定"

# --- 完了 ---
echo ""
echo "[OK] GNOME デスクトップのセットアップが完了しました"
