# ubuntu-setup

Ubuntu環境のセットアップスクリプト集。

## 共通スクリプト

### claude-root-patch.sh

Claude Codeでsudoをパスワードなしで使えるようにするセットアップスクリプト。
sudo-rs環境でも動作する。

#### 仕組み

`claudex`コマンドを`~/.bashrc`に追加する。
`claudex`実行時に一時的なNOPASSWD sudoersエントリを作成し、Claude終了時に自動削除する。

#### 前提条件

- Claude Codeがインストール済み
- sudoが使えるユーザーであること

#### 使い方

```bash
bash claude-root-patch.sh   # claudex関数を.bashrcに追加
source ~/.bashrc
claudex                      # Claude Code起動（sudo パスワード不要）
```

初回の`claudex`実行時にsudoパスワードを1回だけ入力する。以降Claude内のsudoはすべてパスワード不要になる。

### setup-clipboard-history.sh

GNOME拡張「Clipboard History」をインストールし、左右キーでの隣接メニュー移動をブロックするパッチを適用するスクリプト。

#### やること

1. **GNOME Extensions アプリ** がなければインストール
2. **Clipboard History** 拡張がなければインストール
3. 左右キーで隣のトレイアイコンメニューに移動しないようブロック
4. dconf設定を適用（`Super+V` でトグル）

#### 使い方

```bash
bash setup-clipboard-history.sh
```

### fix-luks-keyboard.sh

LUKS解除画面（initramfs）のキーボードレイアウトをUSに変更するスクリプト。

#### やること

1. `/etc/default/keyboard` の `XKBLAYOUT` を `"us"` に変更
2. `update-initramfs -u` で initramfs を再生成

#### 注意

- コンソール (tty) のキーボードレイアウトも US になる
- GNOME デスクトップの入力ソース設定には影響しない
- 反映には再起動が必要

#### 使い方

```bash
sudo bash fix-luks-keyboard.sh
```

### setup-gnome-desktop.sh

gnome-tweaks をインストールし、GNOME デスクトップの各種設定を行うスクリプト。

#### やること

1. **gnome-tweaks** をインストール（未インストールの場合）
2. キーボードのリピート速度（repeat-interval=16ms）と長押し判定時間（delay=232ms）を設定

#### 使い方

```bash
bash setup-gnome-desktop.sh
```

### setup-pointing-devices.sh

マウス・トラックボール・タッチパッド・トラックポイントのポインター速度・加速度・スクロール速度を対話的に調整するウィザード。

#### やること

1. デバイス選択（マウス / タッチパッド / トラックポイント）
2. ポインター速度・加速プロファイルをリアルタイムで試行→確定
3. タッチパッド / トラックポイントのスクロール速度を libinput-config で調整
4. `pointing-wizard` エイリアスを `~/.bashrc` に登録

#### 対応環境

- Ubuntu 24.04+ / GNOME / Wayland
- ポインター調整: gsettings（即時反映）
- スクロール調整: libinput-config（再ログインで反映）

#### 使い方

```bash
bash setup-pointing-devices.sh   # 通常のウィザード
pointing-wizard                  # エイリアス登録後
```

### setup-fcitx5.sh

Fcitx5 + Mozc の日本語入力環境を構築し、どの状況でも変換/無変換キーで IME のオンオフを切り替え可能にするスクリプト。

#### やること

1. **fcitx5 / fcitx5-mozc** をインストール（未インストールの場合）
2. **im-config** で fcitx5 をデフォルト入力メソッドに設定
3. 物理キーボードレイアウトを自動検出して fcitx5 プロファイルを設定（例: US → `keyboard-us` + `mozc`）
4. Fcitx5 ホットキー設定:
   - ActivateKeys / DeactivateKeys を無効化
   - ShareInputState を All に設定（全ウィンドウで IME 状態を共有）
5. Mozc キーマップ設定:
   - MS-IME ベース
   - Henkan / Muhenkan エントリを削除
   - 入力モード切替を削除（常にひらがなモード）
6. GNOME カスタムキーボードショートカット:
   - 変換 (Henkan) → `fcitx5-remote -o`（IME オン）
   - 無変換 (Muhenkan) → `fcitx5-remote -c`（IME オフ）

#### なぜ GNOME ショートカット経由か

Fcitx5 のホットキーは入力コンテキスト（テキストフィールド）がある場合のみ動作する。GNOME カスタムショートカットはコンポジター（Mutter）レベルで処理されるため、デスクトップ上やテキストフィールド外でも IME の切り替えが可能になる。

