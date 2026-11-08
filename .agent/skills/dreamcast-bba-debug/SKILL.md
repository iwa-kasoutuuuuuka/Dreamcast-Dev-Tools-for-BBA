---
name: dreamcast-bba-debug
description: Dreamcast 実機を BBA (ブロードバンドアダプタ) と dcload-ip でデバッグする手順。Dreamcast-Dev-Tools-for-BBA の dc_auto.ps1 (ビルド → 転送 → 実行 → ログ → クラッシュ解析 → 再送、-Watch / -Regress) と dc_vmu.ps1 (実機 VMU の吸い出し・書き戻し、PS1 メモリーカード .mcr の出し入れ) を使う。「実機で動かして」「実機のログを見て」「クラッシュした場所を調べて」「回帰テストを回して」「VMU を吸い出して」「セーブを編集して VMU に戻して」などで使う。
---

# Dreamcast 実機デバッグ (BBA + dcload-ip)

このリポジトリ (Dreamcast-Dev-Tools-for-BBA) のスクリプトで、PC から実機を操作する。詳しい説明は `README.md` と
`AUTO_DEBUG_ja.md`。VMU のセーブの中身を解析するときは skill `vmu-save-analysis` も使う。
ビルド → 実行 → ログ確認の流れは skill `dc-debug`、VMU の吸い出し → 編集 → 書き戻しの流れは skill `vmu-edit` にまとめてある。

## 守ること (実機と利用者のものを壊さない)

- **実機に送る前に利用者に確認する。** 新しいプログラムやテスト用の版を送るとき、何が起きるか (例: 30 秒で dcload に戻る) を伝えて了承を得る。
- **VMU への書き込み (`dc_vmu.ps1 -Restore`) は、毎回利用者の明確な了承を得てから。** 書き戻すイメージと対象スロットを伝える。
  `-Yes` は利用者がそう指示したときだけ付ける。書き戻しの前に今の中身が `logs\vmu\*_before.bin` に吸い出されることも伝える。
- **自分が起動していない dc-tool-ip は止めない。** 別の作業が Dreamcast を使っている。`dc_auto` は終わるまで自動で待つ。
- SD カード (GDEMU) への書き込み、PC のネットワーク・ファイアウォールの設定変更 (`setup_pc_network.ps1`) は利用者が行う。
- ゲームの画像・ディスクイメージ・BIOS はリポジトリに入れない (`logs\`・`build\` は git の対象外)。

## スクリプトの起動

PowerShell の実行ポリシーで `.\scripts\x.ps1` が止まることがある。そのときは
`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dc_auto.ps1 ...` で起動する (設定は変えない)。
長く動くもの (`-Watch`、`-Regress`、実機を待つもの) は、利用者が見られるターミナルで動かす。

Dreamcast が複数台 (最大 16 台、`config\units.json` に名前と IP) のときは、どの台かを利用者に確かめて
`dc_auto.ps1 -Unit <名前> -Ip <IP>` / `dc_vmu.ps1 -Unit <名前> -Ip <IP>` で動かす。その台のログ・クラッシュ報告・状態は
`logs\units\<名前>\` (`dc_auto_status.txt`)。利用者が GUI (`dc_gui.bat`) で動かしている台は、GUI から止めてもらう。

## 準備ができているか

1. PC と Dreamcast が LAN でつながっている (`Test-Connection 192.168.10.2`。IP は `config\bba.config.ps1`)。
2. Dreamcast で GDmenu から dcload-ip (青い画面) を起動してある。ping が返っても、プログラムの実行中のことがある。
3. 返らなければ、利用者に「リセットして GDmenu から DCLOAD-IP を起動して」と頼む。

## よく使う操作

| やりたいこと | コマンド |
|---|---|
| ビルドして実機で 1 回実行、ログを保存 | `dc_auto.ps1 -Preset <名前>` (または `-Elf x.elf -Build 'make' -BuildDir <dir>`) |
| 保存するたびに自動で再ビルド・再送 | `dc_auto.ps1 -Preset <名前> -Watch` |
| クラッシュの場所 (関数名・行) | 自動で `logs\auto_*.crash.txt`。後から `dc_auto.ps1 -Analyze <log>` |
| 実機で回帰テスト (画面を基準と比較) | `dc_auto.ps1 -Preset bleem2 -Regress .\profiles\bleem2_regress.ps1` (初回・作り直しは `-UpdateBaseline`) |
| VMU を丸ごと PC に | `dc_vmu.ps1 -Dump` → `logs\vmu\a1_<日時>.bin` |
| bleem2 の PS1 カードを .mcr に / .mcr から | `dc_vmu.ps1 -ExportPs1 card.mcr` / `-ImportPs1 card.mcr` (→ `*_ps1.bin`) |
| イメージを VMU に書き戻す (要了承) | `dc_vmu.ps1 -Restore <img>` |
| セーブの一覧 / GUI エディタ | `dc_vmu.ps1 -List` / `-Gui` |

## 結果の読み方

- `logs\auto_<日時>.txt`：実機のコンソール出力 (printf / dbglog)。`.stderr` は dc-tool-ip のエラー。
- `logs\auto_<日時>.crash.txt`：KOS の例外表示を `sh-elf-addr2line` で関数名・ソース行にしたもの。その回の ELF は `<log>.elf`。
- `[run] dcload-ip received the program but did not start it`：前のプログラムが dcload の途中で止まっている。リセットを頼む
  (dc_auto はリセットを検出して自動で送り直す)。
- `[wait] Another dc-tool-ip is running`：別の作業が使用中。止めずに待つ。
- 回帰テストは `logs\regress\<日時>\report.html` (基準・今回・差分)。失敗があると終了コード 1。
- VMU の転送結果は `logs\vmu\vmu_result.txt` (`dump OK <crc32>` / `restore OK <crc32>` / `END OK`)。

## 報告のしかた

実機で確かめたことと、PC 上だけで確かめたことを分けて書く。実機で試していない機能は「実機では未確認」と書く。
