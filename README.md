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

### setup-clipboard-indicator.sh

GNOME拡張「Clipboard Indicator」をインストールし、トップバー中央に透明配置＋ショートカットキー専用運用にカスタマイズするスクリプト。

#### やること

1. **GNOME Extension Manager** がなければインストール
2. **Clipboard Indicator** 拡張がなければ `gext` 経由でインストール（`pipx` も必要に応じて導入）
3. `addToStatusArea` をパッチしてインジケーターを **トップバー中央（時計の左側）** に配置
4. display-mode=3 (Neither) の挙動を `this.hide()` → **透明1px** に変更（メニューが出せるように）
5. dconf設定を適用（`display-mode=3`, `Super+V` でトグル）

#### 使い方

```bash
bash setup-clipboard-indicator.sh
```

実行後、GNOME Shellを再起動して反映:
- **X11**: `Alt+F2` → `r` → Enter
- **Wayland**: ログアウト → ログイン

`Super+V` でクリップボード履歴を表示。

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

Chrome のタッチパッド・タッチパネルでの二本指スワイプナビゲーション（戻る・進む）を修正するスクリプト。

#### やること

`~/.local/share/applications/google-chrome.desktop` をオーバーライドし、Chrome 起動時に以下のフラグを付与:

- `--enable-features=TouchpadOverscrollHistoryNavigation,WaylandFractionalScaleV1`
- `--disable-features=WaylandPerSurfaceScale`

#### 使い方

```bash
bash x1-carbon-gen13/fix-chrome-gesture.sh           # フラグを設定
bash x1-carbon-gen13/fix-chrome-gesture.sh status     # 現在の設定を確認
bash x1-carbon-gen13/fix-chrome-gesture.sh revert     # 元に戻す
```

設定後、Chrome の全ウィンドウを閉じて再起動が必要。

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

### setup-key-remap.sh

keyd を使用して Wayland / X11 両対応のキーリマッピングを設定するスクリプト。

#### リマッピング内容

| 変更前 | 変更後 |
|---|---|
| 右 Alt | 変換 (Henkan) |
| CapsLock | 無変換 (Muhenkan) |
| Copilot ボタン (Meta+Shift+F23) | CapsLock |

#### 前提条件

- Linux kernel 6.14 以降（F23 スキャンコードのサポート）

#### 使い方

```bash
sudo bash x1-carbon-gen13/setup-key-remap.sh
```
