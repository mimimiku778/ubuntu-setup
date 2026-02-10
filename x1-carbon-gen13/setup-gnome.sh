#!/bin/bash
# setup-gnome.sh
#
# GNOME デスクトップ環境の各種設定を行う。
#
# Usage:
#   bash setup-gnome.sh
#
# What it does:
#   1. gnome-tweaks をインストール (未インストールの場合)
#   2. ショートカットキーの設定
#   3. Dock の設定
#   4. インターフェースの設定
#   5. デスクトップアイコンの設定
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

# --- 2. ショートカットキーの設定 ---
echo ""
echo "[INFO] ショートカットキーを設定中..."

# ウィンドウ管理キーバインド
gsettings set org.gnome.desktop.wm.keybindings maximize-vertically "['<Super>f']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>Down']"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>Up']"

# Alt+Tab でウィンドウ単位の切り替え (アプリ単位ではなく)
gsettings set org.gnome.desktop.wm.keybindings switch-applications "['<Super>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"

# メディアキー
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['<Super>t']"

# Shell キーバインド
gsettings set org.gnome.shell.keybindings toggle-message-tray "[]"
gsettings set org.gnome.shell.keybindings screenshot "['Print']"
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Launch5']"
gsettings set org.gnome.shell.keybindings show-screen-recording-ui "['<Alt>Launch5']"

echo "[OK] ショートカットキーを設定"

# --- 3. Dock の設定 ---
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

# --- 4. インターフェースの設定 ---
echo ""
echo "[INFO] インターフェースを設定中..."

# カーソルサイズ (デフォルト24 → 32)
gsettings set org.gnome.desktop.interface cursor-size 32

# 中クリック貼り付けを無効化
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste false

echo "[OK] インターフェースを設定"

# --- 5. デスクトップアイコンの設定 ---
echo ""
echo "[INFO] デスクトップアイコンを設定中..."

gsettings set org.gnome.shell.extensions.ding show-home false

echo "[OK] デスクトップアイコンを設定"

# --- 完了 ---
echo ""
echo "[OK] GNOME のセットアップが完了しました"
