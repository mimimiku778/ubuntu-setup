# Adaptive Panel

OLED 焼付き防止のための GNOME Shell 拡張。パネル背景色をダーク/ライトモードおよび最大化ウィンドウのヘッダーバーに応じて動的に変更する。

## 要件

- GNOME Shell 49+
- Wayland セッション

## インストール / アンインストール

```bash
bash setup-adaptive-panel.sh             # インストール
bash setup-adaptive-panel.sh --uninstall # アンインストール
```

反映にはログアウト → ログインが必要。

## 機能

### パネル背景色の決定ロジック

| 状態 | パネル背景色 |
|------|-------------|
| ウィンドウなし / 最大化なし | テーマ色 (ライト: `#FAFAFA`, ダーク: `#131313`) |
| 最大化ウィンドウあり | ヘッダーバーの色に同期 (pick_color) |
| Overview 表示中 | テーマ色 |
| ロック画面 | テーマ色 |

### 前景色の自動切替

背景の輝度 (relative luminance) が 128 を超える場合はダーク前景 (`#3D3D3D`)、以下の場合はライト前景 (`#f2f2f2`) を適用。パネルボタン・時計・ワークスペースドットすべてに反映される。

### 色のサンプリング方法

`Shell.Screenshot.pick_color()` でパネル直下 (パネル高さ + 5px) の 3 点 (画面幅の 25%, 50%, 75%) をサンプリングし、輝度の中央値を採用する。これによりボタン等の外れ値を除外する。

## 監視シグナルとトリガー

| シグナル | ソース | 用途 |
|---------|--------|------|
| `changed::color-scheme` | `org.gnome.desktop.interface` | ダーク/ライトモード切替 |
| `notify::focus-window` | `global.display` | フォーカスウィンドウ変更 |
| `window-created` | `global.display` | 新規ウィンドウの追跡開始 |
| `restacked` | `global.display` | ウィンドウスタック順変更 (新規ウィンドウ追加含む) |
| `active-workspace-changed` | `global.workspace_manager` | ワークスペース切替 |
| `showing` | `Main.overview` | Overview 表示開始 |
| `hiding` | `Main.overview` | Overview 非表示開始 |
| `hidden` | `Main.overview` | Overview 非表示完了 |
| `notify::maximized-*` | 各ウィンドウ | 最大化/非最大化の変更 |
| `size-changed` | 各ウィンドウ | ウィンドウサイズ変更 |
| `unmanaging` | 各ウィンドウ | ウィンドウ破棄 |

## タイミング制御の設計

### デバウンス (150ms)

すべての更新は `_scheduleUpdate()` を経由し、150ms のデバウンスで集約される。短時間に複数のシグナルが発火しても 1 回の `_updatePanel()` にまとまる。

### フォローアップ再ピック (500ms + 1500ms)

フォーカス変更・最大化イベントでは `_scheduleUpdateWithFollowUp()` が使われ、150ms 後の即時更新に加えて **500ms** と **1500ms** に追加の re-pick を行う。

- **500ms**: 通常のアプリケーションでヘッダーバーの描画が完了するタイミング
- **1500ms**: VSCode 等テーマ適用が遅いアプリケーション向け (起動直後にライトテーマで描画→数百ms後にダークテーマへ切替わるケースをキャッチ)

re-pick で色が変化していれば自動的に反映される。generation カウンタにより、途中で別の更新が割り込んだ場合は古い pick 結果を破棄する。

### Overview 安定待ち (300ms)

Overview の閉じアニメーション完了後 (`hidden` シグナル)、300ms の **settling 期間** を設ける。

```
showing  → テーマ色を即時適用
hiding   → overviewClosing フラグ ON + テーマ色を維持
hidden   → settling フラグ ON (300ms)
          → settling 期間中は restacked/focus 等による pick_color をブロック
          → 300ms 後に settling OFF → _updatePanel() で正しい色を pick
```

これにより Overview 閉じ直後に restacked/focus-window シグナルが発火しても、描画が不安定なタイミングでの pick_color を防ぎ、ちらつきを回避する。

### 最大化ウィンドウの検索

アクティブワークスペースのウィンドウを `sort_windows_by_stacking()` でスタック順にソートし、最前面の最大化ウィンドウを対象とする。作成順ではなくスタック順を使うことで、複数の最大化ウィンドウが重なっている場合に正しく最前面のウィンドウの色を取得する。

## CSS スタイリング

パネル背景の明暗に応じて `adaptive-panel-light` / `adaptive-panel-dark` クラスをトグルし、`stylesheet.css` でパネルボタンの hover/active スタイルとワークスペースドットの色を制御する。色の切替には 350ms の CSS transition を適用。

## ファイル構成

```
~/.local/share/gnome-shell/extensions/adaptive-panel@ubuntu-setup/
  metadata.json    # 拡張メタデータ
  extension.js     # メインロジック
  stylesheet.css   # パネルボタン・ワークスペースドットのスタイル
```

すべて `setup-adaptive-panel.sh` が生成する。
