# Dreamcast-Dev-Tools-for-BBA のルール

- 実機の操作は skill `dreamcast-bba-debug`、VMU セーブの解析は skill `vmu-save-analysis` の手順に従う。
- 実機に新しいプログラムを送る前と、VMU に書き込む前 (`scripts\dc_vmu.ps1 -Restore`) は、利用者の了承を得る。
- 自分が起動していない dc-tool-ip は止めない。SD カード・PC のネットワーク設定は利用者が変える。
- `third_party\vmu-workbench\` は VMU Workbench の写し。直接編集せず、元のリポジトリを直して `scripts\sync_vmu_workbench.ps1` で取り込む。
- PowerShell 5.1 で動かす .ps1 に日本語を書くときは UTF-8 (BOM 付き) で保存する。
- ゲームの画像・ディスクイメージ・BIOS はコミットしない。実機で確かめていない機能は README に「実機では未確認」と書く。
