#!/usr/bin/env bash
# setup.sh — libscroll-speed のビルド＆インストール
#
# macOS ライクな非線形タッチパッドスクロールを実現する
# LD_PRELOAD interposer をインストールします。
#
# - 遅いスクロール: 55% 感度 (精密操作、VSCode等で快適)
# - 速いフリック:   ソフトキャップ → 慣性スクロールの暴走を防止
#
# 既存の libinput-config (線形 scroll-factor) を置き換えます。
# 設定: /etc/scroll-speed.conf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="/usr/local/lib/x86_64-linux-gnu"
PRELOAD="/etc/ld.so.preload"
TARGET="libscroll-speed.so"
CONF_DEST="/etc/scroll-speed.conf"
OLD_CONF="/etc/libinput.conf"

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ── 依存チェック ──────────────────────────────────
check_deps() {
    local missing=()
    command -v gcc   &>/dev/null || missing+=(gcc)
    dpkg -s libinput-dev &>/dev/null 2>&1 || missing+=(libinput-dev)

    if [[ ${#missing[@]} -gt 0 ]]; then
        info "依存パッケージをインストール: ${missing[*]}"
        sudo apt update -qq
        sudo apt install -y "${missing[@]}"
    fi
}

# ── ビルド ────────────────────────────────────────
build() {
    info "ビルド中..."
    cd "$SCRIPT_DIR"
    make clean
    make
    ok "ビルド完了: $TARGET"
}

# ── インストール ──────────────────────────────────
install_lib() {
    info "インストール中..."

    # ライブラリ配置 (アトミック置換: mmap中のプロセスに影響しない)
    sudo cp "$SCRIPT_DIR/$TARGET" "$LIB_DIR/$TARGET.tmp"
    sudo chmod 644 "$LIB_DIR/$TARGET.tmp"
    sudo mv "$LIB_DIR/$TARGET.tmp" "$LIB_DIR/$TARGET"
    ok "ライブラリ → $LIB_DIR/$TARGET (atomic replace)"

    # ld.so.preload: 古い libinput-config を除去
    if grep -q 'libinput-config' "$PRELOAD" 2>/dev/null; then
        warn "libinput-config を ld.so.preload から除去"
        sudo sed -i '/libinput-config/d' "$PRELOAD"
    fi

    # ld.so.preload: libscroll-speed を追加
    if ! grep -q 'libscroll-speed' "$PRELOAD" 2>/dev/null; then
        echo "$LIB_DIR/$TARGET" | sudo tee -a "$PRELOAD" > /dev/null
        ok "ld.so.preload に追加"
    else
        ok "ld.so.preload に既に登録済み"
    fi

    # 設定ファイル
    if [[ ! -f "$CONF_DEST" ]]; then
        sudo install -m 644 "$SCRIPT_DIR/scroll-speed.conf" "$CONF_DEST"
        ok "デフォルト設定 → $CONF_DEST"
    else
        ok "$CONF_DEST は既存のため保持"
    fi

    # 古い libinput.conf を無効化 (バックアップ)
    if [[ -f "$OLD_CONF" ]]; then
        warn "旧 $OLD_CONF をバックアップ (libscroll-speed が置き換えます)"
        sudo mv "$OLD_CONF" "${OLD_CONF}.bak.$(date +%s)"
    fi
}

# ── メイン ────────────────────────────────────────
main() {
    echo ""
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m  libscroll-speed — macOS ライクスクロール\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    info "非線形スクロールカーブ:"
    echo "  遅いスクロール → 55% 感度 (精密、VSCode でも快適)"
    echo "  速いフリック   → ソフトキャップ (慣性暴走を防止)"
    echo "  最大出力       → 8.25 (base-speed × scroll-cap)"
    echo ""

    check_deps
    build
    install_lib

    echo ""
    ok "インストール完了"
    warn "反映にはログアウト→再ログインが必要です"
    echo ""
    info "設定の調整:"
    echo "  sudo nano $CONF_DEST"
    echo ""
    info "アンインストール:"
    echo "  cd $SCRIPT_DIR && make uninstall"
    echo ""
}

main "$@"
