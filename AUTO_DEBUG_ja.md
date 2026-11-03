# GDmenu + BBA 自動デバッグ環境

> この文書のパス（`H:\DC\...`、`profiles\bleem2.ps1`）と IP（DC 192.168.10.2 / PC 192.168.10.1）は作者の環境の例です。
> 自分のプロジェクトでは `profiles\` に同じ形のプリセットを作るか、`-Elf` / `-Build` / `-BuildDir` を指定してください。

GDEMU の GDmenu から dcload-ip を起動しておけば、あとは PC 側で
**ビルド → Dreamcast の準備待ち → 転送・実行 → ログ保存 → クラッシュ箇所の特定 → ソース変更で自動やり直し**
が回ります。

```
[GDmenu] → 44 "DCLOAD-IP BBA 192.168.10.2" → dcload-ip（青い画面・idle）
                                   ▲  LAN 直結（DC 192.168.10.2 ⇔ PC 192.168.10.1）
dc_auto.bat ─ build ─ ping 待ち ─ dc-tool-ip -x ─ logs\auto_*.txt ─ *.crash.txt
      ▲                                                    │
      └──────── ソースを保存すると自動で再ビルド・再実行 ◄───┘
```

## 最初に 1 回だけ

1. **SD カードに dcload-ip を入れる**
   `H:\DC\gdemu_sd_cdpark\44\`（disc.cdi + name.txt など）を、SD の次の空き番号のフォルダにコピー（番号は 01 から連続）。
2. **Dreamcast を起動** → GDmenu で「DCLOAD-IP BBA 192.168.10.2」を選ぶ → 青い画面に `192.168.10.2` と `idle...` が出る。
3. **PC 側のネットワーク設定**（管理者 PowerShell で 1 回）
   ```powershell
   H:\DC\tools\dc-bba-tools\scripts\setup_pc_network.ps1
   ```
   リンクが来ている有線 LAN に 192.168.10.1 を付け、dc-tool-ip の受信を 192.168.10.x からだけ許可します。
   Wi-Fi のインターネット接続はそのままです。戻すときは `-Undo`。
   最後に `Dreamcast 192.168.10.2 answers ping. Ready.` と出れば OK。

## 毎回の使い方

| やりたいこと | 操作 |
|---|---|
| bleem2 を自動ループで回す | `dc_auto.bat` をダブルクリック |
| サンプルで動作確認 | `dc_auto.bat -Preset hello_bba -Watch` |
| 1 回だけ実行 | `dc_auto.bat -Preset bleem2`（`-Watch` なし） |
| ビルドせずに今の ELF を送る | `-NoBuild` を追加 |
| 任意の ELF | `dc_auto.bat -Elf H:\path\game.elf` |
| 保存済みログからクラッシュ箇所を引く | `dc_auto.bat -Analyze logs\auto_….txt -Elf H:\DC\bleem2\bleem2.elf` |
| GDB 付き | `scripts\dc_gdb.ps1`（README 9 章。プログラム側に `gdb_init()` が必要） |

- ログ：`logs\auto_日付_時刻.txt`（Dreamcast の printf / dbglog がすべて入る）
- クラッシュ時（KOS の `Unhandled exception` / スタックトレース / `ASSERTION FAILURE` / `kernel panic`）は
  PC・PR・スタックの各アドレスを `sh-elf-addr2line` で関数名とソース行に変換し、
  画面に赤字で表示して `logs\auto_….crash.txt` に保存します。クラッシュした回の ELF も `logs\auto_….elf` に残すので、
  あとで `-Analyze` しても（その後に再ビルドしていても）正しい関数名・行になります。
- `-Watch` 中にソースを保存すると再ビルドし、dcload-ip が待ち受けに戻った時点（プログラムが `exit()` した、
  またはリセットして GDmenu から 44 を選び直した）で新しい ELF を自動で送ります。
- **bleem2 はリセット不要**：再ビルドが成功すると dc_auto が `logs\bleem2\reload.req` を作り、bleem2 はそれを 1 秒ごとに
  見て自分から dcload に戻ります。そのまま新しい版が送られます（プリセットの `ReloadReq`）。
  ほかにも dcload 起動時の bleem2 は次のとき dcload に戻ります：A+B+X+Y+Start、SH-4 例外（KOS と同じ書式で
  レジスタを出すので crash.txt ができる）、30 秒フレームが進まないハング。ディスク起動では従来どおりその場で止まります。
- dcload 起動時の bleem2 は、デバッグ用ファイル（BLEEMLOG / BLEEMWIN / BLEEMDSC / SHOTn など）を VMU ではなく
  `logs\bleem2\` に書きます（VMU が一杯になる・書き込みで止まる問題の対策）。セーブデータは VMU のままです。
- dcload-ip はプログラム実行中でも（/pc/ やコンソールの通信中に）ping に応答するため、ping だけでは「送ってよい」と判定しません。
  送るのは「ping が返る」かつ「この PC で他の dc-tool-ip が動いていない」かつ「前回の実行が終わった、
  または再起動を検出した（5 秒以上 ping が途切れてから復帰）」ときだけです。実行中のプログラムを上書きしないためです。
  dcload の呼び出しを数秒しないプログラムはリセットと見分けられないので、長く黙るプログラムでは `-WaitReboot` を使わず、
  プログラム側から定期的に /pc/ や printf を使ってください（bleem2 は reload.req の確認がその役目を兼ねます）。

## 電源を入れ直す必要があるとき

- KOS が例外を捕まえた場合や `exit()` した場合は dcload-ip に戻るので、そのまま次を送れます。
- 完全に固まった場合だけ、電源（またはリセット）→ GDmenu → 44 を選び直してください。スクリプトは待ち続けます。

## 制限・注意（2026-11-03 時点）

- **実機で確認済み（2026-11-03）**：サンプル（コンソール・/pc/・コントローラー・VMU）と、
  bleem2 が `/pc/` のフォルダからメタルスラッグXを起動するところまで。
  `-Watch` で保存 → 再ビルド → bleem2 が自分で dcload に戻る → 自動送信、もリセットなしで 2 回続けて確認済み。
  クラッシュ解析も実機で確認済み：わざと起こした SH-4 例外で dcload に自動で戻り、`crash.txt` に関数名とソース行
  （例外の場所と呼び出し元）が出て、次の保存でそのまま送り直せた。
- **`/cd/` リダイレクト（`-Iso` / `-CdDir`）は KallistiOS 2.3 では動きません。** dcload-ip 2.0.3 は GD-ROM コマンドに
  ハンドル 0 を返し（KOS はこれを失敗扱い）、DMA 読み込みにも対応していないため。ディスクのデータは `/pc/` で読む必要があります。
- **bleem2 は dcload から起動すると PC のフォルダからディスクを読みます**（`src/disc.h` の `BBA_DISC_DIR`）。
  `/cd` を探したあと `build\bleem2_cd\`（= `/pc/DC/tools/dc-bba-tools/build/bleem2_cd`）も探し、
  BIOS はその中の `psbios\` から読みます。プリセットが METAL_SL.BIN（ハードリンク）と BIOS を置きます。
  別のゲームを試すときは、このフォルダの .bin / .cue を入れ替えてください。ディスク起動（GDEMU）のときは何も変わりません。
- bleem2 の `dlog` は printf にも出ます。ディスク起動のときは本体のシリアル（SCIF）に出しますが、
  dcload から起動したときは出力先を dcload のコンソールのままにするので、PC の `logs\auto_*.txt` に入ります
  （`src/main.c`。ログが多いと LAN 経由の分だけ遅くなることがあります）。
- `/pc/` は H: ドライブ全体が見えます。LAN ケーブル直結なので外部からは届きませんが、ルーターにつなぐ場合は注意。
- `make_dcload_disc.ps1` の不具合を修正済み：dcload-ip のビルドが既にスクランブルした 1st_read.bin をもう一度
  スクランブルしていたため、作ったディスクが起動しなかった。

## ファイル

| ファイル | 内容 |
|---|---|
| `dc_auto.bat` | ダブルクリック用（引数なし = bleem2 を `-Watch` で） |
| `scripts\dc_auto.ps1` | 自動デバッグループ本体 |
| `scripts\setup_pc_network.ps1` | PC の固定 IP + ファイアウォール（管理者で 1 回） |
| `profiles\bleem2.ps1` / `profiles\hello_bba.ps1` | プリセット（ELF・ビルドコマンド・監視するフォルダ） |
| `config\bba.config.ps1` | Dreamcast の IP（192.168.10.2） |
| `out\dcload-ip_gdemu.cdi` | GDEMU 用 dcload-ip（mkdcdisc 製、= gdemu_sd_cdpark\44\disc.cdi） |
| `out\dcload-ip.cdi` | CD-R 用 dcload-ip（cdi4dc 製） |
