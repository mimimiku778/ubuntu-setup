#!/bin/bash
# allow-short-password.sh
#
# パスワードポリシーを緩和し、4桁の数字パスワードなど短いパスワードを許可する。
#
# Usage:
#   sudo bash allow-short-password.sh
#
# What it does:
#   1. /etc/security/pwquality.conf に短いパスワードを許可する設定を追記
#   2. /etc/pam.d/common-password から pam_pwquality.so を無効化
#   3. pam_unix.so に minlen=4 を設定し obscure チェックを除去
#
# Requirements:
#   - root 権限 (sudo)

set -euo pipefail

# --- root チェック ---
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] root 権限が必要です。sudo bash $0 で実行してください。" >&2
    exit 1
fi

PWQUALITY_CONF="/etc/security/pwquality.conf"
COMMON_PASSWORD="/etc/pam.d/common-password"
MARKER="# Added by allow-short-password.sh"

# --- 1. pwquality.conf に短いパスワード許可設定を追記 ---
if grep -qF "$MARKER" "$PWQUALITY_CONF" 2>/dev/null; then
    echo "[SKIP] $PWQUALITY_CONF は設定済み"
else
    cat >> "$PWQUALITY_CONF" << EOF

$MARKER
minlen = 4
minclass = 0
dcredit = 0
ucredit = 0
lcredit = 0
ocredit = 0
dictcheck = 0
usercheck = 0
enforcing = 1
EOF
    echo "[OK] $PWQUALITY_CONF に短いパスワード許可設定を追記"
fi

# --- 2. pam_pwquality.so を無効化 ---
if grep -q '^#.*pam_pwquality.so' "$COMMON_PASSWORD"; then
    echo "[SKIP] pam_pwquality.so は既に無効化済み"
elif grep -q '^password.*pam_pwquality.so' "$COMMON_PASSWORD"; then
    sed -i 's/^password\(.*\)pam_pwquality.so/#password\1pam_pwquality.so/' "$COMMON_PASSWORD"
    echo "[OK] pam_pwquality.so を無効化"
else
    echo "[SKIP] pam_pwquality.so の行が見つかりません"
fi

# --- 3. pam_unix.so から obscure を除去 ---
if grep -q 'pam_unix.so.*obscure' "$COMMON_PASSWORD"; then
    sed -i 's/\bobscure\b//' "$COMMON_PASSWORD"
    echo "[OK] pam_unix.so から obscure を除去"
else
    echo "[SKIP] obscure は既に除去済み"
fi

# --- 4. pam_unix.so に minlen=4 を設定 ---
if grep -q 'pam_unix.so.*minlen=' "$COMMON_PASSWORD"; then
    echo "[SKIP] pam_unix.so に minlen は既に設定済み"
elif grep -q 'pam_unix.so' "$COMMON_PASSWORD"; then
    sed -i '/^password.*pam_unix.so/ s/pam_unix.so/pam_unix.so minlen=4/' "$COMMON_PASSWORD"
    echo "[OK] pam_unix.so に minlen=4 を設定"
else
    echo "[ERROR] pam_unix.so の行が見つかりません" >&2
    exit 1
fi

# --- 5. pam_unix.so から use_authtok を除去 (pam_pwquality 無効化に伴い不要) ---
if grep -q 'pam_unix.so.*use_authtok' "$COMMON_PASSWORD"; then
    sed -i 's/\buse_authtok\b//' "$COMMON_PASSWORD"
    # 連続スペースを整理
    sed -i '/pam_unix.so/s/  */ /g' "$COMMON_PASSWORD"
    echo "[OK] pam_unix.so から use_authtok を除去"
else
    echo "[SKIP] use_authtok は既に除去済み"
fi

# --- 完了 ---
echo ""
echo "[OK] パスワードポリシーの変更が完了しました"
echo "     passwd コマンドで4桁の数字パスワードを設定できます"
