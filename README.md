# Dreamcast-Dev-Tools-for-BBA — ブロードバンドアダプターで Dreamcast 実機開発・デバッグ

Dreamcast の **ブロードバンドアダプター（BBA, HIT-0400 / HIT-0401）** を使って、
Windows PC から実機へプログラムを LAN 経由で転送・実行し、`printf` のログ表示、
PC 上のファイル読み書き、CD イメージの差し替え、**GDB によるソースレベルデバッグ**までを
PowerShell スクリプト数本で行えるようにする環境です。

CD-R を毎回焼く必要がなくなり、「ビルド → 数秒で実機起動 → ログを見る → 直す」の
サイクルを回せます。

さらに、自分のプログラムに組み込める小さな C ライブラリ **dcdev** と **VS Code 設定**が付いています。

| 機能 | 使い方 |
|---|---|
| 画面キャプチャを PC に保存（BMP） | L+R トリガーを押しながら A、または `dcdev_screenshot()` |
| ログを PC に自動保存 | `dc_run.ps1` が毎回 `logs\` に保存、Dreamcast 側は `dcdev_log()` |
| VMU のセーブデータを PC と行き来 | L+R+X でバックアップ、L+R+Y で書き戻し |
| アセットを PC から読み込み、編集したら即反映 | `dcdev_asset_load()` / `dcdev_asset_changed()` |
| 処理時間の計測とグラフ | `dcdev_prof_begin/end()` → `prof_report.ps1 -Html` |
| VS Code でビルド・実行・ブレークポイントデバッグ | `Ctrl+Shift+B` でビルド、`F5` で実機デバッグ |

### 新機能：自動デバッグループ `dc_auto`（2026-11）

GDEMU の GDmenu から dcload-ip を起動しておけば、あとは PC 側が全部回します。詳しくは [AUTO_DEBUG_ja.md](AUTO_DEBUG_ja.md)。

| 機能 | 使い方 | 実機 |
|---|---|---|
| 保存 → ビルド → 転送・実行 → ログ保存、を自動で繰り返す | `dc_auto.bat -Preset <名前> -Watch` | 確認済み |
| リセット不要の再送：再ビルド後に `reload.req` を作り、プログラムが自分で dcload に戻る | プリセットの `ReloadReq`（プログラム側で 1 秒ごとに確認） | 確認済み（bleem2） |
| クラッシュ箇所の自動特定：KOS の例外表示を `sh-elf-addr2line` で関数名・ソース行に（`logs\auto_*.crash.txt`、その回の ELF も保存） | 自動。後から `-Analyze <log>` | 確認済み |
| 実行中のプログラムを上書きしない：他の dc-tool-ip・実行中・再起動を見分けて待つ（ビルド中のリセットも検出）。送ったのに始まらなければリセットを頼んで送り直す。待っている間に ELF が消えたら（`sync_vmu_workbench.ps1` など）ビルドし直してから送る | 自動 | 確認済み（ビルド中の検出は未確認） |
| 実機での回帰テスト：テストごとに起動・パッド入力・スクリーンショット → 基準画像と比較して `report.html` | `-Regress <tests.ps1> [-UpdateBaseline]` | 確認済み（bleem2、基準と比較して差 0.00%） |
| 実行ごとの後処理（例：性能の CSV / グラフ化） | プリセットの `PostRun` | 確認済み（bleem2） |
| 待っている・送った・終わったを Windows の通知で知らせる。待っている間はウィンドウのタイトルに理由、状態は `logs\dc_auto_status.txt` | 自動（`-NoNotify` で通知なし） | 確認済み（2026-11-04、実機の「リセットしてください」の通知も） |
| PC 側のネットワーク設定（固定 IP・ファイアウォール）を 1 回で | 管理者で `scripts\setup_pc_network.ps1`（`-Undo` で元に戻す） | 確認済み |
| Dreamcast 2 台を別々の LAN アダプター（USB-LAN など）で：サブネットごとにファイアウォールの規則、サブネットの重なりを検出（4 章のパターン C） | 管理者で `setup_pc_network.ps1 -Adapter <名前> -PcIp 192.168.11.1` | アドレス計算は PC 上でテスト済み（2026-11-08）。2 台・USB-LAN での実機は未確認 |

プリセット（`profiles\*.ps1`）に ELF・ビルドコマンド・監視するフォルダなどを書きます。`profiles\hello_bba.ps1`（サンプル）と
`profiles\bleem2.ps1`（PS1 エミュレーター bleem2 での実例：ディスクを `/pc/` から読む、デバッグファイルを PC に保存、回帰テスト）があります。

**2026-11-05 の修正**：ビルドに失敗しても「成功」と扱って古い ELF を送っていた（コンパイラの出力も見えなかった）のを修正。
ほかに、`-Watch` 中のクラッシュは送った版の ELF で解析する、出力をすぐ書き出す dc-tool-ip でも noexec を判定する、
dc_auto を 2 つ同時に待たせても 1 つずつ送る、クラッシュ・時間切れの回を回帰テストの基準にしない、など
（[AUTO_DEBUG_ja.md](AUTO_DEBUG_ja.md)）。偽の dc-tool-ip を使って PC 上で確認済みで、実機ではまだ試していません。

> `/cd/` リダイレクト（`-i`）は KallistiOS 2.3 のプログラムでは動きません（[8 章](#8-cd-イメージを焼かずに使うcd-リダイレクト)）。

### 新機能：BBA 経由のメモリーカード（VMU）編集 `dc_vmu`（2026-11）

[VMU Workbench](https://github.com/iwa-kasoutuuuuuka/vmu-workbench)（MIT、`third_party\vmu-workbench`）を取り込み、
実機の VMU を PC で編集できるようにしました。詳しくは [11-9 章](#11-9-vmu-を丸ごと吸い出して編集するdc_vmups1)。

| 機能 | 使い方 | 実機 |
|---|---|---|
| VMU を丸ごと（128KB、ミニゲーム・コピー禁止のファイルも）PC に吸い出す | `scripts\dc_vmu.ps1 -Dump` | 確認済み（2026-11-03、PC との読み書きは 4KB ずつ） |
| イメージを VMU に書き戻す（先に今の中身を控えとして吸い出し、今の中身と違うブロックだけを書いて読み直して確認） | `dc_vmu.ps1 -Restore <img>` | 確認済み（2026-11-04、同じ内容は 0 ブロック、PS1 カードを入れ替えると 2 ブロックだけ書き、元に戻して一致） |
| bleem2 の PS1 メモリーカード（`BLEEMMC`）を `.mcr` で出し入れ（MemcardRex などで編集。VMU に入らないカードは書く前に止める） | `dc_vmu.ps1 -ExportPs1 card.mcr` / `-ImportPs1 card.mcr` | 確認済み（2026-11-04、テスト用セーブを入れたカードを実機の VMU に書き、吸い出して一致） |
| セーブの一覧・HEX / アイコン / 名前付きの値の編集（ブラウザの GUI） | `dc_vmu.ps1 -List` / `-Gui` | PC 上で確認 |

**2026-11-05 の修正**：書き戻しが途中で失敗しても、書く前の吸い出しを `_before.bin` として必ず残す（以前は次の実行で消えることがあった）。
`-ExportPs1` / `-ImportPs1` / `-List` で `-Image` を省くと、そのスロットの最新の吸い出しを使う（書き戻し前の `_before.bin` は選ばない）。

### 新機能：AI エージェント（Antigravity / Claude Code）対応（2026-11）

このフォルダをワークスペースとして開くと、エージェントが実機デバッグと VMU 編集の手順を使えます。詳しくは [12-1 章](#12-1-ai-エージェントantigravity--claude-codeで使う)。

| 内容 | Antigravity | Claude Code |
|---|---|---|
| skill `dreamcast-bba-debug`（dc_auto / dc_vmu の使い方と、実機を壊さないための決まり） | `.agent/skills/` | `.claude/skills/` |
| skill `vmu-save-analysis`（VMU Workbench のセーブ解析の手順） | `.agent/skills/` | `.claude/skills/` |
| ルール（実機に送る前・VMU に書く前は利用者に確認、など） | `.agent/rules/` | skill の中に同じ内容 |
| skill `dc-debug`（ビルド → 実行 → ログ・クラッシュ → 修正 → 再実行） | `.agent/skills/` | `.claude/skills/` |
| skill `vmu-edit`（VMU の吸い出し → 編集 → 確認 → 書き戻し） | `.agent/skills/` | `.claude/skills/` |
| MCP サーバー `dc-vmu`（VMU Workbench のツール 19 個：一覧・差分・値探し・書き換えなど） | `scripts\setup_agent_mcp.ps1` で登録 | `.mcp.json`（登録済み） |

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

> **自動デバッグループ（`dc_auto`）**：GDmenu から dcload-ip を起動しておけば、ソースを保存するたびに
> ビルド → 実機へ転送・実行 → ログ保存 → クラッシュ箇所の自動特定（addr2line）→ 再実行 までを自動で回します。
> 使い方は [AUTO_DEBUG_ja.md](AUTO_DEBUG_ja.md) を参照してください（実機 + BBA で確認済み）。

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
11. [開発支援ライブラリ dcdev](#11-開発支援ライブラリ-dcdev)
12. [VS Code・AI エージェントで使う](#12-vs-codeai-エージェントで使う)
13. [トラブルシューティング](#13-トラブルシューティング)
14. [制限事項・注意](#14-制限事項注意)
15. [動作確認状況](#15-動作確認状況)
16. [ライセンス・参考資料](#16-ライセンス参考資料)

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
├─ AUTO_DEBUG_ja.md             自動デバッグループ dc_auto の使い方
├─ dc_auto.bat                  dc_auto をダブルクリックで（引数なし = bleem2 を -Watch で）
├─ profiles/                    dc_auto のプリセット（hello_bba / bleem2 / bleem2_regress / bleem2_stats）
├─ .vscode/                     VS Code 設定（タスク、F5 デバッグ、IntelliSense）
├─ config/
│   └─ bba.config.example.ps1   設定の雛形（bba.config.ps1 にコピーして使う）
├─ scripts/
│   ├─ _common.ps1              共通設定（DreamSDK のパス、設定読み込み）
│   ├─ make_dcload_disc.ps1     dcload-ip 起動ディスク(.cdi)を作る
│   ├─ dc_run.ps1               .elf を転送して実行、コンソール/ファイルサーバー/ログ保存
│   ├─ dc_auto.ps1              自動デバッグループ（ビルド・待機・実行・クラッシュ解析・-Watch・-Regress）
│   ├─ dc_vmu.ps1               実機 VMU の吸い出し・書き戻し、PS1 メモリーカード（.mcr）の出し入れ
│   ├─ sync_vmu_workbench.ps1   VMU Workbench を third_party\ に取り込み直す
│   ├─ setup_agent_mcp.ps1      Antigravity に MCP サーバー dc-vmu を登録（-Remove で外す）
│   ├─ setup_pc_network.ps1     PC の固定 IP とファイアウォール（管理者で 1 回）
│   ├─ dc_gdb.ps1               GDB 付きで実行（dc-tool-ip + sh-elf-gdb）
│   ├─ dc_reset.ps1             疎通確認(ping)とリセット
│   ├─ dc_prepare_host.ps1      dcdev が書き込むフォルダを PC 側に作る
│   └─ prof_report.ps1          処理時間 CSV の集計と HTML グラフ
├─ lib/dcdev/                   開発支援ライブラリ（Dreamcast 側の C コード）
│   ├─ dcdev.h                  API（ここだけ読めば使えます）
│   └─ dcdev_*.c                画面キャプチャ / ログ / VMU / アセット / 計測 / ボタン操作
├─ tests/                     dcdev の PC 上テスト（KallistiOS の模擬ヘッダー付き）
│   └─ run_tests.ps1            ビルドして実行
├─ gdb/
│   └─ dreamcast.gdbinit        GDB 設定（SH4、タイムアウト等）
├─ third_party/vmu-workbench/   VMU Workbench（MIT）の写し。VMU エディタ（CLI・GUI・MCP サーバー）と転送プログラム emu/vmutransfer
├─ .agent/                      Antigravity 用の skill・ルール
├─ .claude/skills/              Claude Code 用の skill（.agent/skills と同じ内容）
├─ .mcp.json                    Claude Code 用の MCP 設定（dc-vmu）
└─ sample/hello_bba/            動作確認用サンプル（全機能を使う）
    ├─ main.c
    ├─ Makefile                 KallistiOS 標準の Makefile
    ├─ build.ps1                PowerShell からビルド（host\ フォルダも準備）
    └─ host/                    Dreamcast から /pc/ で見えるフォルダ
        ├─ assets/message.txt   画面に表示する文字列（編集すると即反映）
        ├─ screenshots/ logs/ prof/ vmu/a1/ ...   実行すると Dreamcast が書き込む
```

