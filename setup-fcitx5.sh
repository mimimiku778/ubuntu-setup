#!/bin/bash
# setup-fcitx5.sh
#
# Fcitx5 + Mozc の完全セットアップ。
# 日本語入力環境の構築と、どの状況でも変換/無変換キーで
# IME のオンオフを切り替え可能にする。
#
# Usage:
#   bash setup-fcitx5.sh
#
# What it does:
#   1. fcitx5 / fcitx5-mozc をインストール (未インストールの場合)
#   2. im-config で fcitx5 をデフォルト入力メソッドに設定
#   3. 物理キーボードレイアウトを検出して fcitx5 プロファイルを設定
#   4. Fcitx5 ホットキー設定:
#      - ActivateKeys / DeactivateKeys を無効化
#      - ShareInputState を All に設定 (全ウィンドウで IME 状態を共有)
#   5. Mozc キーマップ設定:
#      - MS-IME ベース
#      - Henkan / Muhenkan エントリを削除
#      - 入力モード切替を削除 (常にひらがなモード)
#   6. GNOME カスタムキーボードショートカット:
#      - 変換 (Henkan) → fcitx5-remote -o (IME オン)
#      - 無変換 (Muhenkan) → fcitx5-remote -c (IME オフ)
#
# Requirements:
#   - GNOME デスクトップ環境
#   - sudo 権限 (パッケージインストール時)

set -euo pipefail

# ─── 色付きログ ───────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
skip()  { echo -e "\033[1;33m[SKIP]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# ─── 前提条件チェック ─────────────────────────────────────
if ! command -v gsettings &>/dev/null; then
    error "gsettings が見つかりません。GNOME デスクトップ環境が必要です。"
fi

if ! command -v python3 &>/dev/null; then
    error "python3 が見つかりません。"
fi

# ─── 1. パッケージインストール ────────────────────────────
info "パッケージを確認中..."

PACKAGES=(fcitx5 fcitx5-mozc)
missing=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        missing+=("$pkg")
    fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
    ok "必要なパッケージはすべてインストール済み"
else
    info "パッケージをインストール中: ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${missing[@]}"
    ok "パッケージをインストール完了"
fi

# ─── 2. im-config で fcitx5 をデフォルトに ────────────────
info "入力メソッドフレームワークを設定中..."

current_im=$(im-config -m 2>/dev/null | tail -1)
if [[ "$current_im" == "fcitx5" ]]; then
    ok "fcitx5 は既にデフォルトの入力メソッド"
else
    im-config -n fcitx5
    ok "fcitx5 をデフォルトの入力メソッドに設定"
    warn "この変更はログアウト後に反映されます"
fi

# ─── 3. キーボードレイアウト検出 + fcitx5 プロファイル ────
info "キーボードレイアウトを検出中..."

KB_LAYOUT=""

# GNOME 設定から検出
sources=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "")
KB_LAYOUT=$(echo "$sources" | grep -oP "'xkb',\s*'\\K[^']+" || true)

# localectl にフォールバック
if [[ -z "$KB_LAYOUT" ]]; then
    KB_LAYOUT=$(localectl status 2>/dev/null | grep "X11 Layout" | awk '{print $3}' || true)
fi

# 最終フォールバック
if [[ -z "$KB_LAYOUT" ]]; then
    KB_LAYOUT="us"
    warn "キーボードレイアウトを検出できません。デフォルト (us) を使用します。"
fi

ok "キーボードレイアウト: $KB_LAYOUT"

# ─── Fcitx5 停止 (設定ファイル書き込み前) ─────────────────
FCITX5_WAS_RUNNING=false
if fcitx5-remote --check &>/dev/null; then
    FCITX5_WAS_RUNNING=true
    info "Fcitx5 を一時停止中..."
    fcitx5-remote -e &>/dev/null || true
    for _ in {1..10}; do
        fcitx5-remote --check &>/dev/null || break
        sleep 0.5
    done
fi

# ─── fcitx5 プロファイル作成 ──────────────────────────────
mkdir -p "$HOME/.config/fcitx5"

cat > "$HOME/.config/fcitx5/profile" << EOF
[Groups/0]
Name=Default
Default Layout=${KB_LAYOUT}
DefaultIM=mozc

[Groups/0/Items/0]
Name=keyboard-${KB_LAYOUT}
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[GroupOrder]
0=Default
EOF

ok "fcitx5 プロファイルを設定 (keyboard-${KB_LAYOUT} + mozc)"

# ─── 4. Fcitx5 ホットキー設定 ────────────────────────────
info "Fcitx5 ホットキーを設定中..."

