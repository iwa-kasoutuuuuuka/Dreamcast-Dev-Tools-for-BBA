---
description: Dreamcast 実機でビルド → 実行 → ログとクラッシュの確認を回す (dc_auto)
---

skill `dreamcast-bba-debug` に従う。

1. 対象のプリセット (`profiles\*.ps1`) か、ELF・ビルドコマンド・フォルダを決める。
2. Dreamcast で dcload-ip が起動しているか確かめる。別の dc-tool-ip が動いていたら止めずに待つ。
3. 利用者の了承を得てから、ターミナルで `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dc_auto.ps1 -Preset <名前>` を実行する
   (保存のたびに回すなら `-Watch`)。
4. 終わったら `logs\auto_<日時>.txt` を読み、`logs\auto_<日時>.crash.txt` があれば関数名・ソース行から原因を調べる。
5. 直したら再実行する。実機で確かめたことと PC 上だけのことを分けて報告する。
