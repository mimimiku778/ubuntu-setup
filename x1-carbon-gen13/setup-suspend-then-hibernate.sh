#!/bin/bash
# setup-suspend-then-hibernate.sh
#
# スリープ後に一定時間で自動ハイバネートする設定。
# バッテリー切れによるセッション消失を防止する。
#
# 動作: 蓋を閉じる → サスペンド(s2idle) → 指定時間後にRTCで復帰 → ハイバネート → 電源オフ
#       電源ボタン押下 → ハイバネートから復帰 → セッション継続
#
# Usage:
#   sudo bash setup-suspend-then-hibernate.sh enable [時間]
#   sudo bash setup-suspend-then-hibernate.sh disable
#   sudo bash setup-suspend-then-hibernate.sh status
#   sudo bash setup-suspend-then-hibernate.sh set-delay <時間>
#
#   時間の例: 30min, 2h, 24h (デフォルト: 24h)
#
# 前提:
#   - スワップが RAM 以上 (ハイバネートにはメモリ全体をディスクに退避するため)
#   - GRUB に resume= / resume_offset= が設定済み
#   - dracut に resume モジュールが含まれていること
#
# 設定ファイル:
#   /etc/polkit-1/rules.d/10-enable-hibernate.rules
#   /etc/systemd/sleep.conf.d/99-hibernate-delay.conf
#   /etc/systemd/logind.conf.d/99-suspend-then-hibernate.conf
#   /etc/dracut.conf.d/resume.conf

set -euo pipefail

DEFAULT_DELAY="24h"

POLKIT_RULE="/etc/polkit-1/rules.d/10-enable-hibernate.rules"
SLEEP_CONF="/etc/systemd/sleep.conf.d/99-hibernate-delay.conf"
LOGIND_CONF="/etc/systemd/logind.conf.d/99-suspend-then-hibernate.conf"
DRACUT_CONF="/etc/dracut.conf.d/resume.conf"

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── 使い方 ──────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: sudo bash $0 <command> [options]

Commands:
  enable [時間]      suspend-then-hibernate を有効化 (デフォルト: $DEFAULT_DELAY)
  disable            設定を削除して無効化
  status             現在の設定と前提条件を表示
  set-delay <時間>   ハイバネートまでの時間を変更

時間の例: 30min, 1h, 2h, 12h, 24h
EOF
    exit 1
}

# ─── 前提条件チェック ────────────────────────────────────
check_prerequisites() {
    local errors=0

    # スワップ容量チェック
    local swap_kb ram_kb
    swap_kb=$(awk '/^\/swap/ {print $3}' /proc/swaps 2>/dev/null | head -1)
    ram_kb=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
    swap_kb="${swap_kb:-0}"

    if (( swap_kb < ram_kb )); then
        warn "スワップ ($(( swap_kb / 1024 ))MB) が RAM ($(( ram_kb / 1024 ))MB) より小さい"
        warn "ハイバネートには RAM 以上のスワップが必要です"
        errors=$((errors + 1))
    else
        ok "スワップ: $(( swap_kb / 1024 ))MB >= RAM $(( ram_kb / 1024 ))MB"
    fi

    # resume カーネルパラメータ
    if grep -q "resume=" /proc/cmdline 2>/dev/null; then
        ok "GRUB resume= パラメータ: 設定済み"
    else
        warn "GRUB に resume= パラメータが未設定"
        warn "  /etc/default/grub の GRUB_CMDLINE_LINUX_DEFAULT に以下を追加:"
        warn "    resume=<デバイス> resume_offset=<オフセット>"
        errors=$((errors + 1))
    fi

    # /sys/power/resume
    local resume_dev
    resume_dev=$(cat /sys/power/resume 2>/dev/null)
    if [[ "$resume_dev" != "0:0" && -n "$resume_dev" ]]; then
        ok "/sys/power/resume: $resume_dev"
    else
        warn "/sys/power/resume が未設定 (0:0)"
        warn "  dracut に resume モジュールが必要です"
        errors=$((errors + 1))
    fi

    # /sys/power/state に disk があるか
    if grep -q disk /sys/power/state 2>/dev/null; then
        ok "カーネル: disk (hibernate) サポートあり"
    else
        warn "カーネルが hibernate をサポートしていません"
        errors=$((errors + 1))
    fi

    # CanHibernate
    local can
    can=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager CanHibernate 2>/dev/null | awk '{print $2}' | tr -d '"')
    if [[ "$can" == "yes" ]]; then
        ok "CanHibernate: yes"
    else
        # polkit ルール適用前は "no" になるので enable 時はスキップ可能
        warn "CanHibernate: ${can:-unknown}"
    fi

    return $errors
}

