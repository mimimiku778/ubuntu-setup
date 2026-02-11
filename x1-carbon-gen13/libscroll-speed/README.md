# libscroll-speed v2.1

ThinkPad X1 Carbon Gen 13 + Ubuntu (Wayland/GNOME) のタッチパッドスクロール速度を
非線形カーブ（Hill関数）で調整する LD_PRELOAD ライブラリ。

## 解決する問題

1. **X1 Gen 13 のスクロールが速すぎる** — libinput の生値が大きく、慣性スクロールが暴走する
2. **Chrome だけ他アプリより速い** — Chrome は同じ `wl_pointer.axis` 値でも内部倍率が高い
3. **1を修正すると Chrome 以外が遅すぎる** — 全アプリ均一では Chrome に合わせると Firefox/VSCode で5行程度しか動かない

## アーキテクチャ

```
カーネル → libinput → [libscroll-speed: Hill関数変換] → Mutter → wl_pointer.axis → 各アプリ
                                                          ↑
                                                  Chrome フォーカス時は
                                                  chrome-scroll-factor を追加適用
```

### libinput フック（コンポジタ側）

`/etc/ld.so.preload` 経由で全プロセスに読み込まれる。
Mutter（GNOME の Wayland コンポジタ）内で `libinput_event_pointer_get_scroll_value()` を
インターポーズし、Hill関数でスクロール値を変換する。

### Chrome 検出（コンポジタ側）

Mutter/GNOME Shell API（`shell_global_get` → `meta_display_get_focus_window` → `meta_window_get_pid`）
でフォーカスウィンドウの PID を取得し、`/proc/PID/exe` を readlink して
Chrome/Chromium/Electron プロセスを判定。該当する場合 `chrome-scroll-factor` を乗算する。

**注意**: VSCode は Electron ベースだが、exe パスに "electron" を含まないため検出対象外。
検証の結果、VSCode は Chrome ほどの内部倍率増幅がないことを確認済み。

### ホットリロード（v2.1 新機能）

3秒ごとに `/etc/scroll-speed.conf` の mtime をチェックし、変更があれば自動リロード。
パラメータ調整がログアウト不要で即座に反映される（.so 自体の更新は再ログイン必要）。

## 変換式

```
f(d) = base-speed × scroll-cap × x^n / (1 + x^n)  ×  d^4 / (t^4 + d^4)

x = |d| / scroll-cap
n = ramp-softness
t = low-cut（0 のとき右項は省略）
```

| 要素 | 役割 |
|---|---|
| Hill関数 `x^n/(1+x^n)` | 低速で精密、高速で頭打ちの基本カーブ |
| `ramp-softness` (n) | n>1 で低速域をさらに抑制。高速域はほぼ不変 |
| `low-cut` フィルタ | 繊細な指の動き（慣性末端）を追加抑制する n=4 高域通過 |
| `chrome-scroll-factor` | Chrome フォーカス時のみ出力に乗算 |

## パラメータ（/etc/scroll-speed.conf）

| パラメータ | 現在値 | 説明 |
|---|---|---|
| `base-speed` | 0.76 | 全体感度。max出力 = base-speed × scroll-cap |
| `scroll-cap` | 21.0 | ソフトな速度上限。d=cap で出力は max の 50% |
| `ramp-softness` | 1.65 | カーブ形状。1.0=均一減衰、>1=低速域抑制 |
| `low-cut` | 1.8 | 低域カット閾値。繊細な動き(delta<t)を抑制 |
| `discrete-scroll-factor` | 1.0 | マウスホイール倍率 |
| `chrome-scroll-factor` | 0.376 | Chrome 用コンポジタ側倍率 |

### 現在のパラメータでの出力値

