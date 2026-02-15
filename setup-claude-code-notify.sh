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
# Claude Code Stop hook - 応答完了時にGNOME通知+サウンドを送る

input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Stop hook は transcript 最終書き込み前に発火するためリトライで待つ
body=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  for i in 1 2 3 4 5; do
    sleep 1
    body=$(jq -rs '
      [.[] | select(.type == "assistant")
       | .message.content // [] | map(select(.type == "text") | .text) | join(" ")
       | select(length > 0)
      ] | last
    ' "$transcript" 2>/dev/null \
      | tr '\n' ' ' \
      | sed -E 's/```[^`]*```//g' \
      | sed -E 's/`([^`]+)`/\1/g' \
      | sed -E 's/\*\*([^*]+)\*\*/\1/g; s/\*([^*]+)\*/\1/g' \
      | sed -E 's/(^| )#{1,6} /\1/g' \
      | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' \
      | sed -E 's/~~([^~]+)~~/\1/g' \
      | sed -E 's/  +/ /g; s/^ //; s/ $//' \
      | cut -c1-200)
    [[ -n "$body" ]] && break
  done
fi

if [[ -z "$body" ]]; then
  body="入力を待っています"
fi

summary=$(echo "$body" | cut -c1-50)
rest=$(echo "$body" | cut -c51-)
if [[ -n "$rest" ]]; then
  notify-send --app-name="Claude Code" -i utilities-terminal "${summary}" "$rest" 2>/dev/null
else
  notify-send --app-name="Claude Code" -i utilities-terminal "$summary" 2>/dev/null
fi

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
    "Stop": [
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