# ─── 現在の状態を表示 ────────────────────────────────────
show_status() {
    echo ""
    info "=== 前提条件 ==="
    check_prerequisites || true

    echo ""
    info "=== 設定ファイル ==="
    local files=("$POLKIT_RULE" "$SLEEP_CONF" "$LOGIND_CONF" "$DRACUT_CONF")
    for f in "${files[@]}"; do
        if sudo test -f "$f"; then
            ok "$f"
        else
            warn "$f (なし)"
        fi
    done

    echo ""
    info "=== 現在の動作設定 ==="

    # HibernateDelaySec
    local delay
    delay=$(grep -h "^HibernateDelaySec" /etc/systemd/sleep.conf.d/*.conf 2>/dev/null | tail -1 | cut -d= -f2)
    if [[ -n "$delay" ]]; then
        ok "ハイバネートまでの時間: $delay"
    else
        warn "HibernateDelaySec: 未設定"
    fi

    # logind HandleLidSwitch
    local lid
    lid=$(grep -h "^HandleLidSwitch=" /etc/systemd/logind.conf.d/*.conf 2>/dev/null | tail -1 | cut -d= -f2)
    if [[ "$lid" == "suspend-then-hibernate" ]]; then
        ok "蓋閉じ: suspend-then-hibernate"
    else
        warn "蓋閉じ: ${lid:-suspend (デフォルト)}"
    fi

    echo ""
}

# ─── 有効化 ──────────────────────────────────────────────
do_enable() {
    local delay="${1:-$DEFAULT_DELAY}"

    info "suspend-then-hibernate を有効化中 (遅延: $delay) ..."
    echo ""

    # ── polkit: Ubuntu のハイバネート無効化をオーバーライド ──
    info "polkit ルールを作成: $POLKIT_RULE"
    cat > "$POLKIT_RULE" <<'POLKIT'
// Enable hibernate for active local users in sudo group
// setup-suspend-then-hibernate.sh で生成
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit") {
        if (subject.active == true && subject.local == true &&
            subject.isInGroup("sudo")) {
                return polkit.Result.YES;
        }
    }
});
POLKIT
    ok "polkit ルール作成完了"

    # ── sleep.conf: ハイバネートまでの遅延時間 ──
    info "sleep.conf を作成: $SLEEP_CONF"
    mkdir -p "$(dirname "$SLEEP_CONF")"
    cat > "$SLEEP_CONF" <<SLEEP
[Sleep]
# setup-suspend-then-hibernate.sh で生成
HibernateDelaySec=$delay
SLEEP
    ok "HibernateDelaySec=$delay"

    # ── logind.conf: 蓋閉じ → suspend-then-hibernate ──
    info "logind.conf を作成: $LOGIND_CONF"
    mkdir -p "$(dirname "$LOGIND_CONF")"
    cat > "$LOGIND_CONF" <<'LOGIND'
[Login]
# setup-suspend-then-hibernate.sh で生成
# 蓋閉じ時にsuspend-then-hibernateを使用
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
LOGIND
    ok "HandleLidSwitch=suspend-then-hibernate"

    # ── dracut: resume モジュール ──
    if [[ ! -f "$DRACUT_CONF" ]]; then
        info "dracut resume モジュール設定を作成: $DRACUT_CONF"
        cat > "$DRACUT_CONF" <<'DRACUT'
# setup-suspend-then-hibernate.sh で生成
add_dracutmodules+=" resume "
DRACUT
        ok "dracut resume モジュール追加"
        warn "initramfs の再構築が必要です: sudo dracut --force"
    else
        ok "dracut resume モジュール: 設定済み (スキップ)"
    fi

    # ── logind をリロード (再起動ではなくリロード) ──
    systemctl daemon-reload
    systemctl kill -s HUP systemd-logind 2>/dev/null || true
    ok "systemd 設定リロード完了"

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "suspend-then-hibernate を有効化しました"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "動作: 蓋を閉じる → サスペンド → ${delay}後 → 自動ハイバネート"
    info ""
    info "テスト: sudo systemctl hibernate (手動でハイバネートを確認)"
    info "時間変更: sudo bash $0 set-delay <時間>"
    info "無効化: sudo bash $0 disable"
}

# ─── 無効化 ──────────────────────────────────────────────
do_disable() {
    info "suspend-then-hibernate を無効化中..."
    echo ""

    local files=("$POLKIT_RULE" "$SLEEP_CONF" "$LOGIND_CONF")
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            rm "$f"
            ok "削除: $f"
        else
            info "存在しません: $f (スキップ)"
        fi
    done

    # dracut resume.conf は残す (ハイバネートとは独立して有用)
    if [[ -f "$DRACUT_CONF" ]]; then
        info "$DRACUT_CONF は残しています (手動で削除可)"
    fi

    # logind をリロード
    systemctl daemon-reload
    systemctl kill -s HUP systemd-logind 2>/dev/null || true
    ok "systemd 設定リロード完了"

    echo ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "suspend-then-hibernate を無効化しました"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "蓋閉じはデフォルトのサスペンドに戻ります"
    info "GRUB の resume= パラメータは残っています (手動で削除可)"
}

# ─── 遅延時間変更 ────────────────────────────────────────
do_set_delay() {
    local delay="$1"
    if [[ -z "$delay" ]]; then
        error "時間を指定してください (例: 30min, 2h, 24h)"
    fi

    if [[ ! -f "$SLEEP_CONF" ]]; then
        error "設定が有効化されていません。先に enable を実行してください。"
    fi

    mkdir -p "$(dirname "$SLEEP_CONF")"
    cat > "$SLEEP_CONF" <<SLEEP
[Sleep]
# setup-suspend-then-hibernate.sh で生成
HibernateDelaySec=$delay
SLEEP

    systemctl daemon-reload
    ok "HibernateDelaySec を $delay に変更しました (即時反映)"
}

# ─── メイン ──────────────────────────────────────────────
ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
    usage
fi

if [[ "$ACTION" == "status" ]]; then
    show_status
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    error "root 権限が必要です。sudo bash $0 $ACTION で実行してください。"
fi

case "$ACTION" in
    enable)    do_enable "${2:-}" ;;
    disable)   do_disable ;;
    set-delay) do_set_delay "${2:-}" ;;
    status)    show_status ;;
    *)         usage ;;
esac
