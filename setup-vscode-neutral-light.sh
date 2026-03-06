#!/bin/bash
# Bearded Theme のホワイトバランスを GNOME Adwaita に合わせる
# 青みグレーをニュートラルグレー (R=G=B) に変換
# 対象: Bearded Theme Light / Bearded Theme HC Midnight Void

set -euo pipefail

VSCODE_USER_DIR="$HOME/.config/Code/User"

# メイン + 全プロファイルの settings.json を対象
SETTINGS_FILES=("$VSCODE_USER_DIR/settings.json")
for f in "$VSCODE_USER_DIR"/profiles/*/settings.json; do
  [ -f "$f" ] && SETTINGS_FILES+=("$f")
done

# settingsSync.ignoredSettings に workbench.colorCustomizations を追加
add_sync_ignore() {
  local file="$1"
  python3 -c "
import json, re, sys

with open('$file') as f:
    content = f.read()

cleaned = re.sub(r',(\s*[}\]])', r'\1', content)
try:
    data = json.loads(cleaned)
except json.JSONDecodeError:
    print('WARN: parse failed, skipping: $file')
    sys.exit(0)

ignored = data.get('settingsSync.ignoredSettings', [])
if 'workbench.colorCustomizations' not in ignored:
    ignored.append('workbench.colorCustomizations')
    data['settingsSync.ignoredSettings'] = ignored
    with open('$file', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print('  sync ignore 追加: $file')
else:
    print('  sync ignore 設定済み: $file')
"
}

# colorCustomizations + tokenColorCustomizations を設定
apply_colors() {
  local file="$1"
  python3 << PYEOF
import json, re

with open('$file') as f:
    content = f.read()

cleaned = re.sub(r',(\s*[}\]])', r'\1', content)
data = json.loads(cleaned)

data['workbench.colorCustomizations'] = {
    "[Bearded Theme Light]": {
        "editor.background": "#fafafa",
        "editorGutter.background": "#fafafa",
        "minimap.background": "#fafafa",
        "breadcrumb.background": "#fafafa",
        "editorGroupHeader.noTabsBackground": "#fafafa",
        "tab.activeBackground": "#fafafa",
        "tab.activeBorder": "#fafafa",
        "tab.hoverBackground": "#fafafa",
        "tab.unfocusedActiveBorder": "#fafafa",
        "tab.unfocusedHoverBackground": "#fafafa",
        "statusBar.background": "#fafafa",
        "statusBarItem.prominentBackground": "#fafafa",
        "walkThrough.embeddedEditorBackground": "#fafafa",
        "sideBar.background": "#f0f0f0",
        "sideBarSectionHeader.background": "#f0f0f0",
        "activityBar.background": "#f0f0f0",
        "activityBarBadge.foreground": "#f0f0f0",
        "statusBar.noFolderBackground": "#f0f0f0",
        "editorGroupHeader.tabsBackground": "#f0f0f0",
        "tab.inactiveBackground": "#f0f0f0",
        "panel.background": "#f5f5f5",
        "terminal.background": "#f5f5f5",
        "titleBar.activeBackground": "#e0e0e0",
        "titleBar.inactiveBackground": "#e0e0e0",
        "activityBar.border": "#dedede",
        "sideBar.border": "#dedede",
        "sideBarSectionHeader.border": "#dedede",
        "editorGroup.border": "#dedede",
        "editorGroupHeader.tabsBorder": "#dedede",
        "editorOverviewRuler.border": "#dedede",
        "panel.border": "#dedede",
        "tab.border": "#dedede",
        "tab.lastPinnedBorder": "#dedede",
        "titleBar.border": "#dedede",
        "statusBar.border": "#dedede",
        "statusBar.noFolderBorder": "#dedede",
        "panelSection.border": "#dedede",
        "panelSectionHeader.border": "#dedede",
        "editorWidget.border": "#e0e0e0",
        "notifications.border": "#dedede",
        "menu.border": "#dedede",
        "pickerGroup.border": "#dedede",
        "editorHoverWidget.border": "#dedede",
        "editorSuggestWidget.border": "#dedede",
        "merge.border": "#dedede",
        "diffEditor.border": "#dedede",
        "peekView.border": "#dedede",
        "focusBorder": "#cccccc",
        "input.border": "#cccccc",
        "dropdown.border": "#cccccc",
        "dropdown.background": "#f9f9f9",
        "dropdown.listBackground": "#f9f9f9",
        "input.background": "#f9f9f9",
        "editorHoverWidget.background": "#f9f9f9",
        "editorSuggestWidget.background": "#f9f9f9",
        "editorWidget.background": "#f9f9f9",
        "menu.background": "#f9f9f9",
        "notifications.background": "#f9f9f9",
        "notificationCenterHeader.background": "#f9f9f9",
        "keybindingLabel.background": "#f9f9f9",
        "debugExceptionWidget.background": "#f9f9f9",
        "inputValidation.errorBackground": "#f9f9f9",
        "inputValidation.infoBackground": "#f9f9f9",
        "inputValidation.warningBackground": "#f9f9f9",
        "statusBarItem.activeBackground": "#f9f9f9",
        "quickInput.background": "#fbfbfb",
        "editorStickyScrollHover.background": "#fbfbfb",
        "terminalStickyScrollHover.background": "#fbfbfb",
        "quickInputTitle.background": "#f0f0f0",
        "sideBarStickyScroll.background": "#e8e8e8",
        "panelSectionHeader.background": "#e5e5e5",
        "button.secondaryBackground": "#e5e5e5",
        "editorSuggestWidget.selectedBackground": "#e8e8e8",
        "diffEditor.unchangedCodeBackground": "#ebebeb",
        "diffEditor.unchangedRegionBackground": "#ebebeb",
        "debugToolBar.background": "#e8e8e8",
        "editorMarkerNavigation.background": "#f0f0f0",
        "statusBarItem.hoverBackground": "#e0e0e0",
        "button.secondaryHoverBackground": "#d8d8d8",
        "inputOption.hoverBackground": "#d8d8d8",
        "panelInput.border": "#d8d8d8",
        "editor.foreground": "#222222",
        "editorLink.activeForeground": "#222222",
        "sideBarSectionHeader.foreground": "#222222",
        "panelSectionHeader.foreground": "#222222",
        "settings.headerForeground": "#222222",
        "settings.settingsHeaderHoverForeground": "#222222",
        "dropdown.foreground": "#222222",
        "input.foreground": "#222222",
        "notificationCenterHeader.foreground": "#222222",
        "peekViewResult.fileForeground": "#222222",
        "peekViewTitleDescription.foreground": "#222222",
        "peekViewTitleLabel.foreground": "#222222",
        "pickerGroup.foreground": "#222222",
        "tab.inactiveForeground": "#606060",
        "tab.unfocusedInactiveForeground": "#606060",
        "panelTitle.inactiveForeground": "#606060",
        "sideBarTitle.foreground": "#606060",
        "commandCenter.foreground": "#606060",
        "editorCodeLens.foreground": "#000000b0",
        "editorLineNumber.foreground": "#787878",
        "editorLineNumber.activeForeground": "#303030",
        "editorIndentGuide.activeBackground1": "#606060cc",
        "editorIndentGuide.background1": "#60606050",
        "editorRuler.foreground": "#60606050",
        "editorWhitespace.foreground": "#60606078",
        "tree.indentGuidesStroke": "#60606088",
        "inputOption.activeBackground": "#787878",
        "input.placeholderForeground": "#787878",
        "activityBar.inactiveForeground": "#686868",
        "activityBarTop.inactiveForeground": "#787878",
        "sideBar.foreground": "#222222e0",
        "statusBar.noFolderForeground": "#222222e0",
        "statusBar.foreground": "#000000a0",
        "scrollbarSlider.background": "#22222226",
        "scrollbarSlider.hoverBackground": "#22222233",
        "scrollbarSlider.activeBackground": "#2222224d",
        "list.hoverBackground": "#9090901a",
        "list.activeSelectionBackground": "#90909033",
        "list.inactiveSelectionBackground": "#9090901f",
        "list.focusBackground": "#90909040",
        "quickInputList.focusBackground": "#90909033",
        "toolbar.hoverBackground": "#9090904d",
        "toolbar.activeBackground": "#90909080",
        "statusBar.debuggingBackground": "#e8e8e8",
        "statusBar.debuggingForeground": "#222222",
        "titleBar.activeForeground": "#222222cc",
        "titleBar.inactiveForeground": "#222222b0",
        "commandCenter.background": "#fafafa",
        "commandCenter.border": "#dedede",
        "commandCenter.activeBackground": "#fafafa61",
        "commandCenter.activeForeground": "#222222b0",
        "descriptionForeground": "#222222e0",
        "editorGhostText.foreground": "#22222288",
        "keybindingLabel.border": "#909090",
        "keybindingLabel.bottomBorder": "#909090",
        "editor.foldPlaceholderForeground": "#606060",
        "multiDiffEditor.border": "#dedede",
        "multiDiffEditor.headerBackground": "#e8e8e8"
    },
    "[Bearded Theme HC Midnight Void]": {
        "editor.background": "#1c1c1c",
        "editorGutter.background": "#1c1c1c",
        "minimap.background": "#1c1c1c",
        "breadcrumb.background": "#1c1c1c",
        "editorGroupHeader.noTabsBackground": "#1c1c1c",
        "tab.activeBackground": "#1c1c1c",
        "tab.activeBorder": "#1c1c1c",
        "tab.hoverBackground": "#1c1c1c",
        "tab.unfocusedActiveBorder": "#1c1c1c",
        "tab.unfocusedHoverBackground": "#1c1c1c",
        "statusBar.background": "#1c1c1c",
        "statusBarItem.prominentBackground": "#1c1c1c",
        "walkThrough.embeddedEditorBackground": "#1c1c1c",
        "commandCenter.background": "#1c1c1c",
        "sideBar.background": "#171717",
        "sideBarSectionHeader.background": "#171717",
        "activityBar.background": "#171717",
        "activityBarBadge.background": "#c8c8c8",
        "activityBarBadge.foreground": "#171717",
        "statusBar.noFolderBackground": "#171717",
        "editorGroupHeader.tabsBackground": "#171717",
        "tab.inactiveBackground": "#171717",
        "panel.background": "#1a1a1a",
        "terminal.background": "#1a1a1a",
        "titleBar.activeBackground": "#101010",
        "titleBar.inactiveBackground": "#101010",
        "activityBar.border": "#0d0d0d",
        "sideBar.border": "#0d0d0d",
        "sideBarSectionHeader.border": "#0d0d0d",
        "editorGroup.border": "#0d0d0d",
        "editorGroupHeader.tabsBorder": "#0d0d0d",
        "editorOverviewRuler.border": "#0d0d0d",
        "panel.border": "#0d0d0d",
        "tab.border": "#383838",
        "tab.lastPinnedBorder": "#0d0d0d",
        "titleBar.border": "#0d0d0d",
        "statusBar.border": "#0d0d0d",
        "statusBar.noFolderBorder": "#0d0d0d",
        "panelSection.border": "#0d0d0d",
        "panelSectionHeader.border": "#0d0d0d",
        "notifications.border": "#0d0d0d",
        "menu.border": "#0d0d0d",
        "pickerGroup.border": "#0d0d0d",
        "editorHoverWidget.border": "#0d0d0d",
        "editorSuggestWidget.border": "#0d0d0d",
        "merge.border": "#0d0d0d",
        "diffEditor.border": "#0d0d0d",
        "peekView.border": "#0d0d0d",
        "multiDiffEditor.border": "#0d0d0d",
        "focusBorder": "#4e4e4e",
        "input.border": "#424242",
        "dropdown.border": "#424242",
        "editorWidget.border": "#424242",
        "dropdown.background": "#232323",
        "dropdown.listBackground": "#232323",
        "input.background": "#232323",
        "editorHoverWidget.background": "#232323",
        "editorSuggestWidget.background": "#232323",
        "editorWidget.background": "#232323",
        "menu.background": "#232323",
        "notifications.background": "#232323",
        "notificationCenterHeader.background": "#232323",
        "keybindingLabel.background": "#232323",
        "debugExceptionWidget.background": "#232323",
        "statusBarItem.activeBackground": "#232323",
        "quickInput.background": "#292929",
        "quickInputTitle.background": "#171717",
        "sideBarStickyScroll.background": "#141414",
        "panelSectionHeader.background": "#2d2d2d",
        "button.secondaryBackground": "#2d2d2d",
        "editorSuggestWidget.selectedBackground": "#2d2d2d",
        "diffEditor.unchangedCodeBackground": "#141414",
        "diffEditor.unchangedRegionBackground": "#141414",
        "debugToolBar.background": "#2d2d2d",
        "editorMarkerNavigation.background": "#171717",
        "statusBarItem.hoverBackground": "#353535",
        "button.secondaryHoverBackground": "#353535",
        "inputOption.hoverBackground": "#353535",
        "panelInput.border": "#353535",
        "multiDiffEditor.headerBackground": "#2d2d2d",
        "editor.foreground": "#cecece",
        "editorLink.activeForeground": "#cecece",
        "sideBarSectionHeader.foreground": "#cecece",
        "panelSectionHeader.foreground": "#cecece",
        "settings.headerForeground": "#cecece",
        "settings.settingsHeaderHoverForeground": "#cecece",
        "dropdown.foreground": "#cecece",
        "input.foreground": "#cecece",
        "notificationCenterHeader.foreground": "#cecece",
        "peekViewResult.fileForeground": "#cecece",
        "peekViewTitleDescription.foreground": "#cecece",
        "peekViewTitleLabel.foreground": "#cecece",
        "pickerGroup.foreground": "#cecece",
        "foreground": "#b4b4b4",
        "descriptionForeground": "#cecece80",
        "sideBar.foreground": "#b4b4b4e0",
        "statusBar.foreground": "#b4b4b4a0",
        "statusBar.noFolderForeground": "#b4b4b4e0",
        "tab.inactiveForeground": "#b0b0b0",
        "tab.unfocusedInactiveForeground": "#b0b0b0",
        "panelTitle.inactiveForeground": "#b0b0b0",
        "sideBarTitle.foreground": "#b0b0b0",
        "commandCenter.foreground": "#b0b0b0",
        "editor.foldPlaceholderForeground": "#b0b0b0",
        "editorLineNumber.foreground": "#888888",
        "editorLineNumber.activeForeground": "#c8c8c8",
        "editorIndentGuide.activeBackground1": "#b0b0b0cc",
        "editorIndentGuide.background1": "#b0b0b050",
        "editorRuler.foreground": "#b0b0b050",
        "editorWhitespace.foreground": "#b0b0b078",
        "tree.indentGuidesStroke": "#b0b0b088",
        "activityBar.inactiveForeground": "#a8a8a8",
        "activityBarTop.inactiveForeground": "#b0b0b0",
        "editorGhostText.foreground": "#cecece88",
        "keybindingLabel.border": "#b0b0b0",
        "keybindingLabel.bottomBorder": "#b0b0b0",
        "scrollbarSlider.background": "#cecece26",
        "scrollbarSlider.hoverBackground": "#cecece33",
        "scrollbarSlider.activeBackground": "#cecece4d",
        "list.hoverBackground": "#5a5a5a1a",
        "list.activeSelectionBackground": "#5a5a5a33",
        "list.inactiveSelectionBackground": "#5a5a5a1f",
        "list.focusBackground": "#5a5a5a40",
        "quickInputList.focusBackground": "#5a5a5a33",
        "toolbar.hoverBackground": "#5a5a5a4d",
        "toolbar.activeBackground": "#5a5a5a80",
        "statusBar.debuggingBackground": "#2d2d2d",
        "statusBar.debuggingForeground": "#cecece",
        "titleBar.activeForeground": "#cecececc",
        "titleBar.inactiveForeground": "#cececeaa",
        "commandCenter.border": "#0d0d0d",
        "commandCenter.activeBackground": "#29292961",
        "commandCenter.activeForeground": "#b4b4b4b0"
    }
}

data['editor.tokenColorCustomizations'] = {
    "[Bearded Theme Light]": {
        "comments": "#727272"
    },
    "[Bearded Theme HC Midnight Void]": {
        "comments": "#b0b0b0"
    }
}

with open('$file', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print('  適用完了: $file')
PYEOF
}

echo "=== VSCode Neutral Theme 適用 (Light + Dark) ==="

for file in "${SETTINGS_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "処理: $file"
    apply_colors "$file"
  fi
done

add_sync_ignore "$VSCODE_USER_DIR/settings.json"

echo "完了。VSCode を Reload Window (Ctrl+Shift+P) してください。"
