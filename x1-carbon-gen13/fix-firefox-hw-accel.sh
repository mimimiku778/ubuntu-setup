#!/bin/bash
# fix-firefox-hw-accel.sh
#
# Firefox で YouTube 4K 動画などが重い問題を修正する。
# Snap 版 Firefox を Mozilla 公式 deb 版に置き換え、
# VA-API ハードウェアビデオデコードを有効にする。
#
# 問題:
#   Snap 版 Firefox は内蔵の古い iHD ドライバを使用するため、
#   Arrow Lake GPU で VA-API が動作せず、4K 動画が CPU ソフト
#   デコードになりカクつく。Chrome は自前の HW デコードパスを
#   持つため問題なし。
#
# Usage:
#   bash fix-firefox-hw-accel.sh [status|revert]
#
#   (引数なし)  Snap 版を削除し、deb 版をインストールし VA-API を設定
#   status      現在の設定を表示する
#   revert      deb 版を削除し Snap 版に戻す
#
# What it does:
#   1. intel-media-va-driver-non-free をインストール
#   2. Snap 版 Firefox を削除
#   3. Mozilla 公式 APT リポジトリを追加
#   4. deb 版 Firefox をインストール
#   5. MOZ_DISABLE_RDD_SANDBOX=1 を environment.d に設定
#
# Note:
#   設定後ログアウト/ログインが必要です（environment.d の反映のため）。
#   about:support の "Media" セクションで hardware decoding を確認できます。

set -euo pipefail

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
skip()  { echo -e "\033[1;36m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

MOZILLA_KEYRING="/etc/apt/keyrings/packages.mozilla.org.asc"
MOZILLA_LIST="/etc/apt/sources.list.d/mozilla.list"
MOZILLA_PIN="/etc/apt/preferences.d/mozilla"
ENV_FILE="$HOME/.config/environment.d/firefox-vaapi.conf"

# ─── ステータス表示 ───────────────────────────────────────
show_status() {
    info "Firefox バージョン:"
    if command -v firefox &>/dev/null; then
        echo "  $(firefox --version 2>&1)"
    else
        echo "  (未インストール)"
    fi

    echo ""
    info "インストール方式:"
    if snap list firefox &>/dev/null; then
        echo "  Snap 版"
    elif dpkg -s firefox &>/dev/null; then
        local origin
        origin=$(LANG=C apt-cache policy firefox 2>/dev/null | grep '\*\*\*' -A1 | tail -1 | xargs || echo "不明")
        echo "  deb 版 ($origin)"
    else
        echo "  (未インストール)"
    fi

    echo ""
    info "VA-API ドライバ:"
    if command -v vainfo &>/dev/null; then
        if vainfo 2>&1 | grep -q "vaInitialize failed"; then
            warn "VA-API 初期化失敗"
        else
            local driver
            driver=$(vainfo 2>&1 | grep "Driver version" || echo "不明")
            ok "$driver"
        fi
    else
        warn "vainfo 未インストール"
    fi

    echo ""
    info "intel-media-va-driver-non-free:"
    if dpkg -s intel-media-va-driver-non-free &>/dev/null 2>&1; then
        ok "インストール済み"
    else
        warn "未インストール"
    fi

    echo ""
    info "環境変数 (${ENV_FILE}):"
    if [[ -f "$ENV_FILE" ]]; then
        while IFS= read -r line; do
            echo "  $line"
        done < "$ENV_FILE"
    else
        echo "  (ファイルなし)"
    fi

    echo ""
    info "Firefox プロセスの確認:"
    if pgrep -x firefox &>/dev/null; then
        local pid
        pid=$(pgrep -x firefox -o)
        info "  PID: $pid"
        if tr '\0' '\n' < /proc/"$pid"/environ 2>/dev/null | grep -q "MOZ_DISABLE_RDD_SANDBOX=1"; then
            ok "  MOZ_DISABLE_RDD_SANDBOX=1 反映済み"
        else
            warn "  MOZ_DISABLE_RDD_SANDBOX=1 未反映 (ログアウト/ログインが必要)"
        fi
    else
        info "  Firefox は起動していません"
    fi
}

# ─── 元に戻す ─────────────────────────────────────────────
revert() {
    info "deb 版 Firefox を削除し Snap 版に戻します"

    # deb版Firefoxの削除
    if dpkg -s firefox &>/dev/null 2>&1; then
        sudo apt remove -y firefox
        ok "deb 版 Firefox を削除しました"
    fi

    # Mozillaリポジトリの削除
    if [[ -f "$MOZILLA_LIST" ]]; then
        sudo rm -f "$MOZILLA_LIST" "$MOZILLA_PIN"
        ok "Mozilla APT リポジトリを削除しました"
    fi

    # Snap版Firefoxのインストール
    if ! snap list firefox &>/dev/null 2>&1; then
        sudo snap install firefox
        ok "Snap 版 Firefox をインストールしました"
    fi

    # 環境変数ファイルの削除
    if [[ -f "$ENV_FILE" ]]; then
        rm "$ENV_FILE"
        ok "環境変数ファイルを削除しました: $ENV_FILE"
    fi

    echo ""
    ok "Snap 版に戻しました"
}

# ─── メイン ───────────────────────────────────────────────
ACTION="${1:-apply}"

case "$ACTION" in
    status)
        show_status
        exit 0
        ;;
    revert)
        revert
        exit 0
        ;;
    apply)
        ;;
    *)
        echo "Usage: bash $0 [status|revert]"
        exit 1
        ;;