`build/`・`out/`・`logs/`・`config/bba.config.ps1`・サンプルの書き出しフォルダは `.gitignore` 済みです。

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

### パターン C：Dreamcast を 2 台

どちらのつなぎ方でも、2 台目用に別の IP の dcload-ip を作り、送るときに `-Ip` で台を選びます
（`dc_auto.ps1 -Ip 192.168.10.3 …`。`config\bba.config.ps1` の `$DcIp` は `-Ip` を省いたときの 1 台）。

- **ハブ 1 つ（同じサブネット）**：`PC ─ ハブ ─ DC 2 台`。2 台目は `make_dcload_disc.ps1 -Ip 192.168.10.3`。
  PC 側の設定は 1 台のときのままで使えます。
- **PC に LAN をもう 1 つ（USB-LAN など）**：台ごとにアダプターを分けます。**サブネットは必ず別にします**
  （同じ 192.168.10.x を 2 つのアダプターに付けると、Windows はどちらか一方からしか送りません）。
  ```powershell
  .\scripts\setup_pc_network.ps1 -Adapter "イーサネット" -PcIp 192.168.10.1 -DcIp 192.168.10.2
  .\scripts\setup_pc_network.ps1 -Adapter "イーサネット 3" -PcIp 192.168.11.1 -DcIp 192.168.11.2
  .\scripts\make_dcload_disc.ps1 -Ip 192.168.11.2
  ```
  アダプター名は `Get-NetAdapter` で確認。ファイアウォールの許可はサブネットごとに別の規則
  （`Dreamcast dc-tool-ip (BBA) 192.168.11.0/24` など）になり、2 回目を実行しても 1 台目の許可は残ります。
  別のアダプターが同じサブネットを使っているときは何も変えずに止まります。`-Undo` はそのアダプターのサブネットの規則だけを消し、同じサブネットを別のアダプターがまだ使っているときは規則を残します。`-DcIp` がそのサブネットの外のときや、`-PcIp` がネットワーク・ブロードキャストのアドレス（.0 や .255）のときも何も変えずに止まります。
  2026-11-08 より前に作った規則（名前が `Dreamcast dc-tool-ip (BBA)` だけのもの）は、同じサブネットで実行し直すと新しい名前に置き換わります。