| delta | Chrome以外 | Chrome (×0.376) | 体感 |
|------:|-----------:|----------------:|------|
| 2 | 0.20 | 0.08 | 繊細な指の動き |
| 5 | 1.47 | 0.55 | 位置合わせ |
| 8 | 2.85 | 1.07 | さっと指を滑らせる |
| 10 | 3.90 | 1.47 | 軽い弾き |
| 15 | 6.10 | 2.29 | 速い弾き |
| 20 | 7.76 | 2.92 | 強い弾き |

## チューニングガイド

ホットリロードにより、conf を保存→3秒で反映。

```bash
# 例: Chrome が他アプリより速い → chrome-scroll-factor を下げる
sudo sed -i 's/chrome-scroll-factor=.*/chrome-scroll-factor=0.35/' /etc/scroll-speed.conf

# 例: 全体的に遅い → base-speed を上げる（Chrome も比例して上がる）
sudo sed -i 's/base-speed=.*/base-speed=0.80/' /etc/scroll-speed.conf

# 例: Chrome は維持、他だけ速く → base-speed 上げ + chrome-scroll-factor 下げ
# Chrome 実効 = base-speed × chrome-scroll-factor を一定に保つ
```

| やりたいこと | 調整するパラメータ |
|---|---|
| 全速度域を均一に変更 | `base-speed` |
| 低速域だけ抑制/緩和 | `ramp-softness` |
| 繊細な動きだけ抑制 | `low-cut` |
| 高速弾きの天井を変更 | `scroll-cap` |
| Chrome だけ調整 | `chrome-scroll-factor` |
| Chrome 維持で他を変更 | `base-speed` + `chrome-scroll-factor`（実効値を一定に） |

## パラメータ履歴

| 版 | base-speed | scroll-cap | softness | low-cut | chrome-factor | 備考 |
|---|---|---|---|---|---|---|
| 初期 | 0.57 | 14 | 2.0 | 0 | — | 加速カーブ、過敏 |
| B2 | 0.18 | 20 | 1.0 | 0 | — | 加速感ゼロ化、低すぎ |
| D1 | 0.23 | 20 | 1.0 | 0 | — | +28%均一増、Chrome丁度/他遅い |
| E1 | 0.46 | 20 | 1.0 | 0 | 0.5 | Chrome検出+per-app factor導入 |
| **F1 (現在)** | **0.76** | **21** | **1.65** | **1.8** | **0.376** | 5パラメータ全活用、Chrome/他均衡 |

v2.1 での主な変更点:
- **ホットリロード**: conf の mtime を3秒ごと監視、変更で自動リロード
- **Mutter API 常時解決**: chrome-scroll-factor を後から有効にしても動作
- **ramp-softness 活用**: 1.65 で低速域を抑制し高速域を活かすカーブ形状に
- **low-cut 活用**: 1.8 で繊細な指の動きをさらに抑制

## ビルド・インストール

```bash
bash setup.sh          # ビルド + アトミックインストール + ld.so.preload 登録
# または
make && sudo make install
```

反映:
- **.so の更新**: ログアウト→再ログイン（gnome-shell が新しい .so を読み込む）
- **conf の変更のみ**: 保存して3秒待つだけ（ホットリロード）

## アンインストール

```bash
sudo make uninstall    # .so 削除 + ld.so.preload から除去
```

## 安全性

- インストールは**アトミック置換**（tmp + mv）。`cp` で直接上書きすると
  mmap 中のプロセスが一斉クラッシュする（実証済み）
- Chrome 以外のプロセスでは Mutter API が NULL に解決されるため per-app 機能は自動スキップ
- `chrome-scroll-factor=1.0` で Chrome 検出自体を無効化可能

## ファイル構成

```
scroll-speed.c       ライブラリ本体（libinputフック + Mutter API Chrome検出 + ホットリロード）
scroll-speed.conf    設定ファイルのテンプレート（→ /etc/scroll-speed.conf）
test-interposer.c    テストハーネス
Makefile             ビルド・インストール自動化
setup.sh             ワンコマンドセットアップスクリプト
dlsym.ver            シンボルバージョニング定義
```