esac

# ─── Step 1: VA-API ドライバのインストール ────────────────
info "━━━ Step 1/5: VA-API ドライバ ━━━"
if dpkg -s intel-media-va-driver-non-free &>/dev/null 2>&1; then
    skip "intel-media-va-driver-non-free は既にインストール済み"
else
    sudo apt install -y intel-media-va-driver-non-free
    ok "intel-media-va-driver-non-free をインストール"
fi

# vainfo もインストール（診断用）
if ! command -v vainfo &>/dev/null; then
    sudo apt install -y vainfo
    ok "vainfo をインストール"
fi

# VA-API 動作確認
if vainfo 2>&1 | grep -q "vaInitialize failed"; then
    error "VA-API が動作しません。GPU ドライバを確認してください"
fi
ok "VA-API 動作確認 OK"

# ─── Step 2: Snap 版 Firefox の削除 ──────────────────────
info "━━━ Step 2/5: Snap 版 Firefox の削除 ━━━"
if snap list firefox &>/dev/null 2>&1; then
    sudo snap remove firefox
    # スナップショットが残っている場合は削除
    local_snap_id=$(snap saved 2>&1 | grep firefox | awk '{print $1}' || true)
    if [[ -n "$local_snap_id" ]]; then
        sudo snap forget "$local_snap_id"
        ok "Snap スナップショットを削除"
    fi
    ok "Snap 版 Firefox を削除"
else
    skip "Snap 版 Firefox は既に削除済み"
fi

# ─── Step 3: Mozilla 公式 APT リポジトリ追加 ─────────────
info "━━━ Step 3/5: Mozilla APT リポジトリ ━━━"
if [[ -f "$MOZILLA_LIST" ]]; then
    skip "Mozilla APT リポジトリは既に追加済み"
else
    # 署名キー
    sudo install -d -m 0755 /etc/apt/keyrings
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
        | sudo tee "$MOZILLA_KEYRING" > /dev/null
    ok "署名キーを追加"

    # リポジトリ
    echo "deb [signed-by=${MOZILLA_KEYRING}] https://packages.mozilla.org/apt mozilla main" \
        | sudo tee "$MOZILLA_LIST" > /dev/null
    ok "リポジトリを追加"

    # ピン設定（Mozilla 版を優先）
    cat <<'PINEOF' | sudo tee "$MOZILLA_PIN" > /dev/null
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
PINEOF
    ok "ピン設定を追加"

    sudo apt update -qq
    ok "パッケージリストを更新"
fi

# ─── Step 4: deb 版 Firefox のインストール ───────────────
info "━━━ Step 4/5: deb 版 Firefox のインストール ━━━"
if dpkg -s firefox &>/dev/null 2>&1 && ! snap list firefox &>/dev/null 2>&1; then
    # deb版が既にインストールされていてsnap版でない場合
    local_ver=$(firefox --version 2>&1 | awk '{print $NF}')
    skip "deb 版 Firefox ${local_ver} は既にインストール済み"
else
    sudo apt install -y --allow-downgrades firefox
    ok "deb 版 Firefox をインストール: $(firefox --version 2>&1)"
fi

# ─── Step 5: 環境変数の設定 ──────────────────────────────
info "━━━ Step 5/5: 環境変数の設定 ━━━"
mkdir -p "$(dirname "$ENV_FILE")"
if [[ -f "$ENV_FILE" ]] && grep -q "MOZ_DISABLE_RDD_SANDBOX=1" "$ENV_FILE"; then
    skip "MOZ_DISABLE_RDD_SANDBOX=1 は既に設定済み"
else
    echo "MOZ_DISABLE_RDD_SANDBOX=1" > "$ENV_FILE"
    ok "MOZ_DISABLE_RDD_SANDBOX=1 を設定: $ENV_FILE"
fi

# ─── 結果表示 ─────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "設定完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
show_status
echo ""
info "反映方法:"
info "  ログアウトしてログインし直してください（environment.d の反映のため）"
info "  その後 Firefox を起動し、about:support の Media セクションで"
info "  HARDWARE_VIDEO_DECODING を確認してください"
echo ""
info "YouTube で確認:"
info "  動画を再生 → 右クリック → 「統計情報」→ Codecs 行に"
info "  「hardware accelerated」と表示されれば HW デコード有効"
echo ""
info "元に戻す場合:"
info "  bash $0 revert"