cat > "$HOME/.config/fcitx5/config" << 'EOF'
[Hotkey]
TriggerKeys=
EnumerateWithTriggerKeys=True
EnumerateForwardKeys=
EnumerateBackwardKeys=
EnumerateSkipFirst=False
EnumerateGroupForwardKeys=
EnumerateGroupBackwardKeys=
ModifierOnlyKeyTimeout=250

[Hotkey/AltTriggerKeys]
0=Shift+Shift_L

# ActivateKeys / DeactivateKeys は無効化
# GNOME カスタムショートカット経由で fcitx5-remote を使用
[Hotkey/ActivateKeys]

[Hotkey/DeactivateKeys]

[Hotkey/PrevPage]
0=Up

[Hotkey/NextPage]
0=Down

[Hotkey/PrevCandidate]
0=Shift+Tab

[Hotkey/NextCandidate]
0=Tab

[Hotkey/TogglePreedit]
0=Control+Alt+P

[Behavior]
ActiveByDefault=False
resetStateWhenFocusIn=No
# 全ウィンドウで IME 状態を共有
ShareInputState=All
PreeditEnabledByDefault=True
ShowInputMethodInformation=True
showInputMethodInformationWhenFocusIn=False
CompactInputMethodInformation=True
ShowFirstInputMethodInformation=True
DefaultPageSize=5
OverrideXkbOption=False
CustomXkbOption=
EnabledAddons=
DisabledAddons=
PreloadInputMethod=True
AllowInputMethodForPassword=False
ShowPreeditForPassword=False
AutoSavePeriod=30
EOF

ok "Fcitx5 ホットキー設定完了"

# ─── 5. Mozc キーマップ設定 ───────────────────────────────
info "Mozc キーマップを設定中..."

# mozc_server を停止 (config1.db を安全に書き換えるため)
pkill -f mozc_server 2>/dev/null || true
sleep 0.5

MOZC_CONFIG_DIR="$HOME/.config/mozc"
MOZC_CONFIG="$MOZC_CONFIG_DIR/config1.db"
mkdir -p "$MOZC_CONFIG_DIR"

# Python スクリプトで config1.db の protobuf を操作
# - session_keymap を CUSTOM (1) に設定
# - custom_keymap_table に MS-IME ベースのキーマップを設定
#   (Henkan/Muhenkan 削除, 入力モード切替削除)
python3 << 'PYEOF'
import os
import sys

CONFIG_DIR = os.path.expanduser("~/.config/mozc")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config1.db")

