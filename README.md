# Dreamcast-Dev-Tools-for-BBA — ブロードバンドアダプターで Dreamcast 実機開発・デバッグ

Dreamcast の **ブロードバンドアダプター（BBA, HIT-0400 / HIT-0401）** を使って、
Windows PC から実機へプログラムを LAN 経由で転送・実行し、`printf` のログ表示、
PC 上のファイル読み書き、CD イメージの差し替え、**GDB によるソースレベルデバッグ**までを
PowerShell スクリプト数本で行えるようにする環境です。

CD-R を毎回焼く必要がなくなり、「ビルド → 数秒で実機起動 → ログを見る → 直す」の
サイクルを回せます。

```
 ┌──────────── Windows PC ────────────┐            ┌──────── Dreamcast ────────┐
 │ DreamSDK (KallistiOS / sh-elf-gcc)  │            │  dcload-ip（起動ディスク）  │
 │                                     │   LAN      │        ↓ 受信・実行          │
 │ dc_run.ps1 ─ dc-tool-ip ────────────┼── UDP ────►│  あなたのプログラム (.elf)   │
 │   ├ コンソール（printf 表示）  ◄─────┼────────────┤  printf()                  │
 │   ├ /pc/ ファイルサーバー     ◄─────┼────────────┤  fopen("/pc/...")           │
 │   ├ /cd/ ISO リダイレクト     ◄─────┼────────────┤  fopen("/cd/...")           │
 │   └ GDB ブリッジ :2159              │            │  gdb_init() の GDB スタブ   │
 │ dc_gdb.ps1 ─ sh-elf-gdb ──TCP──┘    │            │                            │
 └─────────────────────────────────────┘            └────────────────────────────┘
```

---

## 目次

