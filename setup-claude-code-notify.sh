#!/bin/bash
# Claude Code — 入力待ち時にGNOME通知+サウンドを送るフックを設定
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOK_SCRIPT="$CLAUDE_DIR/notify-hook.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
SOUND_FILE="$CLAUDE_DIR/notify-sound.oga"

mkdir -p "$CLAUDE_DIR"

# --- 通知音ファイル (カスタム音がなければデフォルトをコピー) ---
if [[ ! -f "$SOUND_FILE" ]]; then
  cp /usr/share/sounds/Yaru/stereo/message.oga "$SOUND_FILE"
  echo "Sound: copied default to $SOUND_FILE (replace with custom .oga/.ogg if desired)"
fi

# --- hook script ---
cat > "$HOOK_SCRIPT" << 'HOOK'
#!/bin/bash
# Claude Code notification hook - shows last assistant output in GNOME notification
input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

body=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  body=$(jq -rs '
    [.[] | select(.type == "assistant")] | last
    | .message.content // [] | map(select(.type == "text") | .text) | join(" ")
  ' "$transcript" 2>/dev/null \
    | tr '\n' ' ' \
    | sed 's/  */ /g' \
    | cut -c1-200)
fi

if [[ -z "$body" ]]; then
  body=$(echo "$input" | jq -r '.message // "入力を待っています"')
fi

notify-send -i utilities-terminal "Claude Code" "$body" 2>/dev/null

# 通知音を再生 (非同期)
SOUND="$HOME/.claude/notify-sound.oga"
if [[ -f "$SOUND" ]]; then
  canberra-gtk-play -f "$SOUND" &>/dev/null &
fi
HOOK
chmod +x "$HOOK_SCRIPT"

# --- settings.json (hook登録) ---
hook_config='{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash '"$HOOK_SCRIPT"'"
          }
        ]
      }
    ]
  }
}'

if [[ -f "$SETTINGS" ]]; then
  # 既存設定にマージ
  merged=$(jq -s '.[0] * .[1]' "$SETTINGS" <(echo "$hook_config"))
  echo "$merged" > "$SETTINGS"
else
  echo "$hook_config" | jq . > "$SETTINGS"
fi

echo "Done: $HOOK_SCRIPT installed, $SETTINGS updated"