# MS-IME ベースのキーマップ
# - Henkan / Muhenkan エントリを削除
# - 入力モード切替コマンドを削除 (常にひらがなモード):
#   ToggleAlphanumericMode, SwitchKanaType,
#   CompositionModeHiragana, CompositionModeFullKatakana,
#   CompositionModeSwitchKanaType
KEYMAP_ENTRIES = [
    # ── Composition ──
    ("Composition", "ASCII", "InsertCharacter"),
    ("Composition", "Backspace", "Backspace"),
    ("Composition", "Ctrl a", "MoveCursorToBeginning"),
    ("Composition", "Ctrl Backspace", "Backspace"),
    ("Composition", "Ctrl d", "MoveCursorRight"),
    ("Composition", "Ctrl Down", "MoveCursorToEnd"),
    ("Composition", "Ctrl e", "MoveCursorToBeginning"),
    ("Composition", "Ctrl Enter", "Commit"),
    ("Composition", "Ctrl f", "MoveCursorToEnd"),
    ("Composition", "Ctrl g", "Delete"),
    ("Composition", "Ctrl h", "Backspace"),
    ("Composition", "Ctrl i", "ConvertToFullKatakana"),
    ("Composition", "Ctrl k", "MoveCursorLeft"),
    ("Composition", "Ctrl l", "MoveCursorRight"),
    ("Composition", "Ctrl Left", "MoveCursorToBeginning"),
    ("Composition", "Ctrl m", "Commit"),
    ("Composition", "Ctrl n", "MoveCursorToEnd"),
    ("Composition", "Ctrl o", "ConvertToHalfWidth"),
    ("Composition", "Ctrl p", "ConvertToFullAlphanumeric"),
    ("Composition", "Ctrl Right", "MoveCursorToEnd"),
    ("Composition", "Ctrl s", "MoveCursorLeft"),
    ("Composition", "Ctrl Shift Space", "InsertFullSpace"),
    ("Composition", "Ctrl Space", "InsertHalfSpace"),
    ("Composition", "Ctrl t", "ConvertToHalfAlphanumeric"),
    ("Composition", "Ctrl u", "ConvertToHiragana"),
    ("Composition", "Ctrl Up", "MoveCursorToBeginning"),
    ("Composition", "Ctrl x", "MoveCursorToEnd"),
    ("Composition", "Ctrl z", "Cancel"),
    ("Composition", "Delete", "Delete"),
    ("Composition", "Down", "MoveCursorToEnd"),
    ("Composition", "End", "MoveCursorToEnd"),
    ("Composition", "Enter", "Commit"),
    ("Composition", "ESC", "Cancel"),
    ("Composition", "F10", "ConvertToHalfAlphanumeric"),
    ("Composition", "F2", "ConvertWithoutHistory"),
    ("Composition", "F6", "ConvertToHiragana"),
    ("Composition", "F7", "ConvertToFullKatakana"),
    ("Composition", "F8", "ConvertToHalfWidth"),
    ("Composition", "F9", "ConvertToFullAlphanumeric"),
    ("Composition", "Hankaku/Zenkaku", "IMEOff"),
    ("Composition", "Home", "MoveCursorToBeginning"),
    ("Composition", "Kanji", "IMEOff"),
    ("Composition", "Left", "MoveCursorLeft"),
    ("Composition", "OFF", "IMEOff"),
    ("Composition", "ON", "IMEOn"),
    ("Composition", "Right", "MoveCursorRight"),
    ("Composition", "Shift Backspace", "Backspace"),
    ("Composition", "Shift ESC", "Cancel"),
    ("Composition", "Shift Left", "MoveCursorLeft"),
    ("Composition", "Shift Right", "MoveCursorRight"),
    ("Composition", "Shift Space", "Convert"),
    ("Composition", "Space", "Convert"),
    ("Composition", "Tab", "PredictAndConvert"),
    ("Composition", "VirtualEnter", "Commit"),
    ("Composition", "VirtualLeft", "MoveCursorLeft"),
    ("Composition", "VirtualRight", "MoveCursorRight"),
    # ── Conversion ──
    ("Conversion", "Backspace", "Cancel"),
    ("Conversion", "Ctrl a", "SegmentFocusFirst"),
    ("Conversion", "Ctrl Backspace", "Cancel"),
    ("Conversion", "Ctrl d", "SegmentFocusRight"),
    ("Conversion", "Ctrl Down", "CommitOnlyFirstSegment"),
    ("Conversion", "Ctrl e", "ConvertPrev"),
    ("Conversion", "Ctrl Enter", "Commit"),
    ("Conversion", "Ctrl f", "SegmentFocusLast"),
    ("Conversion", "Ctrl g", "Cancel"),
    ("Conversion", "Ctrl h", "Cancel"),
    ("Conversion", "Ctrl i", "ConvertToFullKatakana"),
    ("Conversion", "Ctrl k", "SegmentWidthShrink"),
    ("Conversion", "Ctrl l", "SegmentWidthExpand"),
    ("Conversion", "Ctrl Left", "SegmentFocusFirst"),
    ("Conversion", "Ctrl m", "Commit"),
    ("Conversion", "Ctrl n", "CommitOnlyFirstSegment"),
    ("Conversion", "Ctrl o", "ConvertToHalfWidth"),
    ("Conversion", "Ctrl p", "ConvertToFullAlphanumeric"),
    ("Conversion", "Ctrl Right", "SegmentFocusLast"),
    ("Conversion", "Ctrl s", "SegmentFocusLeft"),
    ("Conversion", "Ctrl Shift Space", "InsertFullSpace"),
    ("Conversion", "Ctrl Space", "InsertHalfSpace"),
    ("Conversion", "Ctrl t", "ConvertToHalfAlphanumeric"),
    ("Conversion", "Ctrl u", "ConvertToHiragana"),
    ("Conversion", "Ctrl Up", "ConvertPrev"),
    ("Conversion", "Ctrl x", "ConvertNext"),
    ("Conversion", "Ctrl z", "Cancel"),
    ("Conversion", "Delete", "Cancel"),
    ("Conversion", "Down", "ConvertNext"),
    ("Conversion", "End", "SegmentFocusLast"),
    ("Conversion", "Enter", "Commit"),
    ("Conversion", "ESC", "Cancel"),
    ("Conversion", "F1", "ReportBug"),
    ("Conversion", "F10", "ConvertToHalfAlphanumeric"),
    ("Conversion", "F3", "ReportBug"),
    ("Conversion", "F6", "ConvertToHiragana"),
    ("Conversion", "F7", "ConvertToFullKatakana"),
    ("Conversion", "F8", "ConvertToHalfWidth"),
    ("Conversion", "F9", "ConvertToFullAlphanumeric"),
    ("Conversion", "Hankaku/Zenkaku", "IMEOff"),
    ("Conversion", "Home", "SegmentFocusFirst"),
    ("Conversion", "Kanji", "IMEOff"),
    ("Conversion", "Left", "SegmentFocusLeft"),
    ("Conversion", "OFF", "IMEOff"),
    ("Conversion", "ON", "IMEOn"),
    ("Conversion", "PageDown", "ConvertNextPage"),
    ("Conversion", "PageUp", "ConvertPrevPage"),
    ("Conversion", "Right", "SegmentFocusRight"),
    ("Conversion", "Shift Backspace", "Cancel"),
    ("Conversion", "Shift Down", "ConvertNextPage"),
    ("Conversion", "Shift ESC", "Cancel"),
    ("Conversion", "Shift Left", "SegmentWidthShrink"),
    ("Conversion", "Shift Right", "SegmentWidthExpand"),
    ("Conversion", "Shift Space", "ConvertPrev"),
    ("Conversion", "Shift Tab", "ConvertPrev"),
    ("Conversion", "Shift Up", "ConvertPrevPage"),
    ("Conversion", "Space", "ConvertNext"),
    ("Conversion", "Tab", "PredictAndConvert"),
    ("Conversion", "Up", "ConvertPrev"),
    ("Conversion", "VirtualEnter", "CommitOnlyFirstSegment"),
    ("Conversion", "VirtualLeft", "SegmentWidthShrink"),
    ("Conversion", "VirtualRight", "SegmentWidthExpand"),
    # ── DirectInput ──
    ("DirectInput", "Eisu", "IMEOn"),
    ("DirectInput", "F13", "IMEOn"),
    ("DirectInput", "Hankaku/Zenkaku", "IMEOn"),
    ("DirectInput", "Hiragana", "IMEOn"),
    ("DirectInput", "Kanji", "IMEOn"),
    ("DirectInput", "Katakana", "IMEOn"),
    ("DirectInput", "ON", "IMEOn"),
    # ── Precomposition ──
    ("Precomposition", "ASCII", "InsertCharacter"),
    ("Precomposition", "Backspace", "Revert"),
    ("Precomposition", "Ctrl Backspace", "Undo"),
    ("Precomposition", "Ctrl Shift Space", "InsertFullSpace"),
    ("Precomposition", "Hankaku/Zenkaku", "IMEOff"),
    ("Precomposition", "Kanji", "IMEOff"),
    ("Precomposition", "OFF", "IMEOff"),
    ("Precomposition", "ON", "IMEOn"),
    ("Precomposition", "Shift Space", "InsertAlternateSpace"),
    ("Precomposition", "Space", "InsertSpace"),
    # ── Prediction / Suggestion ──
    ("Prediction", "Ctrl Delete", "DeleteSelectedCandidate"),
    ("Suggestion", "Down", "PredictAndConvert"),
    ("Suggestion", "Shift Enter", "CommitFirstSuggestion"),
]

