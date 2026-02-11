#!/bin/bash
# fix-chrome-gesture.sh
#
# Chrome のタッチパッド・タッチパネルでの二本指スワイプによる
# ナビゲーション（戻る・進む）を修正する。
#
# 問題:
#   - トラックパッド: 二本指左右スワイプでナビゲーションが反応しない
#   - タッチパネル: ナビゲーション UI は出るが閾値がおかしく発動しない
#     (Wayland + fractional scaling 環境での座標ズレ)
#
# Usage:
#   bash fix-chrome-gesture.sh [status|revert]
#
#   (引数なし)  .desktop ファイルにフラグを設定する
#   status      現在の設定を表示する
#   revert      ユーザーオーバーライドを削除して元に戻す
#
# What it does:
#   ~/.local/share/applications/google-chrome.desktop をオーバーライドし、
#   Chrome 起動時に以下のフラグを付与:
#   --enable-features:
#     - TouchpadOverscrollHistoryNavigation: トラックパッドの二本指スワイプナビ有効化
#     - WaylandFractionalScaleV1: fractional scaling の座標処理を改善
#   --disable-features:
#     - WaylandPerSurfaceScale: fractional scaling でのタッチ座標ズレを修正
#
# Note:
#   設定後 Chrome の再起動が必要です（すべてのウィンドウを閉じて再度開く）。

set -euo pipefail

SYSTEM_DESKTOP="/usr/share/applications/google-chrome.desktop"
USER_DESKTOP="$HOME/.local/share/applications/google-chrome.desktop"
USER_DESKTOP_DIR="$HOME/.local/share/applications"

# ─── 設定するフラグ ───────────────────────────────────────
FEATURE_FLAGS=(
    "TouchpadOverscrollHistoryNavigation"
    "WaylandFractionalScaleV1"
)
FEATURES_CSV=$(IFS=,; echo "${FEATURE_FLAGS[*]}")

DISABLE_FLAGS=(
    "WaylandPerSurfaceScale"
    "PercentBasedScrolling"
)
DISABLE_CSV=$(IFS=,; echo "${DISABLE_FLAGS[*]}")

CHROME_FLAGS="--enable-features=${FEATURES_CSV} --disable-features=${DISABLE_CSV}"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
skip()  { echo -e "\033[1;36m[SKIP]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── ステータス表示 ───────────────────────────────────────
show_status() {
    info "システム .desktop: $SYSTEM_DESKTOP"
    info "ユーザー .desktop: $USER_DESKTOP"
    echo ""

    if [[ -f "$USER_DESKTOP" ]]; then
        ok "ユーザーオーバーライドが存在します"
        info "Exec 行:"
        grep "^Exec=" "$USER_DESKTOP" | while read -r line; do
            echo "  $line"
        done
    else
        info "ユーザーオーバーライドなし（システムデフォルト使用中）"
        info "Exec 行:"
        grep "^Exec=" "$SYSTEM_DESKTOP" | while read -r line; do
            echo "  $line"
        done
    fi

    echo ""
    info "Chrome プロセスの確認:"
    if pgrep -x chrome > /dev/null 2>&1; then
        local chrome_pid
        chrome_pid=$(pgrep -x chrome -o)
        local chrome_features
        chrome_features=$(tr '\0' '\n' < /proc/"$chrome_pid"/cmdline 2>/dev/null | grep -- '--enable-features' || echo "(フラグなし)")
        echo "  $chrome_features"
        if [[ "$chrome_features" == *"TouchpadOverscrollHistoryNavigation"* ]]; then
            ok "フラグは反映済み"
        else
            warn "フラグが未反映です。Chrome の再起動が必要です"
        fi
    else
        info "Chrome は起動していません"
    fi
}

# ─── 元に戻す ─────────────────────────────────────────────
revert() {
    if [[ -f "$USER_DESKTOP" ]]; then
        rm "$USER_DESKTOP"
        ok "ユーザーオーバーライドを削除しました: $USER_DESKTOP"
        info "システムデフォルトに戻りました"
        info "反映するには Chrome を再起動してください"
    else
        skip "ユーザーオーバーライドは存在しません"
    fi
}

# ─── Exec 行にフラグを付与する ────────────────────────────
inject_flags_to_exec() {
    local file="$1"
    local flags="$2"
    # Exec= 行に既にフラグが含まれていなければ追加
    # /usr/bin/google-chrome-stable の直後にフラグを挿入
    sed -i "s|^\(Exec=/usr/bin/google-chrome-stable\)\(.*\)|\1 ${flags}\2|" "$file"
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

# ─── システム .desktop の存在確認 ─────────────────────────
if [[ ! -f "$SYSTEM_DESKTOP" ]]; then
    error "Google Chrome がインストールされていません: $SYSTEM_DESKTOP"
fi

# ─── 既にフラグが設定済みか確認（全Exec行をチェック） ────
all_flags_present=true
if [[ -f "$USER_DESKTOP" ]]; then
    while IFS= read -r exec_line; do
        for flag in "${FEATURE_FLAGS[@]}" "${DISABLE_FLAGS[@]}"; do
            if [[ "$exec_line" != *"$flag"* ]]; then
                all_flags_present=false
                break 2
            fi
        done
    done < <(grep "^Exec=" "$USER_DESKTOP")
else
    all_flags_present=false
fi

if [[ "$all_flags_present" == true ]]; then
    skip "フラグは既に設定済みです"
    show_status
    exit 0
fi

# ─── ユーザー .desktop ディレクトリ作成 ───────────────────
mkdir -p "$USER_DESKTOP_DIR"

# ─── 既存のユーザーオーバーライドがあればバックアップ ─────
if [[ -f "$USER_DESKTOP" ]]; then
    cp "$USER_DESKTOP" "${USER_DESKTOP}.bak"
    info "既存オーバーライドのバックアップ: ${USER_DESKTOP}.bak"
fi

# ─── システム .desktop をコピー ───────────────────────────
cp "$SYSTEM_DESKTOP" "$USER_DESKTOP"
info "システム .desktop をコピー"

# ─── フラグを注入 ─────────────────────────────────────────
inject_flags_to_exec "$USER_DESKTOP" "$CHROME_FLAGS"
ok "フラグを注入: $CHROME_FLAGS"

# ─── デスクトップデータベースを更新 ──────────────────────
update-desktop-database "$USER_DESKTOP_DIR" 2>/dev/null || true

# ─── 結果表示 ─────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "設定完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "設定内容:"
grep "^Exec=" "$USER_DESKTOP" | head -1 | while read -r line; do
    info "  $line"
done
echo ""
info "反映方法:"
info "  Chrome をすべてのウィンドウを閉じて再起動してください"
echo ""
if pgrep -x chrome > /dev/null 2>&1; then
    warn "Chrome が起動中です。すべてのウィンドウを閉じて再起動してください"
fi
echo ""
info "元に戻す場合:"
info "  bash $0 revert"
