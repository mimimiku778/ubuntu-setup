#!/bin/bash
# setup-fingerprint-auth.sh
#
# sudo / polkit (GUI認証ダイアログ・ソフトウェアインストール) で指紋認証を有効にする。
#
# Usage:
#   sudo bash setup-fingerprint-auth.sh
#
# What it does:
#   1. /etc/pam.d/sudo に pam_fprintd.so を追加 (sudo で指紋認証)
#   2. /etc/pam.d/sudo-i に pam_fprintd.so を追加
#   3. /etc/pam.d/polkit-1 に pam_fprintd.so を追加 (GUI認証ダイアログ・ソフトウェアインストールで指紋認証)
#
# Requirements:
#   - root 権限 (sudo)
#   - fprintd / libpam-fprintd がインストール済み
#   - 指紋が登録済み (fprintd-enroll)

set -euo pipefail

MARKER="# Added by setup-fingerprint-auth.sh"
FPRINTD_LINE="auth    sufficient    pam_fprintd.so max-tries=1 timeout=10"
PAM_MODULE="/usr/lib/x86_64-linux-gnu/security/pam_fprintd.so"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── root チェック ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 で実行してください。"
fi

# ─── 前提条件チェック ─────────────────────────────────────
if ! command -v fprintd-list &>/dev/null; then
    error "fprintd がインストールされていません。apt install fprintd libpam-fprintd を実行してください。"
fi

if [[ ! -f "$PAM_MODULE" ]]; then
    error "pam_fprintd.so が見つかりません。apt install libpam-fprintd を実行してください。"
fi

CURRENT_USER="${SUDO_USER:-$USER}"
if ! fprintd-list "$CURRENT_USER" 2>/dev/null | grep -q "finger"; then
    warn "ユーザー $CURRENT_USER の指紋が登録されていません。fprintd-enroll で登録してください。"
    warn "スクリプトは続行しますが、指紋認証は指紋登録後に機能します。"
fi

ok "前提条件チェック完了"

# ─── PAM設定関数 ──────────────────────────────────────────
configure_pam_file() {
    local pam_file="$1"
    local description="$2"

    if [[ ! -f "$pam_file" ]]; then
        error "$pam_file が見つかりません"
    fi

    # 冪等性チェック
    if grep -qF "$MARKER" "$pam_file"; then
        skip "$description: $pam_file は設定済み"
        return 0
    fi

    # @include common-auth の存在確認
    if ! grep -q '^@include common-auth' "$pam_file"; then
        error "$pam_file に @include common-auth が見つかりません"
    fi

    # タイムスタンプ付きバックアップ
    local backup="${pam_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$pam_file" "$backup"
    info "バックアップ作成: $backup"

    # @include common-auth の前に指紋認証を挿入
    sed -i "/@include common-auth/i\\${MARKER}\n${FPRINTD_LINE}" "$pam_file"

    ok "$description: $pam_file に指紋認証を追加"
}

# ─── 1. sudo の設定 ───────────────────────────────────────
configure_pam_file "/etc/pam.d/sudo" "sudo"

# ─── 2. sudo -i の設定 ───────────────────────────────────
configure_pam_file "/etc/pam.d/sudo-i" "sudo -i"

# ─── 3. polkit の設定 (GUI認証ダイアログ・ソフトウェアインストール) ─
POLKIT_ETC="/etc/pam.d/polkit-1"
POLKIT_VENDOR="/usr/lib/pam.d/polkit-1"

if [[ -f "$POLKIT_ETC" ]]; then
    configure_pam_file "$POLKIT_ETC" "polkit"
elif [[ -f "$POLKIT_VENDOR" ]]; then
    cp "$POLKIT_VENDOR" "$POLKIT_ETC"
    info "$POLKIT_VENDOR を $POLKIT_ETC にコピー"
    configure_pam_file "$POLKIT_ETC" "polkit"
else
    warn "polkit-1 の PAM 設定ファイルが見つかりません。polkit の指紋認証はスキップします。"
fi

# ─── 4. 検証 ──────────────────────────────────────────────
info "設定を検証中..."

verify_ok=true
for pam_file in /etc/pam.d/sudo /etc/pam.d/sudo-i /etc/pam.d/polkit-1; do
    if [[ ! -f "$pam_file" ]]; then
        continue
    fi
    if grep -q "pam_fprintd.so" "$pam_file"; then
        ok "$(basename "$pam_file"): pam_fprintd.so が設定されています"
    else
        warn "$(basename "$pam_file"): pam_fprintd.so が見つかりません"
        verify_ok=false
    fi
done

# ─── 5. 完了 ──────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "指紋認証のセットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "有効化された機能:"
info "  - sudo コマンドで指紋認証"
info "  - GUI 認証ダイアログ (polkit) で指紋認証"
info "  - ソフトウェアインストール時の認証で指紋認証"
echo ""
info "使い方:"
info "  sudo を実行すると指紋センサーが光ります。"
info "  指紋をスキャンするか、従来通りパスワードを入力できます。"
info "  指紋認証がタイムアウト(10秒)すると、パスワード入力に切り替わります。"
echo ""
warn "GNOME Keyring について:"
warn "  指紋認証ではパスワードが提供されないため、GNOME Keyring は"
warn "  自動的にアンロックされません。セッション開始後、最初にキーリングを"
warn "  使用するアプリ (Chrome等) でパスワード入力が必要になります。"
warn "  キーリングを自動アンロックしたい場合は、Seahorse (パスワードと鍵)"
warn "  で「ログイン」キーリングのパスワードを空に設定してください。"
echo ""
info "元に戻す場合:"
info "  sudo sed -i '/$MARKER/d;/pam_fprintd.so.*max-tries/d' /etc/pam.d/sudo /etc/pam.d/sudo-i"
info "  sudo rm -f /etc/pam.d/polkit-1"