keymap_tsv = "status\tkey\tcommand\n" + "\n".join(
    f"{s}\t{k}\t{c}" for s, k, c in KEYMAP_ENTRIES
)


# ── Protobuf ヘルパー ──

def encode_varint(value):
    result = bytearray()
    while value > 0x7F:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value & 0x7F)
    return bytes(result)


def decode_varint(data, offset):
    result = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        result |= (byte & 0x7F) << shift
        offset += 1
        if (byte & 0x80) == 0:
            return result, offset
        shift += 7
    raise ValueError("Truncated varint")


def parse_fields(data):
    fields = []
    offset = 0
    while offset < len(data):
        key, offset = decode_varint(data, offset)
        field_number = key >> 3
        wire_type = key & 0x07
        if wire_type == 0:  # varint
            start = offset
            _, offset = decode_varint(data, offset)
            raw = data[start:offset]
        elif wire_type == 1:  # 64-bit
            raw = data[offset:offset + 8]
            offset += 8
        elif wire_type == 2:  # length-delimited
            length, offset = decode_varint(data, offset)
            raw = data[offset:offset + length]
            offset += length
        elif wire_type == 5:  # 32-bit
            raw = data[offset:offset + 4]
            offset += 4
        else:
            raise ValueError(f"Unknown wire type {wire_type}")
        fields.append((field_number, wire_type, raw))
    return fields


