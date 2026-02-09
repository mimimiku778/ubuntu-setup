# ubuntu-setup

Ubuntu環境のセットアップスクリプト集。

## claude-root-patch.sh

Claude Codeでsudoをパスワードなしで使えるようにするセットアップスクリプト。
sudo-rs環境でも動作する。

### 仕組み

`claudex`コマンドを`~/.bashrc`に追加する。
`claudex`実行時に一時的なNOPASSWD sudoersエントリを作成し、Claude終了時に自動削除する。

### 前提条件

- Claude Codeがインストール済み
- sudoが使えるユーザーであること

### 使い方

```bash
bash claude-root-patch.sh   # claudex関数を.bashrcに追加
source ~/.bashrc
claudex                      # Claude Code起動（sudo パスワード不要）
```

初回の`claudex`実行時にsudoパスワードを1回だけ入力する。以降Claude内のsudoはすべてパスワード不要になる。

## setup-clipboard-indicator.sh

GNOME拡張「Clipboard Indicator」をインストールし、トップバー中央に透明配置＋ショートカットキー専用運用にカスタマイズするスクリプト。

### やること

1. **GNOME Extension Manager** がなければインストール
2. **Clipboard Indicator** 拡張がなければ `gext` 経由でインストール（`pipx` も必要に応じて導入）
3. `addToStatusArea` をパッチしてインジケーターを **トップバー中央（時計の左側）** に配置
4. display-mode=3 (Neither) の挙動を `this.hide()` → **透明1px** に変更（メニューが出せるように）
5. dconf設定を適用（`display-mode=3`, `Super+V` でトグル）

### 特徴

- パターンマッチベースのパッチなので拡張のバージョンアップにもある程度追従可能
- 適用済みチェックにより二重適用を防止
- 毎回バックアップを作成（`.bak.YYYYMMDDHHmmSS`）
- 拡張がアップデートされてパッチが消えた場合は再実行するだけで再適用できる

### 使い方

```bash
bash setup-clipboard-indicator.sh
```

実行後、GNOME Shellを再起動して反映:
- **X11**: `Alt+F2` → `r` → Enter
- **Wayland**: ログアウト → ログイン

`Super+V` でクリップボード履歴を表示。
