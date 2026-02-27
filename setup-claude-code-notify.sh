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
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

# Stop hook は transcript 最終書き込み前に発火するためリトライで待つ
body=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  for i in 1 2 3 4 5; do
    sleep 1
    # tac で末尾から1行ずつ読み、最後のアシスタントテキストを探す
    # jq -s はヌルバイト等でファイル全体のパースが壊れるため行単位で処理
    body=$(tac "$transcript" 2>/dev/null | while IFS= read -r line; do
      text=$(printf '%s' "$line" \
        | tr -d '\0' \
        | jq -r '
            select(.type == "assistant")
            | .message.content // [] | map(select(.type == "text") | .text) | join(" ")
            | select(length > 0)
          ' 2>/dev/null)
      if [[ -n "$text" ]]; then
        printf '%s' "$text"
        break
      fi
    done)
    [[ -n "$body" ]] && break
  done
fi

# Markdown記法を除去して通知用テキストに整形
if [[ -n "$body" ]]; then
  body=$(printf '%s' "$body" \
    | tr '\n' ' ' \
    | sed -E 's/```[^`]*```//g' \
    | sed -E 's/`([^`]+)`/\1/g' \
    | sed -E 's/\*\*([^*]+)\*\*/\1/g; s/\*([^*]+)\*/\1/g' \
    | sed -E 's/(^| )#{1,6} /\1/g' \
    | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' \
    | sed -E 's/~~([^~]+)~~/\1/g' \
    | sed -E 's/  +/ /g; s/^ //; s/ $//' \
    | cut -c1-200)
fi

if [[ -z "$body" ]]; then
  body="入力を待っています"
fi

summary=$(echo "$body" | cut -c1-60)
rest=$(echo "$body" | cut -c61-)
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