def serialize_fields(fields):
    result = bytearray()
    for field_number, wire_type, raw in fields:
        key = (field_number << 3) | wire_type
        result.extend(encode_varint(key))
        if wire_type == 0:  # varint
            result.extend(raw)
        elif wire_type == 1:  # 64-bit
            result.extend(raw)
        elif wire_type == 2:  # length-delimited
            result.extend(encode_varint(len(raw)))
            result.extend(raw)
        elif wire_type == 5:  # 32-bit
            result.extend(raw)
    return bytes(result)


# ── config1.db を読み込み・書き換え ──

if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, "rb") as f:
        data = f.read()
    fields = parse_fields(data)
else:
    fields = []

# session_keymap (field 18) と custom_keymap_table (field 19) を除去
fields = [(fn, wt, raw) for fn, wt, raw in fields if fn not in (18, 19)]

# session_keymap = CUSTOM (1)
fields.append((18, 0, encode_varint(1)))

# custom_keymap_table = キーマップ TSV
fields.append((19, 2, keymap_tsv.encode("utf-8")))

with open(CONFIG_PATH, "wb") as f:
    f.write(serialize_fields(fields))

print("OK")
PYEOF

ok "Mozc キーマップ設定完了 (MS-IME ベース, Henkan/Muhenkan 削除, 常にひらがなモード)"

# ─── 6. GNOME カスタムショートカット ──────────────────────
info "GNOME カスタムキーボードショートカットを設定中..."

SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CUSTOM_SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding"
BASE_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

activate_path="${BASE_PATH}/ime-activate/"
deactivate_path="${BASE_PATH}/ime-deactivate/"

# 既存のカスタムキーバインディングを取得
existing=$(gsettings get "$SCHEMA" custom-keybindings)

# 新しいリストを構築 (既存のバインディングを保持しつつ追加)
new_list="$existing"
for path in "$activate_path" "$deactivate_path"; do
    if ! echo "$new_list" | grep -qF "$path"; then
        if [[ "$new_list" == "@as []" ]] || [[ "$new_list" == "[]" ]]; then
            new_list="['${path}']"
        else
            new_list="${new_list%]}, '${path}']"
        fi
    fi
done

gsettings set "$SCHEMA" custom-keybindings "$new_list"

# 変換キー → IME オン
gsettings set "$CUSTOM_SCHEMA:$activate_path" name 'IME オン (変換)'
gsettings set "$CUSTOM_SCHEMA:$activate_path" command 'fcitx5-remote -o'
gsettings set "$CUSTOM_SCHEMA:$activate_path" binding 'Henkan_Mode'
ok "変換 (Henkan) → IME オン"

# 無変換キー → IME オフ
gsettings set "$CUSTOM_SCHEMA:$deactivate_path" name 'IME オフ (無変換)'
gsettings set "$CUSTOM_SCHEMA:$deactivate_path" command 'fcitx5-remote -c'
gsettings set "$CUSTOM_SCHEMA:$deactivate_path" binding 'Muhenkan'
ok "無変換 (Muhenkan) → IME オフ"

# ─── 7. Fcitx5 再起動 ────────────────────────────────────
if $FCITX5_WAS_RUNNING || fcitx5-remote --check &>/dev/null; then
    info "Fcitx5 を再起動中..."
    fcitx5 -d &>/dev/null &
    disown
    sleep 1
    if fcitx5-remote --check &>/dev/null; then
        ok "Fcitx5 を再起動"
    else
        warn "Fcitx5 の起動を確認できません。手動で再起動してください。"
    fi
fi

# ─── 完了 ────────────────────────────────────────────────
echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok   "Fcitx5 + Mozc のセットアップ完了!"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "キーボードレイアウト: ${KB_LAYOUT}"
info ""
info "IME 切り替え (GNOME ショートカット):"
info "  変換 (Henkan)   → IME オン  (fcitx5-remote -o)"
info "  無変換 (Muhenkan) → IME オフ (fcitx5-remote -c)"
info ""
info "Mozc キーマップ: MS-IME ベース"
info "  - Henkan / Muhenkan エントリ削除済み"
info "  - 入力モードは常にひらがな"
info ""
info "Fcitx5 設定:"
info "  - ActivateKeys / DeactivateKeys 無効化"
info "  - 全ウィンドウで IME 状態を共有 (ShareInputState=All)"
echo ""
if [[ "$current_im" != "fcitx5" ]]; then
    warn "im-config を変更しました。ログアウト→ログインで反映されます。"
    echo ""
fi