1. [必要なもの](#1-必要なもの)
2. [フォルダ構成](#2-フォルダ構成)
3. [セットアップ](#3-セットアップ)
4. [ネットワーク構成](#4-ネットワーク構成)
5. [dcload-ip 起動ディスクを作る](#5-dcload-ip-起動ディスクを作る)
6. [プログラムを転送して実行する](#6-プログラムを転送して実行する)
7. [PC のファイルを使う（/pc/）](#7-pc-のファイルを使うpc)
8. [CD イメージを焼かずに使う（/cd/ リダイレクト）](#8-cd-イメージを焼かずに使うcd-リダイレクト)
9. [GDB でデバッグする](#9-gdb-でデバッグする)
10. [自分のプロジェクトで使う](#10-自分のプロジェクトで使う)
11. [トラブルシューティング](#11-トラブルシューティング)
12. [制限事項・注意](#12-制限事項注意)
13. [動作確認状況](#13-動作確認状況)
14. [ライセンス・参考資料](#14-ライセンス参考資料)

---

## 1. 必要なもの

### ハードウェア

| 物 | 説明 |
|---|---|
| Dreamcast 本体 | どのモデルでも可 |
| ブロードバンドアダプター | **HIT-0400 / HIT-0401**（RTL8139 系, 10/100 Mbps）。モデムの代わりに本体背面へ装着 |
| （代替）LAN アダプター HIT-0300 | dcload-ip は対応しますが 10 Mbps で転送が約 1 MB/s と遅く、不安定になりやすい |
| LAN ケーブル | ルーター/スイッチ経由、または PC と直結（最近の NIC は自動 MDI-X なのでストレートで可） |
| dcload-ip を起動する手段 | 次のどれか：**CD-R**（MIL-CD 対応の本体）、**GDEMU / MODE / USB-GDROM** などの光学ドライブエミュレーター |
| Windows PC | Windows 10 / 11、有線 LAN 推奨 |

### ソフトウェア

| 物 | 入手先 | 備考 |
|---|---|---|
| **DreamSDK R4** | <https://dreamsdk.org/> | KallistiOS、sh-elf-gcc、`dc-tool-ip`、`sh-elf-gdb`、dcload-ip のソースとビルド済みバイナリ、mkisofs / cdi4dc が全部入っています。既定のインストール先 `C:\DreamSDK` を想定 |
| CD-R 書き込みソフト（CD-R で起動する場合） | DiscJuggler、ImgBurn など | `.cdi` を焼きます |

> DreamSDK を `C:\DreamSDK` 以外に入れた場合は、環境変数 `DREAMSDK_HOME` にそのパスを設定してください。

この環境は次のバージョンで作成しました：DreamSDK R4 (4.0.11)、KallistiOS 2.3.0、dc-tool-ip / dcload-ip 2.0.3、GDB 16.3。

---

## 2. フォルダ構成

```
Dreamcast-Dev-Tools-for-BBA/
├─ README.md                    このファイル
├─ config/
│   └─ bba.config.example.ps1   設定の雛形（bba.config.ps1 にコピーして使う）
├─ scripts/
│   ├─ _common.ps1              共通設定（DreamSDK のパス、設定読み込み）
│   ├─ make_dcload_disc.ps1     dcload-ip 起動ディスク(.cdi)を作る
│   ├─ dc_run.ps1               .elf を転送して実行、コンソール/ファイルサーバー
│   ├─ dc_gdb.ps1               GDB 付きで実行（dc-tool-ip + sh-elf-gdb）
│   └─ dc_reset.ps1             疎通確認(ping)とリセット
├─ gdb/
│   └─ dreamcast.gdbinit        GDB 設定（SH4、タイムアウト等）
└─ sample/hello_bba/            動作確認用サンプル
    ├─ main.c                   printf / /pc/ 読み書き / GDB / START で dcload に戻る
    ├─ Makefile                 KallistiOS 標準の Makefile
    ├─ build.ps1                PowerShell からビルド
    └─ data/hello.txt           Dreamcast から読むファイル
```

`build/`・`out/`・`config/bba.config.ps1` は `.gitignore` 済みです。

---

## 3. セットアップ

### 3-1. DreamSDK をインストール

1. <https://dreamsdk.org/> から DreamSDK R4 をダウンロードしてインストール。
2. **DreamSDK Manager** を一度起動し、KallistiOS がインストール済みであることを確認。

確認（PowerShell）：

```powershell
C:\DreamSDK\opt\toolchains\dc\bin\dc-tool-ip.exe -h
```

`dc-tool-ip 2.0.3 ...` と使い方が表示されれば OK です。

### 3-2. このリポジトリを取得

```powershell
git clone https://github.com/iwa-kasoutuuuuuka/Dreamcast-Dev-Tools-for-BBA.git
cd Dreamcast-Dev-Tools-for-BBA
```

### 3-3. スクリプトの実行を許可

PowerShell の実行ポリシーで止まる場合は、そのウィンドウだけ許可します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

### 3-4. 設定ファイルを作る

```powershell
Copy-Item config\bba.config.example.ps1 config\bba.config.ps1
notepad config\bba.config.ps1
```

`$DcIp` に Dreamcast の IP アドレスを書きます（dcload-ip の画面に表示される値。
[4章](#4-ネットワーク構成) を参照）。各スクリプトは `-Ip 192.168.x.y` でも上書きできます。

### 3-5. Windows ファイアウォール

初回に `dc-tool-ip.exe` を実行したとき「アクセスを許可しますか」と出たら
**プライベートネットワーク** を許可してください。
許可しないと、転送は始まってもコンソール出力やファイル要求が届きません。

手動で許可する場合（管理者 PowerShell）：

```powershell
New-NetFirewallRule -DisplayName "dc-tool-ip" -Direction Inbound -Action Allow `
  -Program "C:\DreamSDK\opt\toolchains\dc\bin\dc-tool-ip.exe" -Profile Private
```

---

## 4. ネットワーク構成

### パターン A：ルーター経由（DHCP）— おすすめ

```
PC ──┐
     ├── ルーター / スイッチ（DHCP あり）
DC ──┘
```

- dcload-ip は既定で **DHCP** で IP を取得します（ディスク作成時に `-Ip` を付けない場合）。
- 起動すると画面に取得した IP が表示されるので、それを `config\bba.config.ps1` の `$DcIp` に書きます。
- 毎回同じ IP にしたい場合は、ルーターの「DHCP 固定割り当て」で BBA の MAC アドレス
  （dcload-ip の画面に表示）に IP を割り当てると楽です。

### パターン B：PC と直結（固定 IP）

```
PC ─── LAN ケーブル ─── DC
```

DHCP サーバーが無いので、両方に固定 IP を設定します。

1. dcload-ip を固定 IP 版で作る：
   ```powershell
   .\scripts\make_dcload_disc.ps1 -Ip 192.168.10.2
   ```
2. PC の有線 LAN アダプターに同じサブネットの固定 IP を設定：
   「設定 → ネットワークとインターネット → イーサネット → IP 割り当て → 手動」で
   IP `192.168.10.1`、サブネットマスク `255.255.255.0`（ゲートウェイは空欄）。
3. `config\bba.config.ps1` に `$DcIp = '192.168.10.2'`。

> Wi-Fi でインターネットに繋いだまま、有線 LAN だけ Dreamcast 用にする使い方ができます。

### 疎通確認

dcload-ip を起動した状態で：

```powershell
.\scripts\dc_reset.ps1
```

`answers ping` と出れば通信できています。

---

## 5. dcload-ip 起動ディスクを作る

dcload-ip は Dreamcast 側で動く小さなローダーで、PC からのプログラム転送を待ち受けます。
DreamSDK に入っているビルド済み dcload-ip から起動ディスクを作ります。

```powershell
# DHCP 版（パターン A）
.\scripts\make_dcload_disc.ps1

# 固定 IP 版（パターン B）。DreamSDK の dcload-ip ソースを build\ にコピーして再ビルドします
.\scripts\make_dcload_disc.ps1 -Ip 192.168.10.2

# Audio/Data 形式も作る（読めない CD-R ドライブがある場合に）
.\scripts\make_dcload_disc.ps1 -AudioData
```

出力：

| ファイル | 内容 |
|---|---|
| `out\dcload-ip.cdi` | Data/Data 形式のセルフブートディスク |
| `out\dcload-ip_AD.cdi` | `-AudioData` 指定時。Audio/Data 形式（古典的なセルフブート形式） |

### 起動のしかた

- **CD-R**：`.cdi` を DiscJuggler / ImgBurn で焼き、BBA を付けた Dreamcast に入れて電源 ON。
  （MIL-CD 非対応の後期型本体は CD-R から起動できません。その場合は ODE を使います。）
- **GDEMU / MODE など**：`.cdi` を SD カードにコピーしてメニューから起動。

起動すると dcload-ip の画面に **バージョン、BBA の MAC アドレス、IP アドレス、状態（idle）** が出ます。
この画面のまま PC 側からプログラムを送ります。

> 一度焼けば、プログラムを変えても焼き直しは不要です。

---

## 6. プログラムを転送して実行する

### 6-1. サンプルをビルド

```powershell
.\sample\hello_bba\build.ps1          # 通常ビルド
.\sample\hello_bba\build.ps1 -Debug   # -g -O0 + GDB スタブ入り（9章で使う）
```

### 6-2. 実行

```powershell
.\scripts\dc_run.ps1 .\sample\hello_bba\hello_bba.elf
```

PC 側の表示例：

```
dc-tool-ip -t 192.168.1.200 -x ...\hello_bba.elf
/pc/ = H:\   (e.g. this ELF's folder is /pc/work/Dreamcast-Dev-Tools-for-BBA/sample/hello_bba)
...
Sending data ...
Executing at <0x8c010000>
[hello_bba] KOS 2.3.0 ..., dcload type 1 (1 = dcload-ip)
[hello_bba] host file says: Hello Dreamcast, this text was read from the PC ...
[hello_bba] wrote /pc/.../data/from_dreamcast.txt
[hello_bba] frame 0
[hello_bba] frame 60
```

- Dreamcast 画面に「Hello from the BBA!」が出ます。
- **START ボタン**でプログラムが `return 0` し、**dcload-ip に戻ります**。電源を切らずに次の転送ができます。
- PC 側は `Ctrl+C` で dc-tool-ip を止めます（Dreamcast 側のプログラムは動き続けます）。

### 6-3. dc_run.ps1 のオプション

| オプション | 説明 |
|---|---|
| `-Ip <IP>` | Dreamcast の IP（設定ファイルより優先） |
| `-Fast` | `-f`：FIFO 待ちを無くして高速転送（パケットロスが出る環境では外す） |
| `-Log <file>` | コンソール出力をファイルにも保存 |
| `-Iso <file.iso>` | ISO を Dreamcast の `/cd/` として見せる（8章） |
| `-CdDir <folder>` | フォルダから一時 ISO を作って `/cd/` として見せる（8章） |
| `-Gdb` | GDB サーバー（ポート 2159）を開く（普通は `dc_gdb.ps1` を使う） |
| `-PcRoot <dir>` | `/pc/` にするドライブを選ぶ（既定は ELF のあるドライブ。7章） |

`config\bba.config.ps1` の `$DcToolExtraArgs` に書いた引数は毎回追加されます（例：`@('-f')`）。

### 6-4. 転送速度の目安

dcload-ip 2.0.3 の資料によると、BBA で約 4.3〜5.5 MB/s（`-f` なし/ありの理想値）。
10 MB の ELF でも数秒で起動します。LAN アダプター（HIT-0300）は約 1 MB/s です。

---

## 7. PC のファイルを使う（/pc/）

dc-tool-ip 起動中は、Dreamcast のプログラムから **`/pc/` 以下で PC のファイルを読み書き**できます。
アセットを CD に焼かずに試せるほか、ログやスクリーンショットを PC に保存するのにも使えます。

```c
FILE *f = fopen("/pc/work/game/data/stage1.bin", "rb");   /* 読み込み */
FILE *o = fopen("/pc/work/game/log.txt", "w");            /* 書き込みも可 */
```

### Windows 版の対応関係（重要）

Windows 版 dc-tool-ip には Linux/macOS 版にある `-m`（マップ）/`-c`（chroot）が**ありません**。
`/pc/<パス>` は **dc-tool-ip を起動したカレントドライブのルート** からのパスになります。

| Dreamcast 側 | PC 側（カレントドライブが H: のとき） |
|---|---|
| `/pc/work/game/a.bin` | `H:\work\game\a.bin` |

- `dc_run.ps1` は ELF のあるフォルダに移動してから dc-tool-ip を起動するので、**ELF と同じドライブ**が `/pc/` になります。別ドライブにしたいときは `-PcRoot`。
- 起動時に `this ELF's folder is /pc/...` と、ELF のフォルダの `/pc/` パスを表示します。
- サンプルの `build.ps1` はこのパスを自動計算し、`HOST_DIR` としてプログラムに埋め込んでいます（`main.c` 参照）。
- ドライブ全体が見えるので、**信頼できるネットワークでだけ**使ってください。

---

## 8. CD イメージを焼かずに使う（/cd/ リダイレクト）

`-i <ISO>` を付けると、Dreamcast の **`/cd/`（GD-ROM / CD 読み込み）が PC 上の ISO に置き換わります**。
ゲーム本体のディスク読み込み処理をそのまま、焼かずに実機で試せます。

```powershell
# ISO を指定
.\scripts\dc_run.ps1 game.elf -Iso game.iso

# ディスクに入れるフォルダを指定（一時 ISO を build\cdredir.iso に作成）
.\scripts\dc_run.ps1 game.elf -CdDir .\cd_root
```

- 読み込み速度は LAN 速度になります（実ドライブより速い場面も遅い場面もあります）。
  読み込みタイミングに依存する不具合の確認は、最後に実ディスクでも行ってください。
- CDDA（音楽トラック）はリダイレクトされません。
- 大きなフォルダ（数百 MB）だと一時 ISO の作成に時間がかかります。何度も使うなら ISO を作っておき `-Iso` を使います。

---

## 9. GDB でデバッグする

実機上でブレークポイント、ステップ実行、変数・メモリ・レジスタの確認ができます。

### 9-1. 仕組み

1. プログラムが `gdb_init()` を呼ぶと、KallistiOS の GDB スタブが動き出して停止します。
2. スタブは dcload-ip 経由で PC の dc-tool-ip（`-g`）と通信します。
3. dc-tool-ip は TCP ポート **2159** で GDB を待ち受け、`sh-elf-gdb` が `target remote` で接続します。

### 9-2. プログラム側の準備

```c
#include <arch/gdb.h>

int main(int argc, char **argv) {
    gdb_init();        /* GDB が繋がるまでここで止まる */
    gdb_breakpoint();  /* 任意の場所で止めたいときに */
    ...
}
```

`-g -O0`（または `-Og`）でビルドすると、ソース行と変数がきれいに追えます。
サンプルは `build.ps1 -Debug` でこの状態になります（`USE_GDB` マクロ）。

### 9-3. 実行

```powershell
.\sample\hello_bba\build.ps1 -Debug
.\scripts\dc_gdb.ps1 .\sample\hello_bba\hello_bba.elf
```

- 別ウィンドウで `dc-tool-ip -g -x ...` が起動し（コンソール出力はこちら）、
- このウィンドウで `sh-elf-gdb` が `dreamcast.gdbinit` を読んで接続します。

ブレークポイントを最初から張る：

```powershell
.\scripts\dc_gdb.ps1 game.elf -Break main -Break player_update
```

### 9-4. よく使う GDB コマンド

| コマンド | 意味 |
|---|---|
| `c` | 実行再開 |
| `n` / `s` | 次の行へ（関数に入らない / 入る） |
| `b file.c:123` / `b func` | ブレークポイント |
| `bt` | 呼び出し履歴 |
| `p var` / `p *ptr` | 変数の表示 |
| `x/16wx 0x8c010000` | メモリダンプ |
| `info registers` | レジスタ一覧 |
| `kregs` | PC / PR / SR / SP だけ表示（`dreamcast.gdbinit` で定義） |
| `Ctrl+C` | 実行中のプログラムを停止 |

### 9-5. 例外（クラッシュ）が起きたとき

- GDB 接続中なら、GDB が停止位置を表示します。`bt` で原因箇所を確認。
- GDB なしでも、KallistiOS が PC のコンソールに **例外の種類とレジスタ（PC, PR など）** を出します。
  アドレスからソース行を引くには：
  ```powershell
  C:\DreamSDK\opt\toolchains\dc\sh-elf\bin\sh-elf-addr2line.exe -e game.elf -f -C 0x8c012345
  ```
- dcload-ip 自体もレジスタダンプを約 15 秒画面に表示します。

---

## 10. 自分のプロジェクトで使う

### KallistiOS 標準の Makefile を使っている場合

`dc_run.ps1` に ELF を渡すだけです。

```powershell
.\scripts\dc_run.ps1 C:\path\to\mygame.elf -Log run.log
```

DreamSDK シェル内で `make run` したい場合は、サンプルの `Makefile` のように：

```make
run: $(TARGET)
	dc-tool-ip -t $(DC_IP) -x $(TARGET)
```

### 独自のビルド（バッチファイル等）の場合

`sh-elf-gcc` で作った **`.elf`** をそのまま渡せます（`objcopy` で作った `.bin` / スクランブル済み `1ST_READ.BIN` ではなく ELF を使ってください）。
CD からアセットを読むゲームは `-CdDir` に CD のルートフォルダを渡せば、焼かずに起動できます。

```powershell
.\scripts\dc_run.ps1 .\build\game.elf -CdDir .\cd_root -Fast -Log run.log
```

### 開発ビルドだけで使いたい処理

dcload 経由で起動したかどうかは `dcload_type`（`<dc/fs_dcload.h>`）で判定できます。

```c
#include <dc/fs_dcload.h>
if (dcload_type == DCLOAD_TYPE_IP) {
    /* BBA 経由の開発起動: /pc/ にログを書く、など */
}
```

ディスク起動の製品版では `dcload_type == DCLOAD_TYPE_NONE` になり、`/pc/` は使えません。

---

## 11. トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| dcload-ip の画面で IP が `0.0.0.0` のまま | DHCP サーバーが無い。ルーター経由にするか、`-Ip` で固定 IP 版を作る（4章 B） |
| `ping` が返らない | ケーブル、BBA の装着、PC と DC が同じサブネットか確認。PC 側の VPN を切る |
| ping は通るが転送が始まらない / 止まる | ファイアウォールで dc-tool-ip を許可（3-5）。`-Fast` を外す。設定に `'-l'`（小さいパケット）を追加 |
| 転送中に dcload-ip が `link change` と表示 | 受信 FIFO あふれ。`-Fast` を外す。ギガビット NIC ⇔ 直結なら 100 Mbps 固定にすると安定することがある |
| 転送は終わるがコンソールに何も出ない | ファイアウォールの受信許可が無い。または `KOS_INIT_FLAGS` に `INIT_NO_DCLOAD` を指定している |
| `/pc/...` が開けない | パスのドライブ違い（7章）。起動時表示の `/pc/...` を確認。パスにスペースや日本語を含めない |
| `-Reset` が効かない | dcload-ip が動いている時だけ有効。プログラムが固まったら本体の電源で |
| GDB が `Remote connection closed` / 繋がらない | プログラムが `gdb_init()` を呼んでいるか確認。2159 番ポートは 1 クライアントだけ受け付けるので、前の dc-tool-ip を閉じてやり直す |
| GDB でソース行が出ない | `-g` でビルドしているか、`-O2` だと行がずれるので `-O0` / `-Og` で |
| `make_dcload_disc.ps1 -Ip` が失敗 | DreamSDK Manager で KallistiOS / dcload が導入済みか確認。`C:\DreamSDK\usr\bin\bash.exe` があるか |
| `.ps1 を読み込めません` | 実行ポリシー：`Set-ExecutionPolicy -Scope Process Bypass` |
| `DreamSDK ... not found` | DreamSDK のインストール先を `DREAMSDK_HOME` に設定 |

---

## 12. 制限事項・注意

- **Windows 版 dc-tool-ip は `/pc/` の範囲を制限できません**（ドライブのルート全体が見えます）。信頼できない LAN で起動したままにしないでください。
- dcload の通信は暗号化も認証もありません。家庭内 LAN などでだけ使ってください。
- 転送できるのは RAM（16 MB）に収まるプログラムだけです。
- `/cd/` リダイレクトは ISO9660 データのみ。CDDA は実ディスクで確認してください。
- GDB ポートは dc-tool-ip 2.0.3 では 2159 固定、同時接続は 1 つです。
- KallistiOS のネットワークスタックを自分のプログラムで使う場合も、dcload-ip 起動中は BBA を dcload と共有します（KallistiOS が自動で調整します）。
- `HOST_DIR` をパスとして埋め込むサンプルの仕組みは、パスにスペースがあると使えません。

---

## 13. 動作確認状況

| 項目 | 状況 |
|---|---|
| サンプル `hello_bba` のビルド（通常 / `-Debug`） | 確認済み（DreamSDK R4, KOS 2.3.0） |
| GDB 用デバッグ情報（`sh-elf-gdb` でソース行解決） | 確認済み |
| `make_dcload_disc.ps1`（DHCP 版 / 固定 IP 再ビルド版 / Audio/Data 版）の CDI 生成 | 確認済み |
| `dc_run.ps1` の ISO 作成と dc-tool-ip 起動（実機なし） | 確認済み |
| 実機 + BBA での転送・コンソール・`/pc/`・`/cd/`・GDB | **未確認**（実機での確認結果を Issue / PR で歓迎します） |

---

## 14. ライセンス・参考資料

### ライセンス

- このリポジトリのスクリプトとサンプルのライセンスは、公開時に `LICENSE` ファイルで指定してください（例：MIT）。
- dcload-ip / dc-tool-ip は GPL v2、KallistiOS は BSD 系ライセンスです。このリポジトリはそれらを同梱せず、DreamSDK にインストールされたものを呼び出します。
- 生成される `out\*.cdi` には dcload-ip のバイナリが含まれます。配布する場合は dcload-ip のライセンス（GPL v2）に従ってください。
- 「Dreamcast」は株式会社セガの商標です。本プロジェクトはセガとは無関係です。

### 参考資料

- KallistiOS：<https://github.com/KallistiOS/KallistiOS>
- dcload-ip（dc-tool-ip）：<https://github.com/KallistiOS/dcload-ip>
- DreamSDK：<https://dreamsdk.org/>
- DreamSDK 内のドキュメント：`C:\DreamSDK\opt\toolchains\dc\dcload\dcload-ip\README.md`、同 `NETWORK`
- KallistiOS の GDB スタブ：`C:\DreamSDK\opt\toolchains\dc\kos\kernel\arch\dreamcast\include\arch\gdb.h`