2 台同時に使えるのは `dc_auto`（ビルド・送信・ログ・クラッシュ解析・`-Watch`）です。送信の排他と応答の確認は IP ごと、
dc-tool-ip は PC 側のポートを毎回別にとるので、PowerShell を 2 つ開いて別の `-Ip` で動かせます。
次のものは **1 台ずつ** 使ってください：`dc_vmu.ps1`（`logs\vmu\` の作業ファイルが 1 組）、GDB（PC のポート 2159 は 1 つ）、
bleem2 のデバッグファイル（BLEEMLOG・SHOTn・reload.req の置き場がビルドで 1 つ）。
ログの名前は秒までの日時なので、2 台がまったく同じ秒に始めると同じファイルになります。
2 台での動作はまだ実機で試していません。

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
[dcdev] host folder /pc/work/Dreamcast-Dev-Tools-for-BBA/sample/hello_bba/host
[hello_bba] KOS 2.3.0 ..., dcload type 1 (1 = dcload-ip)
[dcdev] asset message.txt <- /pc/.../host/assets/message.txt
[hello_bba] frame 0
```

- Dreamcast 画面に「Hello from the BBA!」と `host\assets\message.txt` の内容が出ます。
- PC で `message.txt` を編集して保存すると、約 0.5 秒で画面の文字が変わります。
- **L+R トリガーを押しながら A** で画面キャプチャが `host\screenshots\shot_0001.bmp` に保存されます（11章）。
- **START ボタン**でプログラムが `return 0` し、**dcload-ip に戻ります**。電源を切らずに次の転送ができます。
- PC 側は `Ctrl+C` で dc-tool-ip を止めます（Dreamcast 側のプログラムは動き続けます）。

