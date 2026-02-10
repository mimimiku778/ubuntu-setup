#!/bin/bash
# Save/restore screen brightness across suspend/resume

BACKLIGHT="/sys/class/backlight/intel_backlight"
SAVE_FILE="/var/tmp/brightness_suspend_save"

case "$1" in
    pre)
        # Save current brightness before suspend
        cat "$BACKLIGHT/brightness" > "$SAVE_FILE"
        ;;
    post)
        # Restore brightness after resume
        if [ -f "$SAVE_FILE" ]; then
            cat "$SAVE_FILE" > "$BACKLIGHT/brightness"
        fi
        ;;
esac