#### 使い方

```bash
bash setup-fcitx5.sh
```

im-config の変更はログアウト→ログインで反映される。

### allow-short-password.sh

PAMのパスワードポリシーを緩和し、4桁の数字など短いパスワードを設定可能にするスクリプト。

#### やること

1. `/etc/security/pwquality.conf` にminlen=4等の緩和設定を追記
2. `/etc/pam.d/common-password` で `pam_pwquality.so` を無効化（最小6文字がハードコードされているため）
3. `pam_unix.so` に `minlen=4` を設定し、`obscure` / `use_authtok` を除去

#### 使い方

```bash
sudo bash allow-short-password.sh
passwd   # 4桁の数字パスワードを設定可能
```

### setup-auto-darkmode.sh

日の出・日没に基づいて GNOME のダークモード/ライトモードを自動切替する systemd ユーザータイマーをセットアップするスクリプト。

#### 仕組み

- 緯度経度から日の出・日没時刻を Python 標準ライブラリ（外部依存なし）で天文計算
- systemd ユーザータイマーが 5 分ごとにチェックし、`gsettings` で `color-scheme` を切替
- 位置情報は初回セットアップ時に IP ジオロケーション API で自動取得（確認あり）、`~/.config/auto-darkmode/location.conf` に保存
- 以降はオフラインで動作

#### ファイル構成

| ファイル | 役割 |
|---|---|
| `setup-auto-darkmode.sh` | セットアップ / アンインストール |
| `auto-darkmode/darkmode-switch.py` | 日の出/日没計算 + テーマ切替 |
| `auto-darkmode/auto-darkmode.service` | systemd ユーザーサービス |
| `auto-darkmode/auto-darkmode.timer` | 5 分間隔のタイマー |

#### 使い方

```bash
# インストール（位置情報設定 → タイマー登録 → 初回実行）
bash setup-auto-darkmode.sh

# アンインストール（タイマー停止・削除、位置情報は保持）
bash setup-auto-darkmode.sh --uninstall

# 手動で即時実行
python3 auto-darkmode/darkmode-switch.py

# タイマー状態確認
systemctl --user status auto-darkmode.timer

# 位置情報の変更
vi ~/.config/auto-darkmode/location.conf
```

### setup-tiling-thirds.sh

`Super+Left/Up/Right` でウィンドウを画面の 1/3 にタイル配置するカスタム GNOME Shell 拡張をインストールするスクリプト。

#### キーバインド

| キー | 動作 |
|---|---|
| `Super+Left` | 左 1/3 |
| `Super+Up` | 中央 1/3 |
| `Super+Right` | 右 1/3 |
| `Super+Down` | 元のサイズに復元 |

#### 使い方

```bash
bash setup-tiling-thirds.sh
```

GNOME Shell 45+ が必要。Wayland ではログアウト→ログインで反映。

### setup-tiling-edge-drag.sh

GNOME Tiling Assistant 拡張で左右エッジドラッグのみを有効にし、上下エッジのスナップを無効化するスクリプト。

#### 使い方

```bash
bash setup-tiling-edge-drag.sh
```

`tiling-assistant` 拡張がインストール済みであること。

## RX 5600 XT 専用 (`rx5600xt/`)

### setup-amdgpu-stability.sh

RX 5600 XT (RDNA1/Navi 10) GPU で発生する `ring gfx_0.0.0 timeout` エラーを修正するスクリプト。GRUB のカーネルパラメータに `amdgpu.ppfeaturemask=0xffffffff` を追加する。

#### 使い方

```bash
sudo bash rx5600xt/setup-amdgpu-stability.sh
```

反映には再起動が必要。

## X1 Carbon Gen 13 専用 (`x1-carbon-gen13/`)

ThinkPad X1 Carbon Gen 13 (OLED) 向けのセットアップスクリプト。

### fix-oled-flicker.sh

Intel xe ドライバの PSR (Panel Self Refresh) 関連パラメータをトグルし、OLEDのちらつきを制御するスクリプト。

#### 対象パラメータ

| パラメータ | 説明 |
|---|---|
| `xe.enable_psr=0` | Panel Self Refresh を無効化 |
| `xe.enable_psr2_sel_fetch=0` | PSR2 Selective Fetch を無効化 |

#### 使い方

