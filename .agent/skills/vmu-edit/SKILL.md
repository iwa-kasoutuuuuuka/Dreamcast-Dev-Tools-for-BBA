---
name: vmu-edit
description: 実機の VMU を BBA で吸い出し、セーブ (bleem2 の PS1 メモリーカードを含む) を編集して VMU に書き戻す手順 (dc_vmu.ps1 と VMU Workbench)。「VMU を吸い出して」「このセーブの値を変えて VMU に戻して」「PS1 のカードを .mcr にして編集したい」など、実機の VMU の中身を PC で編集して戻すときに使う。
---

# 実機の VMU を吸い出して編集し、書き戻す

skill `dreamcast-bba-debug` と `vmu-save-analysis` に従う。

1. Dreamcast で dcload-ip が起動しているか確かめる (`Test-Connection 192.168.10.2`)。返らなければ利用者に起動を頼む。
2. 利用者の了承を得てから `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dc_vmu.ps1 -Dump` を実行し、
   できた `logs\vmu\a1_<日時>.bin` のファイル一覧を伝える。
3. 編集する：
   - bleem2 の PS1 セーブ：`dc_vmu.ps1 -ExportPs1 <card.mcr>` → 利用者が MemcardRex などで編集 → `dc_vmu.ps1 -ImportPs1 <card.mcr>`
   - 名前付きの値 (構造定義があるとき)：MCP `dc-vmu` の `vmu_fields` / `vmu_set`、または `node third_party\vmu-workbench\cli.js fields|set`
   - それ以外：`dc_vmu.ps1 -Gui` で HEX・アイコン・説明文を編集
4. `node third_party\vmu-workbench\cli.js check <新しいイメージ>` が OK になることを確かめ、変更点 (差分) を利用者に見せる。
5. 書き戻すイメージとスロットを伝えて**了承を得てから** `dc_vmu.ps1 -Restore <新しいイメージ>` を実行する
   (書き戻す前の中身は `logs\vmu\*_before.bin` に残る)。
6. `vmu_result.txt` の `restore OK` と、ゲームで反映されたか (利用者に確認) を報告する。