### 6-3. dc_run.ps1 のオプション

| オプション | 説明 |
|---|---|
| `-Ip <IP>` | Dreamcast の IP（設定ファイルより優先） |
| `-Fast` | `-f`：FIFO 待ちを無くして高速転送（パケットロスが出る環境では外す） |
| `-Log <file>` | コンソール出力の保存先（既定：`logs\dc_日付_時刻.txt` に毎回自動保存） |
| `-NoLog` | コンソール出力を保存しない |
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

> **注意：KallistiOS 2.3 のプログラムでは動きません**（DreamSDK R4 の dcload-ip 2.0.3 で確認）。
> dcload-ip は GD-ROM コマンドにハンドル 0 を返し（KOS はこれを失敗として扱う）、KOS の iso9660 が使う
> DMA 読み込み（コマンド 17）にも対応していないため、CD の初期化で止まります。
> KOS 2.3 では、ディスクのデータを `/pc/` のフォルダから読むようにしてください（[AUTO_DEBUG_ja.md](AUTO_DEBUG_ja.md) の bleem2 の例）。

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

## 11. 開発支援ライブラリ dcdev

`lib/dcdev/` は、自分のプログラムに組み込んで使う Dreamcast 側の小さな C ライブラリです。
すべて `/pc/` 経由で PC とやり取りするので、**dc-tool-ip で起動したときだけ動きます**。
ディスクから起動したときは何もせずエラーを返すだけなので、製品版に残しても害はありません。