```bash
# PSR 全無効化（ちらつき対策）
sudo bash x1-carbon-gen13/fix-oled-flicker.sh disable

# PSR 全有効化（省電力モードに戻す）
sudo bash x1-carbon-gen13/fix-oled-flicker.sh enable

# 現在の状態を確認（root不要）
bash x1-carbon-gen13/fix-oled-flicker.sh status
```

引数なしで実行した場合は `disable` として動作する。

#### 注意

- PSR 無効化によりバッテリー消費が 0.5〜1.5W 程度増加する可能性がある
- 変更の反映には再起動が必要
- 実行時に `/etc/default/grub` のバックアップを自動作成する

### fix-chrome-gesture.sh

Chrome のタッチパッド・タッチパネルでのスワイプによるナビゲーション（戻る・進む）を修正するスクリプト。

#### 問題

- **トラックパッド**: 二本指左右スワイプでナビゲーションが反応しない
- **タッチパネル**: ナビゲーション UI は出るが閾値がおかしく発動しない（Wayland + fractional scaling 環境での座標ズレ）

#### やること

`~/.local/share/applications/google-chrome.desktop` をオーバーライドし、Chrome 起動時に以下のフラグを付与:

| フラグ | 説明 |
|---|---|
| `--enable-features=TouchpadOverscrollHistoryNavigation` | トラックパッドの二本指スワイプナビ有効化 |
| `--enable-features=WaylandFractionalScaleV1` | fractional scaling の座標処理を改善 |
| `--disable-features=WaylandPerSurfaceScale` | fractional scaling でのタッチ座標ズレを修正 |

#### 使い方

```bash
# フラグを設定
bash x1-carbon-gen13/fix-chrome-gesture.sh

# 現在の設定を確認
bash x1-carbon-gen13/fix-chrome-gesture.sh status

# 元に戻す
bash x1-carbon-gen13/fix-chrome-gesture.sh revert
```

#### 注意

- 設定後 Chrome の再起動が必要（すべてのウィンドウを閉じて再度開く）
- Chrome のアップデート時にシステム `.desktop` が変わった場合は再実行が必要

### setup-brightness-restore.sh

サスペンド/レジューム時に画面の明るさを保存・復元するスクリプト。

#### 使い方

```bash
sudo bash x1-carbon-gen13/setup-brightness-restore.sh
```

### setup-fingerprint-auth.sh

sudo / polkit (GUI認証ダイアログ・ソフトウェアインストール) で指紋認証を有効にするスクリプト。

#### やること

1. `/etc/pam.d/sudo` に `pam_fprintd.so` を追加
2. `/etc/pam.d/sudo-i` に `pam_fprintd.so` を追加
3. `/etc/pam.d/polkit-1` に `pam_fprintd.so` を追加

#### 前提条件

- `fprintd` / `libpam-fprintd` がインストール済み
- 指紋が登録済み (`fprintd-enroll`)

#### 使い方

```bash
sudo bash x1-carbon-gen13/setup-fingerprint-auth.sh
```

### setup-gnome.sh

GNOME デスクトップ環境の各種設定（デフォルトからの差分のみ）を適用するスクリプト。

#### やること

1. **gnome-tweaks** がなければインストール
2. ショートカットキーの設定（`Super+Up` で最大化トグル、`Super+Down` で最小化、`Super+F` で縦最大化、`Super+E` でファイルマネージャ、`Super+T` でターミナル、メッセージトレイ無効化）
3. Dock の設定（下側配置、自動非表示、現在のワークスペースのみ、クリックでフォーカス/最小化/プレビュー、アイコンサイズ52、背景不透明度80%、ゴミ箱・マウント非表示）
4. インターフェースの設定（カーソルサイズ32、中クリック貼り付け無効化）
5. デスクトップアイコンの設定（ホームフォルダ非表示）

#### 使い方

```bash
bash x1-carbon-gen13/setup-gnome.sh
```

### setup-key-remap.sh

keyd を使用して Wayland / X11 両対応のキーリマッピングを設定するスクリプト。

#### リマッピング内容

| 変更前 | 変更後 | 備考 |
|---|---|---|
| 左 Alt (単独押し) | 無変換 (Muhenkan) | タップで無変換、ホールドで Alt |
| 右 Alt | 変換 (Henkan) | |
| CapsLock | F13 | Shift+CapsLock で CapsLock トグル |
| Copilot ボタン (Meta+Shift+F23) | Alt | |

#### 前提条件

- Linux kernel 6.14 以降（F23 スキャンコードのサポート）

#### 使い方

```bash
sudo bash x1-carbon-gen13/setup-key-remap.sh
```
