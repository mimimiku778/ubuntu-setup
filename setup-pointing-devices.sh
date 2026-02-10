#!/usr/bin/env bash
# setup-pointing-devices.sh
#
# ポインティングデバイス設定ウィザード
#
# 機能:
#   - マウス / トラックボール / タッチパッドを個別に調整
#   - ポインター速度・加速度をリアルタイムで試行→確定
#   - タッチパッドのスクロール速度を libinput-config で調整
#   - pointing-wizard エイリアスを登録して簡単に再呼び出し
#
# 対応環境:
#   - Ubuntu 24.04+ / GNOME / Wayland
#   - ポインター調整: gsettings (即時反映)
#   - スクロール調整: libinput-config (再ログインで反映)
#
# 使い方:
#   ./setup-pointing-devices.sh      # 通常のウィザード
#   pointing-wizard                  # エイリアス登録後

set -euo pipefail

# ─── 色付きログ ───────────────────────────────────────────
info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()      { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()     { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
header()  {
    echo ""
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;36m  $*\033[0m"
    echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
}
prompt_arrow() { echo -en "\033[1;33m  → \033[0m"; }

# ─── gsettings スキーマ定義 ───────────────────────────────
declare -A SCHEMA=(
    [mouse]="org.gnome.desktop.peripherals.mouse"
    [touchpad]="org.gnome.desktop.peripherals.touchpad"
)
declare -A LABEL=(
    [mouse]="マウス / トラックボール"
    [touchpad]="タッチパッド"
)

# トラックポイントはスキーマが存在する環境のみ追加
if gsettings list-keys org.gnome.desktop.peripherals.trackpoint &>/dev/null; then
    SCHEMA[trackpoint]="org.gnome.desktop.peripherals.trackpoint"
    LABEL[trackpoint]="トラックポイント"
fi

LIBINPUT_CONF="/etc/libinput.conf"

# ─── 利用可能なデバイス種別を列挙 ─────────────────────────
available_devices() {
    local result=()
    for dev in mouse touchpad trackpoint; do
        if [[ -n "${SCHEMA[$dev]:-}" ]]; then
            result+=("$dev")
        fi
    done
    echo "${result[@]}"
}

# ─── accel-profile キーの有無を確認 ──────────────────────
has_accel_profile() {
    gsettings list-keys "${SCHEMA[$1]}" 2>/dev/null | grep -q '^accel-profile$'
}

# ─── Step 1: デバイス選択 ─────────────────────────────────
step_select_device() {
    header "デバイスを選択"

    local devices
    read -ra devices <<< "$(available_devices)"
    if [[ ${#devices[@]} -eq 0 ]]; then
        err "利用可能なデバイスが見つかりません"; exit 1
    fi

    local i=1
    for dev in "${devices[@]}"; do
        echo "  $i) ${LABEL[$dev]}"
        ((i++))
    done

    echo ""
    prompt_arrow
    read -r choice

    local idx=$((choice - 1))
    if [[ $idx -lt 0 || $idx -ge ${#devices[@]} ]]; then
        err "無効な選択です"; exit 1
    fi

    SEL_DEV="${devices[$idx]}"
    SEL_SCHEMA="${SCHEMA[$SEL_DEV]}"
    ok "${LABEL[$SEL_DEV]} を選択"
}

# ─── Step 2: 調整項目選択 ─────────────────────────────────
step_select_mode() {
    header "調整する項目を選択"

    DO_POINTER=false
    DO_SCROLL=false

    local has_scroll=false
    if [[ "$SEL_DEV" == "touchpad" || "$SEL_DEV" == "trackpoint" ]]; then
        has_scroll=true
    fi

    echo "  1) ポインター速度・加速度"
    if $has_scroll; then
        echo "  2) スクロール速度"
        echo "  3) 両方"
    fi
    echo ""
    prompt_arrow
    read -r choice

    case "$choice" in
        1) DO_POINTER=true ;;
        2)
            if $has_scroll; then DO_SCROLL=true
            else err "無効な選択です"; exit 1; fi
            ;;
        3)
            if $has_scroll; then DO_POINTER=true; DO_SCROLL=true
            else err "無効な選択です"; exit 1; fi
            ;;
        *) err "無効な選択です"; exit 1 ;;
    esac
}

# ─── ポインター調整 (リアルタイム) ────────────────────────
step_adjust_pointer() {
    header "ポインター速度・加速度"

    local cur_speed cur_profile
    cur_speed=$(gsettings get "$SEL_SCHEMA" speed)

    local use_profile=false
    if has_accel_profile "$SEL_DEV"; then
        use_profile=true
        cur_profile=$(gsettings get "$SEL_SCHEMA" accel-profile | tr -d "'")
    fi

    info "現在の設定"
    echo "  速度:         $cur_speed  (-1.0〜1.0)"
    if $use_profile; then
        echo "  加速プロファイル: $cur_profile  (flat / adaptive)"
    fi
    echo ""

    echo "  【操作方法】"
    echo "  数値 (-1.0〜1.0)     速度・加速度を変更 (即時反映)"
    if $use_profile; then
        echo "  flat / adaptive      加速プロファイルを変更"
        echo "    flat    = 一定速度（加速なし）"
        echo "    adaptive = ゆっくり→遅く、速く→加速"
    fi
    echo "  ok                   確定"
    echo ""

    while true; do
        cur_speed=$(gsettings get "$SEL_SCHEMA" speed)
        if $use_profile; then
            cur_profile=$(gsettings get "$SEL_SCHEMA" accel-profile | tr -d "'")
            echo "  現在: 速度=$cur_speed  加速=$cur_profile"
        else
            echo "  現在: 速度=$cur_speed"
        fi
        prompt_arrow
        read -r input

        if [[ "$input" == "ok" || "$input" == "OK" || "$input" == "done" ]]; then
            break
        fi

        # 加速プロファイル変更
        if $use_profile; then
            case "$input" in
                flat|adaptive|default)
                    gsettings set "$SEL_SCHEMA" accel-profile "$input"
                    ok "加速プロファイル → $input"
                    echo ""
                    continue
                    ;;
            esac
        fi

        # 数値バリデーション
        if [[ "$input" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
            local val
            val=$(awk -v v="$input" 'BEGIN{
                if(v < -1.0) v = -1.0;
                if(v > 1.0) v = 1.0;
                printf "%.2f", v
            }')
            gsettings set "$SEL_SCHEMA" speed "$val"
            ok "速度 → $val  (ポインターを動かして確認してください)"
        else
            if $use_profile; then
                warn "数値 (-1.0〜1.0) または flat/adaptive を入力してください"
            else
                warn "数値 (-1.0〜1.0) を入力してください"
            fi
        fi
        echo ""
    done

    echo ""
    ok "ポインター設定を確定"
    cur_speed=$(gsettings get "$SEL_SCHEMA" speed)
    echo "  速度: $cur_speed"
    if $use_profile; then
        cur_profile=$(gsettings get "$SEL_SCHEMA" accel-profile | tr -d "'")
        echo "  加速: $cur_profile"
    fi
}

# ─── libinput-config のインストール ───────────────────────
ensure_libinput_config() {
    if grep -qs 'libinput-config' /etc/ld.so.preload 2>/dev/null; then
        ok "libinput-config はインストール済み"
        return 0
    fi

    local so_path
    so_path=$(find /usr/local/lib* /usr/lib* -name 'libinput-config.so' 2>/dev/null | head -1 || true)
    if [[ -n "$so_path" ]]; then
        ok "libinput-config ライブラリ検出: $so_path"
        return 0
    fi

    echo ""
    warn "スクロール速度の調整には libinput-config が必要です"
    echo "  GNOME は Wayland 上でスクロール速度設定を公開していないため、"
    echo "  libinput-config を使って libinput レベルで調整します。"
    echo ""
    echo "  インストールしますか？ (y/n)"
    prompt_arrow
    read -r yn

    if [[ "$yn" != "y" && "$yn" != "Y" ]]; then
        warn "スクロール調整をスキップします"
        return 1
    fi

    info "依存パッケージをインストール中..."
    sudo apt update -qq
    sudo apt install -y meson libinput-dev git build-essential

    local tmpdir
    tmpdir=$(mktemp -d)
    info "ソースを取得中..."
    git clone --depth 1 https://gitlab.com/warningnonpotablewater/libinput-config.git "$tmpdir/libinput-config"

    # サブシェルでビルド (カレントディレクトリを汚さない)
    (
        cd "$tmpdir/libinput-config"
        meson setup build
        cd build
        ninja
        sudo ninja install
    )

    rm -rf "$tmpdir"
    ok "libinput-config をインストールしました"
    return 0
}

# ─── スクロール速度調整 ──────────────────────────────────
step_adjust_scroll() {
    header "スクロール速度"

    if ! ensure_libinput_config; then
        return
    fi

    local cur_factor="1.0 (デフォルト)"
    if [[ -f "$LIBINPUT_CONF" ]]; then
        local found
        found=$(grep -oP '^scroll-factor=\K[0-9.]+' "$LIBINPUT_CONF" 2>/dev/null || true)
        if [[ -n "$found" ]]; then
            cur_factor="$found"
        fi
    fi

    info "現在の scroll-factor: $cur_factor"
    echo ""
    echo "  目安:"
    echo "    0.15  かなり遅い"
    echo "    0.3   遅め"
    echo "    0.5   半分の速度"
    echo "    0.8   少し遅め"
    echo "    1.0   デフォルト"
    echo "    1.5   速め"
    echo ""

    if [[ "$SEL_DEV" == "touchpad" ]]; then
        info "タッチパッドのスクロールに適用されます"
    elif [[ "$SEL_DEV" == "trackpoint" ]]; then
        info "トラックポイントのボタンスクロールに適用されます"
    fi
    warn "再ログイン後に反映されます"
    echo ""

    echo "  scroll-factor を入力 (例: 0.4):"
    prompt_arrow
    read -r factor

    if [[ ! "$factor" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        err "正の数値を入力してください"; exit 1
    fi

    sudo tee "$LIBINPUT_CONF" > /dev/null << EOF
# Added by setup-pointing-devices.sh
scroll-factor=$factor
discrete-scroll-factor=1.0
EOF

    ok "scroll-factor=$factor を設定"
    warn "反映にはログアウト→再ログインが必要です"
}

# ─── エイリアス登録 ───────────────────────────────────────
setup_alias() {
    local script_path
    script_path=$(readlink -f "$0")
    local bashrc="$HOME/.bashrc"

    if grep -qF "pointing-wizard" "$bashrc" 2>/dev/null; then
        return
    fi

    {
        echo ""
        echo "# Added by setup-pointing-devices.sh"
        echo "alias pointing-wizard='$script_path'"
    } >> "$bashrc"
    ok "エイリアス 'pointing-wizard' を登録しました"
    info "新しいターミナルで pointing-wizard で呼び出せます"
}

# ─── 続けるか確認 ─────────────────────────────────────────
ask_continue() {
    echo ""
    echo "  別のデバイスも調整しますか？ (y/n)"
    prompt_arrow
    read -r yn
    [[ "$yn" == "y" || "$yn" == "Y" ]]
}

# ─── メイン ───────────────────────────────────────────────
main() {
    header "ポインティングデバイス設定ウィザード"
    info "マウス・タッチパッドの速度やスクロールを調整します"

    while true; do
        step_select_device
        step_select_mode

        if $DO_POINTER; then
            step_adjust_pointer
        fi

        if $DO_SCROLL; then
            step_adjust_scroll
        fi

        if ! ask_continue; then
            break
        fi
    done

    setup_alias

    header "完了"
    ok "設定が完了しました"
    if $DO_SCROLL; then
        warn "スクロール速度は再ログイン後に反映されます"
    fi
    info "再調整 → pointing-wizard"
}

main "$@"