### 11-1. 組み込み方

1. `lib/dcdev/*.c` をビルドに加え、`-I lib/dcdev` を付ける（サンプルの `Makefile` 参照）。
2. PC 側に書き込み用フォルダを作る（dcload はフォルダを作れないため）：
   ```powershell
   .\scripts\dc_prepare_host.ps1 C:\work\mygame\host
   ```
   `screenshots\ logs\ assets\ prof\ vmu\a1\ … vmu\d2\` ができ、`dcdev_init()` に渡す `/pc/` パスが表示されます。
3. プログラムの最初で初期化し、毎フレーム `dcdev_poll()` を呼ぶ：
   ```c
   #include "dcdev.h"

   dcdev_init("/pc/work/mygame/host");   /* 2. で表示されたパス */
   for (;;) {
       dcdev_poll();         /* L+R トリガー + ボタンの操作を処理 */
       ...
       dcdev_prof_frame();   /* 計測を使う場合 */
       vid_waitvbl();
   }
   ```

### 11-2. ボタン操作（`dcdev_poll()`）

最初に見つかったコントローラー（通常は A ポート）で **L と R のトリガーを両方深く押したまま**、ボタンを押した瞬間に 1 回だけ動きます：

| ボタン | 動作 |
|---|---|
| A | 画面キャプチャ → `host\screenshots\shot_0001.bmp`（番号は自動で増える） |
| X | VMU（A ポートの 1 番スロット）のデータファイルを `host\vmu\a1\` にバックアップ |
| Y | `host\vmu\a1\` のファイルを VMU に書き戻す（同名ファイルは上書き） |
| B | 処理時間の集計をコンソールに表示 |

### 11-3. 画面キャプチャ

```c
dcdev_screenshot(NULL);          /* 自動番号 shot_NNNN.bmp */
dcdev_screenshot("title.bmp");   /* 名前を指定 */
```

- 今表示しているフレームバッファを 24bit BMP で保存します（Windows の標準ビューアで開けます）。
- 全ビデオモード（RGB555 / RGB565 / RGB888 / RGB0888）に対応。640×480 で約 900 KB、転送に 1 秒前後かかります（その間プログラムは止まります）。
- 作業用に Dreamcast のメモリを約 0.9 MB 一時的に使います（1 行ずつ書き出すので、画像 2 枚分は使いません）。
- 撮るのは KallistiOS の `vram_s` が指すフレームバッファです。PVR（3D）でダブルバッファ描画しているゲームでは、表示中ではなく 1 フレーム前後ずれた画面になることがあります。

### 11-4. ログ

- **PC 側**：`dc_run.ps1` はコンソール出力を毎回 `logs\dc_日付_時刻.txt` に保存します（`-NoLog` で無効）。
- **Dreamcast 側**：`dcdev_log()` は `printf` と同じ書式で、コンソールに出しつつ `host\logs\dc_log.txt` に**起動からのミリ秒付き**で追記します。
  1 行ごとに書き込むので、プログラムが固まってもそこまでのログは残ります。

```c
dcdev_log("player hp=%d stage=%d\n", hp, stage);
```

### 11-5. VMU のセーブデータを PC と行き来

```c
dcdev_vmu_backup(0, 1);    /* A ポート 1 番スロット → host\vmu\a1\ */
dcdev_vmu_restore(0, 1);   /* host\vmu\a1\ → VMU */
```

- データファイル（セーブ）だけを対象にします。VMU ミニゲームは対象外です。
- ファイルは VMU 上のデータそのまま（VMS ヘッダー込み）で保存されます。名前は VMU のファイル名（最大 12 文字）。
- 「特定のセーブデータから始めたい」テストや、セーブ破損の再現に使えます。書き戻しは同名ファイルを上書きするので注意してください。

- VMU を丸ごと移したい・ミニゲームも含めたい・中身を編集したいときは、次の `dc_vmu.ps1` を使ってください（[11-9](#11-9-vmu-を丸ごと吸い出して編集するdc_vmups1)）。

### 11-6. アセットの読み込みと即時反映

```c
size_t size;
void *tex = dcdev_asset_load("player.pvr", &size);   /* host\assets\player.pvr */
...
if (dcdev_asset_changed("player.pvr")) {             /* PC で上書き保存されたら 1 */
    free(tex);
    tex = dcdev_asset_load("player.pvr", &size);
    /* テクスチャを作り直す */
}
```

- `dcdev_asset_load()` は `host\assets\` → `/cd/` → `/rd/` の順に探します。
  開発中は PC のファイル、ディスク起動では CD のファイルが自動で使われます。
- `dcdev_asset_changed()` は PC 上のファイルの更新日時とサイズを見ます。1 ファイルにつき 0.5 秒に 1 回しか問い合わせないので、毎フレーム呼んでも大丈夫です（最大 32 ファイル）。まだ存在しないファイルも監視でき、作られた時点で「変更あり」になります。
- 更新日時は秒単位なので、**同じサイズのまま 1 秒以内に 2 回保存**すると 2 回目を見逃すことがあります。
- 画像・音・テキスト・パラメーター表などを、**プログラムを再転送せずに**調整できます。

### 11-7. 処理時間の計測

```c
dcdev_prof_begin("update");  update_game();  dcdev_prof_end("update");
dcdev_prof_begin("render");  render();       dcdev_prof_end("render");
dcdev_prof_frame();          /* 1 フレームの終わりに */
```

- 名前は文字列リテラルで渡してください（ポインターで区別します。最大 16 区間）。
- 60 フレームごとに区間ごとの平均・最大（マイクロ秒）を `host\prof\prof.csv` に書きます（`dcdev_prof_set_interval()` で変更可）。
- PC で集計：
  ```powershell
  .\scripts\prof_report.ps1 .\sample\hello_bba\host\prof\prof.csv -Html
  ```
  区間ごとの平均・最悪値・1 フレーム（16.7 ms）に対する割合を表示し、`-Html` で折れ線グラフ（`prof_report.html`）も作ります。
  60 fps 以外は `-BudgetUs 33367`（30 fps）などで基準を変えられます。

### 11-8. API 一覧

詳しくは [`lib/dcdev/dcdev.h`](lib/dcdev/dcdev.h) を見てください。

| 関数 | 内容 |
|---|---|
| `dcdev_init(host_dir)` / `dcdev_available()` | 初期化 / `/pc/` が使えるか |
| `dcdev_poll()` | L+R ボタン操作の処理 |
| `dcdev_screenshot(name)` | 画面キャプチャ（BMP） |
| `dcdev_log(fmt, ...)` / `dcdev_log_close()` | コンソール + ファイルにログ |
| `dcdev_vmu_backup(port, unit)` / `dcdev_vmu_restore(port, unit)` | VMU ⇔ PC |
| `dcdev_asset_load(name, &size)` / `dcdev_asset_changed(name)` | アセット読み込み / 変更検出 |
| `dcdev_prof_begin/end(name)`、`dcdev_prof_frame()`、`dcdev_prof_print()` | 処理時間の計測 |

---

### 11-9. VMU を丸ごと吸い出して編集する（`dc_vmu.ps1`）

dcdev を組み込まなくても使えます。GDmenu から dcload-ip を起動しておき、PC で次を実行します（PowerShell）。

```powershell
.\scripts\dc_vmu.ps1 -Dump                     # A1 の VMU → logs\vmu\a1_<日時>.bin、ファイル一覧を表示
.\scripts\dc_vmu.ps1 -ExportPs1 card.mcr       # 最新の吸い出しから bleem2 の PS1 カードを card.mcr に
#   card.mcr を MemcardRex などで編集（セーブの追加・削除・別のカードからのコピー）
.\scripts\dc_vmu.ps1 -ImportPs1 card.mcr       # → logs\vmu\a1_<日時>_ps1.bin（元の吸い出しはそのまま）
.\scripts\dc_vmu.ps1 -Restore .\logs\vmu\a1_<日時>_ps1.bin   # VMU に書き戻す（yes と入力して確定）
```

- 仕組み：`third_party\vmu-workbench\emu\vmutransfer` を `dc_auto.ps1` でビルド・転送します。プログラムは PC の
  `logs\vmu\vmu_cmd` を読んで吸い出し・書き戻しを行い、結果を `vmu_result.txt` に書いて dcload に戻ります。
  ブロック単位で読み書きするので、ファイルシステムを介さずに VMU を丸ごと移せます。
- 書き戻しの前には必ず今の VMU を `logs\vmu\<スロット>_<日時>_before.bin` に吸い出します。書いたブロックは
  1 つずつ読み直して確認します。元に戻すときは `-Restore` にこの `_before.bin` を渡してください。
- 別のスロットは `-Slot b1` など（コントローラーのポート a〜d、スロット 1〜2）。
- `-List`（一覧）と `-Gui`（ブラウザで VMU Workbench を開く：HEX 編集・アイコン・説明文・名前付きの値・差分）は
  [Node.js](https://nodejs.org/) が必要です。イメージを書き換える前の版は `logs\vmu\history\` に残ります。
- bleem2 の PS1 セーブは `BLEEMMC`（PS1 メモリーカード 128KB を圧縮したもの）に入っています。`.mcr` にすると
  PS1 用のツールがそのまま使えます。メタルスラッグ X のセーブは、VMU Workbench の構造定義でランキングなどを
  名前で書き換えられます（`node third_party\vmu-workbench\cli.js fields <img> BLEEMMC`）。
- 時計を合わせていない Dreamcast（1998 年）で bleem2 などの KallistiOS 製ソフトが書いたファイルは、日時が 1998 年と出ます
  （KallistiOS 2.3 は 1999 年以前の年を負の数のまま書くため、以前の VMU Workbench は「2064 年」と表示していました。VMU Workbench 8e8e8d8 で修正）。
- VMU Workbench を更新したら `scripts\sync_vmu_workbench.ps1 -From <vmu-workbench のフォルダ>` で取り込み直します（取り込むのは元のリポジトリでコミット済みの内容だけです。作業途中の変更は入りません）。

## 12. VS Code・AI エージェントで使う

### 12-1. AI エージェント（Antigravity / Claude Code）で使う

**Antigravity**：このリポジトリのフォルダをワークスペースとして開くと、`.agent/skills`・`.agent/rules` が読まれます。
「実機で動かしてログを見て」「VMU を吸い出して」などと頼むと、skill `dc-debug`・`vmu-edit` の手順で進めます
（以前のワークフロー `/dc-debug`・`/vmu-edit` は skill に変えました。Claude Code では `/dc-debug`・`/vmu-edit` で呼べます）。
VMU のセーブをツールで解析させるときは、MCP サーバーを 1 回だけ登録して Antigravity を再起動します。

```powershell
.\scripts\setup_agent_mcp.ps1            # ~/.gemini/config/mcp_config.json（と、あれば Antigravity IDE の ~/.gemini/antigravity-ide/mcp_config.json）に dc-vmu を追加。ほかの項目は残し、元の設定は .bak_<日時> に保存
.\scripts\setup_agent_mcp.ps1 -WhatIf    # 書き込まずに内容だけ表示
.\scripts\setup_agent_mcp.ps1 -Remove    # 外す
.\scripts\setup_agent_mcp.ps1 -Check     # 何も書かずに確認：登録・サーバーの応答（ツール数）・Antigravity が読み込んだか
```

登録は開発用 PC で確認済み（2026-11-04）：Antigravity を起動するとサーバーが起動し、ツール 19 個が `~/.gemini/antigravity/mcp/dc-vmu/` に読み込まれる。
`~/.gemini/antigravity/mcp_config.json` は読まれないので、以前の版のスクリプトで登録した場合はもう一度実行してください。

**Claude Code**：このフォルダで開くと `.claude/skills` と `.mcp.json` の `dc-vmu` が使えます（初回にサーバーの利用許可を求められます）。

- エージェントは skill の決まりに従い、実機に新しいプログラムを送る前と VMU に書き込む前（`dc_vmu.ps1 -Restore`）に確認を求めます。
  自分が起動していない dc-tool-ip は止めません。
- MCP の書き込み系ツールは、入力のイメージを上書きせず `third_party\vmu-workbench\.emu\work\` に新しいイメージを作ります。
  実機に戻すのは `dc_vmu.ps1 -Restore` です。
- Node.js が必要です。MCP と skill `vmu-save-analysis` は VMU Workbench から `sync_vmu_workbench.ps1` で取り込んだものです。

### 12-2. VS Code の設定

このフォルダを VS Code で開くと、`.vscode/` の設定がそのまま使えます。
拡張機能 **C/C++（ms-vscode.cpptools）** を入れてください（開いたときに推奨が表示されます）。

| 操作 | 内容 |
|---|---|
| `Ctrl+Shift+B` | サンプルをデバッグビルド（エラーは「問題」パネルに表示） |
| `F5` | デバッグビルド → 実機へ転送（GDB サーバー付き）→ GDB 接続。ソース上でブレークポイント、変数の確認、ステップ実行ができます |
| `Ctrl+Shift+P` → 「タスクの実行」 | `Dreamcast: run sample`、`run current ELF`、`reset`、`profile report`、`make dcload-ip disc` |

- Dreamcast の IP は `config\bba.config.ps1` から読みます。
- コンソール出力は「ターミナル」パネルに出ます。デバッグを止めたあとは、そのターミナルのタスクも止めてください（ゴミ箱アイコン）。
- 自分のプログラムで使うには、`launch.json` の `program` と、`tasks.json` のビルド・起動タスクの ELF パスを書き換えます。
- IntelliSense 用に KallistiOS のインクルードパスを `c_cpp_properties.json` に設定済みです（DreamSDK が `C:\DreamSDK` 以外なら書き換えてください）。

---

## 13. トラブルシューティング

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
| `[dcdev] ... does the screenshots folder exist?` など | PC 側にフォルダが無い。`dc_prepare_host.ps1` を実行（サンプルは `build.ps1` が自動で作る） |
| L+R+ボタンが反応しない | トリガーを奥まで押す（値 200 以上）。`dcdev_poll()` を毎フレーム呼んでいるか確認 |
| VMU の書き戻しが失敗 | VMU の空き容量不足。ファイルサイズが 512 バイトの倍数でないものは無視されます |
| F5 で GDB が繋がらない | 前回の「start sample with GDB server」タスクが残っている。ターミナルで止めてから再実行 |

---

## 14. 制限事項・注意

- **Windows 版 dc-tool-ip は `/pc/` の範囲を制限できません**（ドライブのルート全体が見えます）。信頼できない LAN で起動したままにしないでください。
- dcload の通信は暗号化も認証もありません。家庭内 LAN などでだけ使ってください。
- 転送できるのは RAM（16 MB）に収まるプログラムだけです。
- `/cd/` リダイレクトは ISO9660 データのみ。CDDA は実ディスクで確認してください。
- GDB ポートは dc-tool-ip 2.0.3 では 2159 固定、同時接続は 1 つです。
- KallistiOS のネットワークスタックを自分のプログラムで使う場合も、dcload-ip 起動中は BBA を dcload と共有します（KallistiOS が自動で調整します）。
- `HOST_DIR` をパスとして埋め込むサンプルの仕組みは、パスにスペースがあると使えません。

---

## 15. 動作確認状況

| 項目 | 状況 |
|---|---|
| サンプル `hello_bba` + dcdev のビルド（通常 / `-Debug`、`-Wall -Wextra` で警告なし） | 確認済み（DreamSDK R4, KOS 2.3.0） |
| GDB 用デバッグ情報（`sh-elf-gdb` でソース行解決） | 確認済み |
| BMP 書き出し（向き・色・行パディング）を PC 上でテスト | 確認済み |
| `prof_report.ps1` の集計と HTML グラフ（サンプルデータ） | 確認済み |
| dcdev 全機能の PC 上テスト（`tests/run_tests.ps1`、46 項目：キャプチャ・ログ・VMU・アセット監視・計測・ボタン操作） | 確認済み |
| `dc_run.ps1` の引数・作業フォルダ・ログ保存（偽の dc-tool-ip で 2000 行、スペース入りパス） | 確認済み |
| `make_dcload_disc.ps1`（DHCP 版 / 固定 IP 再ビルド版 / Audio/Data 版）の CDI 生成 | 確認済み |
| `dc_run.ps1` の ISO 作成と dc-tool-ip 起動（実機なし） | 確認済み |
| VS Code 設定ファイルの書式 | 確認済み（実機での F5 デバッグは未確認） |
| 実機 + BBA（USB の Realtek 100 Mbps アダプターに直結、固定 IP 版 dcload-ip を GDEMU / GDmenu から起動）での転送・コンソール・`/pc/` 読み書き・コントローラー・VMU（`hello_bba`） | 確認済み（2026-11-03） |
| `dc_auto` の自動ループ（ビルド → 転送 → ログ → クラッシュ解析 → 保存で再実行、リセットなしの再送）を実機で | 確認済み（2026-11-03） |
| `/cd/` リダイレクト（`-i`） | **KOS 2.3 では動かない**（8 章の注意） |
| `dc_auto` の判定を偽の dc-tool-ip で PC 上テスト（通常の実行、ビルド失敗で送らず終了コード 1、`Executing at` だけで止まる noexec） | 確認済み（2026-11-05） |
| GDB・画面キャプチャ・アセット即時反映を実機で | 未確認（実機での確認結果を Issue / PR で歓迎します） |

### PC 上でテストする

dcdev は KallistiOS の模擬ヘッダー（`tests/mock/`）を使って PC 上でも動かせます。ライブラリを変更したら実行してください。

```powershell
.\tests\run_tests.ps1
```

`46 checks, 0 failed` と `network: 17 passed, 0 failed`（`setup_pc_network.ps1` のアドレス計算とサブネットの重なりの検出。設定は何も変えません）が出れば OK です。

---

## 16. ライセンス・参考資料

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

