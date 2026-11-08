<#
.SYNOPSIS
  Dreamcast BBA マネージャー: dcload-ip の Dreamcast を最大 16 台まで登録し、dc_auto.ps1（ビルド → 転送 →
  実行 → ログ → クラッシュ解析）と dc_vmu.ps1（VMU の吸い出し・書き戻し）をボタンで動かす GUI。

.DESCRIPTION
  dc_gui.bat をダブルクリックで起動（PowerShell 5.1 と Windows フォームだけを使う。Node.js などは不要。
  「VMU 編集」だけは Node.js が要る）。台の設定は config\units.json（個人の設定なので git に入れない）。

  - 1 台ごとに dc_auto.ps1 -Unit <名前> -Ip <IP> を別のプロセス（見えないコンソール）で動かす。出力は
    logs\units\<名前>\gui_<日時>.txt に保存し、下の欄に表示する。dc-tool-ip のログ・クラッシュ報告も
    logs\units\<名前>\ に入る。
  - 状態は dc_auto が書く logs\units\<名前>\dc_auto_status.txt と、この GUI の ping（1 秒ごと）で表示する。
  - 停止は Ctrl+C を送る（dc_auto が dc-tool-ip を閉じて後片付けをする）。10 秒たっても終わらなければ
    この GUI が起動したプロセス（とその子プロセス）だけを終了させる。
  - GUI を閉じても動いている台はそのまま動き続け、次に GUI を開いたときに引き継ぐ。
  - 同じ IP を 2 台に登録することはできない。bleem2（Exclusive）・VMU 転送・GDB は 1 台ずつ順番に動く
    （dc_auto / dc_vmu が待つ）。
#>
# -SelfTest shot: build the window, refresh, save a screenshot to logs\gui_selftest.png, close
# -SelfTest jobs: units GT1 / GT2 (127.0.0.1 / .2, -Elf from DC_TEST_ELF, set DC_TOOL_IP to a stand-in
#                 dc-tool-ip): starts both, stops GT1 with Ctrl+C, checks GT2 keeps running; config\units.json is not touched
param([ValidateSet('', 'shot', 'jobs')] [string]$SelfTest = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_common.ps1')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$MaxUnits = 16
$unitsFile = if ($env:DC_GUI_UNITS) { $env:DC_GUI_UNITS } else { Join-Path $DevkitRoot 'config\units.json' }   # env: another unit list (tests, screenshots)
$unitsRoot = Join-Path $DevkitRoot 'logs\units'
$autoPs1 = Join-Path $PSScriptRoot 'dc_auto.ps1'
$vmuPs1 = Join-Path $PSScriptRoot 'dc_vmu.ps1'
$oem = [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)

# Ctrl+C to one job's own console. The GUI gives up its console at start, so every job started from it
# gets a console of its own (hidden) and the Ctrl+C reaches only that job and its children.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading;
public static class DcConsole {
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(IntPtr h, bool add);
    [DllImport("kernel32.dll")] static extern bool GenerateConsoleCtrlEvent(uint ev, uint group);
    public static void Detach() { FreeConsole(); }
    public static bool SendCtrlC(int pid) {
        FreeConsole();
        if (!AttachConsole((uint)pid)) return false;
        SetConsoleCtrlHandler(IntPtr.Zero, true);          // this process ignores the Ctrl+C it sends
        bool ok = GenerateConsoleCtrlEvent(0, 0);          // CTRL_C_EVENT to every process on that console
        Thread.Sleep(300);
        FreeConsole();
        SetConsoleCtrlHandler(IntPtr.Zero, false);
        return ok;
    }
}
'@
if ($SelfTest -ne 'shot') { [DcConsole]::Detach() }

# ---------------------------------------------------------------- units (config\units.json)
function New-Unit { [pscustomobject]@{ Name = ''; Ip = ''; Preset = ''; Elf = ''; Build = ''; BuildDir = ''; Watch = ''; Slot = 'a1'; Fast = $false; NoNotify = $true } }
function Read-Units {
    $list = New-Object System.Collections.ArrayList
    if (Test-Path $unitsFile) {
        foreach ($u in @((Get-Content $unitsFile -Raw -Encoding UTF8 | ConvertFrom-Json))) {
            if (-not $u) { continue }
            $n = New-Unit
            foreach ($p in $n.PSObject.Properties.Name) { if ($null -ne $u.$p) { $n.$p = $u.$p } }
            [void]$list.Add($n)
        }
    } elseif ($DcIp) {
        # first start: the Dreamcast of config\bba.config.ps1
        $n = New-Unit; $n.Name = 'DC01'; $n.Ip = $DcIp
        $n.Preset = if (Test-Path (Join-Path $DevkitRoot 'profiles\bleem2.ps1')) { 'bleem2' } else { 'hello_bba' }
        [void]$list.Add($n)
    }
    return , $list
}
function Save-Units {
    New-Item -ItemType Directory -Force (Split-Path -Parent $unitsFile) | Out-Null
    $json = if ($script:units.Count) { ConvertTo-Json -InputObject @($script:units) -Depth 3 } else { '[]' }
    [System.IO.File]::WriteAllText($unitsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}
$script:units = Read-Units

# ---------------------------------------------------------------- jobs (one per unit)
# @{ Proc; Kind; Out; Start; StopAt }  Kind: run / watch / regress / vmu-dump / vmu-restore
$script:jobs = @{}
$script:finished = @{}     # unit -> text of the last job's end (VMU jobs: exit code)
$kindText = @{ run = '実行'; watch = '監視実行'; regress = '回帰テスト'; 'vmu-dump' = 'VMU 吸い出し'; 'vmu-restore' = 'VMU 書き戻し' }

function Get-UnitDir([string]$name) { Join-Path $unitsRoot $name }
function Q([string]$s) { if ($s -eq '' -or $s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s } }

function Get-AutoArgs($u) {
    $a = @()
    if ($u.Preset) { $a += @('-Preset', $u.Preset) }
    if ($u.Elf) { $a += @('-Elf', $u.Elf) }
    if ($u.Build) { $a += @('-Build', $u.Build) }
    if ($u.BuildDir) { $a += @('-BuildDir', $u.BuildDir) }
    $w = @($u.Watch -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($w.Count) { $a += '-WatchPath'; $a += ($w -join ',') }
    if ($u.Fast) { $a += '-Fast' }
    if ($u.NoNotify) { $a += '-NoNotify' }
    return $a
}

function Start-Job2($u, [string]$kind, [string[]]$extra) {
    if ($script:jobs[$u.Name]) { return }
    $dir = Get-UnitDir $u.Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    $out = Join-Path $dir ("gui_{0}_{1}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $kind)
    $script_ = if ($kind -like 'vmu-*') { $vmuPs1 } else { $autoPs1 }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script_, '-Ip', $u.Ip, '-Unit', $u.Name) + $extra
    $argLine = ($a | ForEach-Object { Q $_ }) -join ' '
    [System.IO.File]::WriteAllText($out, "# powershell $argLine`r`n", $oem)
    $p = Start-Process powershell -ArgumentList $argLine -WindowStyle Hidden -PassThru -WorkingDirectory $DevkitRoot `
        -RedirectStandardOutput "$out.part" -RedirectStandardError "$out.err"
    $null = $p.Handle
    $script:jobs[$u.Name] = @{ Proc = $p; Kind = $kind; Out = $out; Start = (Get-Date); StopAt = $null }
    $script:finished.Remove($u.Name)
    # lets a GUI opened later take this job over
    Set-Content -LiteralPath (Join-Path $dir 'gui_job.txt') -Encoding UTF8 -Value @("pid=$($p.Id)", "start=$($p.StartTime.ToString('o'))", "kind=$kind", "out=$out")
}

# a job started by an earlier GUI that still runs
function Restore-Jobs {
    foreach ($u in $script:units) {
        $f = Join-Path (Get-UnitDir $u.Name) 'gui_job.txt'
        if (-not (Test-Path $f)) { continue }
        $kv = @{}; Get-Content $f -Encoding UTF8 | ForEach-Object { if ($_ -match '^(\w+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
        try {
            $p = Get-Process -Id ([int]$kv.pid) -ErrorAction Stop
            if ($p.ProcessName -ne 'powershell' -or [math]::Abs(($p.StartTime - [datetime]$kv.start).TotalSeconds) -gt 2) { continue }
            $null = $p.Handle
            $script:jobs[$u.Name] = @{ Proc = $p; Kind = $kv.kind; Out = $kv.out; Start = $p.StartTime; StopAt = $null; Adopted = $true }
        } catch { }
    }
}

function Get-ChildTree([int]$id) {
    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue)
    $ids = New-Object System.Collections.Generic.List[int]; $ids.Add($id)
    for ($i = 0; $i -lt $ids.Count; $i++) { foreach ($c in $all) { if ($c.ParentProcessId -eq $ids[$i] -and -not $ids.Contains([int]$c.ProcessId)) { $ids.Add([int]$c.ProcessId) } } }
    return $ids
}
function Stop-Job2([string]$name) {
    $j = $script:jobs[$name]
    if (-not $j -or $j.Proc.HasExited) { return }
    if (-not $j.StopAt) {
        $j.StopAt = (Get-Date).AddSeconds(10)
        [void][DcConsole]::SendCtrlC($j.Proc.Id)
    } else {
        # second press, or 10 s without ending: end the processes this GUI started (and their children)
        foreach ($id in @(Get-ChildTree $j.Proc.Id) | Sort-Object -Descending) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
}

# job output: dc_auto writes "<out>.part" while it runs; the GUI shows that file and joins it to <out> at the end
function Get-JobOutPath($j) { if (Test-Path "$($j.Out).part") { "$($j.Out).part" } else { $j.Out } }
function Complete-Job([string]$name) {
    $j = $script:jobs[$name]
    try {
        $code = $j.Proc.ExitCode
        foreach ($f in "$($j.Out).part", "$($j.Out).err") {
            if (Test-Path $f) {
                $t = [System.IO.File]::ReadAllText($f, $oem)
                if ($t) { [System.IO.File]::AppendAllText($j.Out, $(if ($f -like '*.err') { "`r`n# stderr:`r`n" } else { '' }) + $t, $oem) }
                Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
            }
        }
        $script:finished[$name] = @{ Kind = $j.Kind; Code = $code; End = (Get-Date); Out = $j.Out; Stopped = [bool]$j.StopAt }
    } catch { $script:finished[$name] = @{ Kind = $j.Kind; Code = $null; End = (Get-Date); Out = $j.Out } }
    Remove-Item -LiteralPath (Join-Path (Get-UnitDir $name) 'gui_job.txt') -ErrorAction SilentlyContinue
    $script:jobs.Remove($name)
}

function Read-Status([string]$name) {
    $f = Join-Path (Get-UnitDir $name) 'dc_auto_status.txt'
    $kv = @{}
    try { foreach ($l in [System.IO.File]::ReadAllLines($f)) { if ($l -match '^([\w]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } } } catch { }
    return $kv
}

$stateText = @{ building = 'ビルド中'; waiting = '待機中'; running = '実行中'; watching = '変更待ち'; idle = '終了処理' }
$reasonText = @{
    'reset' = '電源の入れ直し待ち（電源を切って 5 秒、入れて GDmenu で DCLOAD-IP）'
    'no-dcload' = 'dcload-ip の応答なし（GDmenu で DCLOAD-IP BBA を起動）'
    'program-running' = '前のプログラムが動いている（終了させるかリセット）'
    'other-dc-tool-ip' = 'この台を別の dc-tool-ip が使用中'
    'other-dc-auto' = '別の dc_auto が送信を始めるところ'
    'shared-resource' = 'ほかの台が共有のファイル・ポートを使用中（順番待ち）'
    'other-build' = 'ほかの台が同じフォルダをビルド中（順番待ち）'
}
$resultText = @{
    'exit' = '終了'; 'crash' = 'クラッシュ'; 'timeout' = '時間切れ'; 'build-failed' = 'ビルド失敗'; 'wait-timeout' = '待ち時間切れ'
    'regress-passed' = '回帰テスト合格'; 'regress-failed' = '回帰テスト失敗'; 'changed' = '再ビルドのため中断'; 'noexec' = '実行されず'; 'none' = '-'
}

# ---------------------------------------------------------------- ping (async, one at a time per unit)
$script:pings = @{}     # name -> @{ Ping; Task; Ok; At }
function Update-Ping($u) {
    $p = $script:pings[$u.Name]
    if (-not $p -or $p.Ip -ne $u.Ip) { $p = @{ Ping = (New-Object System.Net.NetworkInformation.Ping); Task = $null; Ok = $null; Ip = $u.Ip }; $script:pings[$u.Name] = $p }
    if ($p.Task -and $p.Task.IsCompleted) {
        $p.Ok = (-not $p.Task.IsFaulted) -and $p.Task.Result.Status -eq 'Success'
        $p.Task = $null
    }
    if (-not $p.Task) { try { $p.Task = $p.Ping.SendPingAsync($u.Ip, 500) } catch { $p.Ok = $false } }
    return $p.Ok
}
# before the process ends: a ping still in flight that completes during shutdown can crash powershell.exe
function Close-Pings {
    foreach ($p in $script:pings.Values) {
        try { if ($p.Task) { [void]$p.Task.Wait(1000) } } catch { }
        try { $p.Ping.Dispose() } catch { }
    }
    $script:pings = @{}
}

# ---------------------------------------------------------------- window
$font = New-Object System.Drawing.Font('Yu Gothic UI', 9)
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Dreamcast BBA マネージャー'
$form.Size = New-Object System.Drawing.Size(1180, 760)
$form.MinimumSize = New-Object System.Drawing.Size(820, 480)
$form.StartPosition = 'CenterScreen'
$form.Font = $font

$tools = New-Object System.Windows.Forms.FlowLayoutPanel
$tools.Dock = 'Top'; $tools.AutoSize = $true; $tools.Padding = New-Object System.Windows.Forms.Padding(6, 6, 6, 2); $tools.WrapContents = $true
$script:buttons = @{}
function Add-Button([string]$key, [string]$text, [string]$tip, [scriptblock]$click, [switch]$Gap) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.AutoSize = $true; $b.Height = 30
    $b.Margin = New-Object System.Windows.Forms.Padding($(if ($Gap) { 14 } else { 2 }), 2, 2, 2)
    $b.Add_Click($click)
    $script:tip.SetToolTip($b, $tip)
    $tools.Controls.Add($b); $script:buttons[$key] = $b
}
$script:tip = New-Object System.Windows.Forms.ToolTip

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false; $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $true
$grid.RowHeadersVisible = $false; $grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = [System.Drawing.SystemColors]::Window
$grid.BorderStyle = 'None'; $grid.RowTemplate.Height = 26
foreach ($c in @(@('Name', '名前', 70), @('Ip', 'IP', 95), @('Program', 'プログラム', 120), @('Ping', 'dcload', 60),
                 @('State', '状態', 90), @('Detail', '詳細', 300), @('Result', '前回の結果', 110), @('Since', '時刻', 70))) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = $c[0]; $col.HeaderText = $c[1]; $col.FillWeight = $c[2]; $col.SortMode = 'NotSortable'
    [void]$grid.Columns.Add($col)
}

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.SplitterDistance = 330
$split.Panel1.Controls.Add($grid)
$outLabel = New-Object System.Windows.Forms.Label
$outLabel.Dock = 'Top'; $outLabel.Height = 22; $outLabel.TextAlign = 'MiddleLeft'; $outLabel.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$outBox = New-Object System.Windows.Forms.TextBox
$outBox.Dock = 'Fill'; $outBox.Multiline = $true; $outBox.ReadOnly = $true; $outBox.ScrollBars = 'Both'; $outBox.WordWrap = $false
$outBox.Font = New-Object System.Drawing.Font('Consolas', 9); $outBox.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24); $outBox.ForeColor = [System.Drawing.Color]::Gainsboro
$split.Panel2.Controls.Add($outBox); $split.Panel2.Controls.Add($outLabel)

$status = New-Object System.Windows.Forms.StatusStrip
$statusText = New-Object System.Windows.Forms.ToolStripStatusLabel
[void]$status.Items.Add($statusText)

$form.Controls.Add($split); $form.Controls.Add($tools); $form.Controls.Add($status)

function Get-Selected {
    $sel = @($grid.SelectedRows | ForEach-Object { $_.Index } | Sort-Object)
    return @($sel | ForEach-Object { $script:units[$_] })
}
function Show-Msg([string]$text, [string]$icon = 'Information') { [void][System.Windows.Forms.MessageBox]::Show($form, $text, 'Dreamcast BBA マネージャー', 'OK', $icon) }
function Confirm-Msg([string]$text) { return [System.Windows.Forms.MessageBox]::Show($form, $text, 'Dreamcast BBA マネージャー', 'YesNo', 'Question') -eq 'Yes' }

# ---------------------------------------------------------------- unit dialog
function Get-Presets { @(Get-ChildItem (Join-Path $DevkitRoot 'profiles') -Filter '*.ps1' | Where-Object { $_.BaseName -notmatch '_(regress|stats)$' } | ForEach-Object BaseName) }
function Test-Ip([string]$ip) { return $ip -match '^\d{1,3}(\.\d{1,3}){3}$' -and @($ip -split '\.' | Where-Object { [int]$_ -gt 255 }).Count -eq 0 }

function Edit-Unit($u, [bool]$isNew) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $(if ($isNew) { 'Dreamcast を追加' } else { "設定: $($u.Name)" })
    $d.Font = $font; $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterParent'; $d.ClientSize = New-Object System.Drawing.Size(600, 400)
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = 'Fill'; $t.Padding = New-Object System.Windows.Forms.Padding(10); $t.ColumnCount = 3
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 130)))
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 70)))
    $f = @{}
    $row = 0
    function Add-Row([string]$label, $ctl, $btn = $null) {
        $l = New-Object System.Windows.Forms.Label; $l.Text = $label; $l.AutoSize = $true; $l.Anchor = 'Left'; $l.Margin = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
        $ctl.Dock = 'Fill'
        $t.Controls.Add($l, 0, $script:row); $t.Controls.Add($ctl, 1, $script:row)
        if ($btn) { $t.Controls.Add($btn, 2, $script:row) }
        $script:row++
    }
    $script:row = 0
    $tb = { param($v) $x = New-Object System.Windows.Forms.TextBox; $x.Text = [string]$v; $x }
    $f.Name = & $tb $u.Name; Add-Row '名前（英数字 16 字まで）' $f.Name
    $f.Ip = & $tb $u.Ip; Add-Row 'IP アドレス' $f.Ip
    $f.Preset = New-Object System.Windows.Forms.ComboBox; $f.Preset.DropDownStyle = 'DropDownList'
    [void]$f.Preset.Items.Add('（なし: ELF を指定）'); foreach ($p in Get-Presets) { [void]$f.Preset.Items.Add($p) }
    $f.Preset.SelectedIndex = [math]::Max(0, $f.Preset.Items.IndexOf([string]$u.Preset))
    Add-Row 'プリセット' $f.Preset
    $f.Elf = & $tb $u.Elf
    $browse = New-Object System.Windows.Forms.Button; $browse.Text = '参照...'; $browse.Dock = 'Fill'
    $browse.Add_Click({
        $o = New-Object System.Windows.Forms.OpenFileDialog; $o.Filter = 'ELF (*.elf)|*.elf|すべて (*.*)|*.*'
        if ($o.ShowDialog($d) -eq 'OK') { $f.Elf.Text = $o.FileName }
    }.GetNewClosure())
    Add-Row 'ELF（プリセットより優先）' $f.Elf $browse
    $f.Build = & $tb $u.Build; Add-Row 'ビルドコマンド' $f.Build
    $f.BuildDir = & $tb $u.BuildDir; Add-Row 'ビルドフォルダ' $f.BuildDir
    $f.Watch = & $tb $u.Watch; Add-Row '監視するフォルダ（; 区切り）' $f.Watch
    $f.Slot = New-Object System.Windows.Forms.ComboBox; $f.Slot.DropDownStyle = 'DropDownList'
    foreach ($s in 'a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'd1', 'd2') { [void]$f.Slot.Items.Add($s) }
    $f.Slot.SelectedItem = $(if ($u.Slot) { [string]$u.Slot } else { 'a1' }); Add-Row 'VMU のスロット' $f.Slot
    $f.Fast = New-Object System.Windows.Forms.CheckBox; $f.Fast.Text = '高速転送（-Fast。パケットが落ちる LAN もある）'; $f.Fast.Checked = [bool]$u.Fast; Add-Row '' $f.Fast
    $f.NoNotify = New-Object System.Windows.Forms.CheckBox; $f.NoNotify.Text = 'Windows の通知を出さない'; $f.NoNotify.Checked = [bool]$u.NoNotify; Add-Row '' $f.NoNotify
    $hint = New-Object System.Windows.Forms.Label; $hint.AutoSize = $true; $hint.ForeColor = [System.Drawing.Color]::DimGray
    $hint.Text = "ビルドコマンドは DreamSDK のシェルで実行（例: make）。空欄ならプリセットの設定を使う。`n監視するフォルダが空ならビルドフォルダ（ELF のフォルダ）を監視する。"
    $t.Controls.Add($hint, 0, $script:row); $t.SetColumnSpan($hint, 3); $script:row++
    $okp = New-Object System.Windows.Forms.FlowLayoutPanel; $okp.FlowDirection = 'RightToLeft'; $okp.Dock = 'Fill'; $okp.AutoSize = $true
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'キャンセル'; $cancel.DialogResult = 'Cancel'; $cancel.AutoSize = $true
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'OK'; $ok.AutoSize = $true; $ok.Width = 90
    $okp.Controls.Add($cancel); $okp.Controls.Add($ok)
    $t.Controls.Add($okp, 0, $script:row); $t.SetColumnSpan($okp, 3)
    $d.Controls.Add($t); $d.AcceptButton = $ok; $d.CancelButton = $cancel
    $others = @($script:units | Where-Object { -not [object]::ReferenceEquals($_, $u) })
    $ok.Add_Click({
        $name = $f.Name.Text.Trim(); $ip = $f.Ip.Text.Trim()
        $err = if ($name -notmatch '^[A-Za-z0-9_-]{1,16}$') { '名前は英数字・- ・_ で 16 字までにしてください。' }
               elseif (@($others | Where-Object { $_.Name -eq $name }).Count) { "名前 $name はもう使われています。" }
               elseif (-not (Test-Ip $ip)) { 'IP アドレスの形が正しくありません（例: 192.168.10.3）。' }
               elseif (@($others | Where-Object { $_.Ip -eq $ip }).Count) { "IP $ip はもう別の台に登録されています（1 台に 1 つの IP）。" }
               elseif ($f.Preset.SelectedIndex -le 0 -and -not $f.Elf.Text.Trim()) { 'プリセットを選ぶか、ELF を指定してください。' }
        if ($err) { [void][System.Windows.Forms.MessageBox]::Show($d, $err, '入力の確認', 'OK', 'Warning'); return }
        $d.DialogResult = 'OK'; $d.Close()
    }.GetNewClosure())
    if ($d.ShowDialog($form) -ne 'OK') { return $false }
    $u.Name = $f.Name.Text.Trim(); $u.Ip = $f.Ip.Text.Trim()
    $u.Preset = if ($f.Preset.SelectedIndex -gt 0) { [string]$f.Preset.SelectedItem } else { '' }
    $u.Elf = $f.Elf.Text.Trim(); $u.Build = $f.Build.Text.Trim(); $u.BuildDir = $f.BuildDir.Text.Trim(); $u.Watch = $f.Watch.Text.Trim()
    $u.Slot = [string]$f.Slot.SelectedItem; $u.Fast = $f.Fast.Checked; $u.NoNotify = $f.NoNotify.Checked
    return $true
}

# ---------------------------------------------------------------- refresh
function Update-Grid([switch]$Rebuild) {
    if ($Rebuild -or $grid.Rows.Count -ne $script:units.Count) {
        $keep = @(Get-Selected | ForEach-Object Name)
        $grid.Rows.Clear()
        foreach ($u in $script:units) { [void]$grid.Rows.Add() }
        for ($i = 0; $i -lt $script:units.Count; $i++) { $grid.Rows[$i].Selected = $keep -contains $script:units[$i].Name }
        if ($grid.SelectedRows.Count -eq 0 -and $grid.Rows.Count) { $grid.Rows[0].Selected = $true }
    }
    $running = 0
    for ($i = 0; $i -lt $script:units.Count; $i++) {
        $u = $script:units[$i]; $r = $grid.Rows[$i]
        $j = $script:jobs[$u.Name]
        if ($j -and $j.Proc.HasExited) { Complete-Job $u.Name; $j = $null }
        $st = Read-Status $u.Name
        $ok = Update-Ping $u
        $prog = if ($u.Elf) { Split-Path -Leaf $u.Elf } elseif ($u.Preset) { $u.Preset } else { '-' }
        $ping = if ($null -eq $ok) { '…' } elseif ($ok) { '● 応答' } else { '× なし' }
        $state = '停止'; $detail = ''; $since = ''; $color = [System.Drawing.SystemColors]::Window
        if ($j) {
            $running++
            $state = $kindText[$j.Kind]
            if ($j.Kind -notlike 'vmu-*' -and $st.state -and $st.pid -and $st.state -ne 'idle') {
                $state = "$($kindText[$j.Kind]): $($stateText[$st.state])"
                $detail = if ($st.reason -and $reasonText[$st.reason]) { $reasonText[$st.reason] } else { $st.detail }
                if ($st.since) { $since = ($st.since -split 'T')[-1] }
            } else { $since = $j.Start.ToString('HH:mm:ss') }
            if ($j.StopAt) { $state = '停止中…'; $detail = 'Ctrl+C を送った。もう一度「停止」で強制終了' }
            $color = switch ($st.reason) { 'reset' { [System.Drawing.Color]::FromArgb(255, 236, 200) } 'no-dcload' { [System.Drawing.Color]::FromArgb(255, 236, 200) } default { [System.Drawing.Color]::FromArgb(225, 242, 255) } }
            if ($st.state -eq 'running') { $color = [System.Drawing.Color]::FromArgb(222, 247, 222) }
        }
        $res = ''
        $fin = $script:finished[$u.Name]
        if ($fin -and $fin.Kind -like 'vmu-*') { $res = "$($kindText[$fin.Kind]) " + $(if ($fin.Code -eq 0) { 'OK' } else { '失敗' }) }
        elseif ($st.last_result) { $res = $resultText[$st.last_result]; if (-not $res) { $res = $st.last_result } }
        if (-not $j -and $fin -and $fin.Stopped) { $res = "停止した（$res）" }
        if (-not $j -and $st.last_result -eq 'crash') { $color = [System.Drawing.Color]::FromArgb(255, 222, 222) }
        $vals = @{ Name = $u.Name; Ip = $u.Ip; Program = $prog; Ping = $ping; State = $state; Detail = $detail; Result = $res; Since = $since }
        foreach ($k in $vals.Keys) { if ([string]$r.Cells[$k].Value -ne [string]$vals[$k]) { $r.Cells[$k].Value = $vals[$k] } }
        if ($r.DefaultCellStyle.BackColor -ne $color) { $r.DefaultCellStyle.BackColor = $color }
    }
    $statusText.Text = "登録 $($script:units.Count) / $MaxUnits 台    動作中 $running 台    設定: $unitsFile"
    Update-Output
    Update-Buttons
}

$script:shownFile = $null; $script:shownLen = -1
function Update-Output {
    $sel = @(Get-Selected)
    if ($sel.Count -ne 1) { $outLabel.Text = '出力: 台を 1 つ選ぶと表示'; if ($script:shownFile) { $outBox.Clear(); $script:shownFile = $null }; return }
    $u = $sel[0]; $j = $script:jobs[$u.Name]
    $file = $null
    if ($j) { $file = Get-JobOutPath $j }
    elseif ($script:finished[$u.Name]) { $file = $script:finished[$u.Name].Out }
    else { $file = Get-ChildItem (Get-UnitDir $u.Name) -Filter 'gui_*.txt' -ErrorAction SilentlyContinue | Where-Object Name -ne 'gui_job.txt' | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName }
    $outLabel.Text = "出力: $($u.Name)   $(if ($file) { $file } else { '（まだ実行していない）' })"
    if (-not $file -or -not (Test-Path $file)) { if ($script:shownFile) { $outBox.Clear() }; $script:shownFile = $null; return }
    $len = (Get-Item $file).Length
    if ($file -eq $script:shownFile -and $len -eq $script:shownLen) { return }
    try {
        $fs = [System.IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
        try {
            $from = [math]::Max(0, $fs.Length - 60000); $null = $fs.Seek($from, 'Begin')
            $buf = New-Object byte[] ($fs.Length - $from); $n = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Dispose() }
        $text = $oem.GetString($buf, 0, $n) -replace "(?<!`r)`n", "`r`n"
        $atEnd = $file -ne $script:shownFile -or $outBox.SelectionStart -ge $outBox.TextLength - 2
        $outBox.Text = $text
        if ($atEnd) { $outBox.SelectionStart = $outBox.TextLength; $outBox.ScrollToCaret() }
        $script:shownFile = $file; $script:shownLen = $len
    } catch { }
}

function Update-Buttons {
    $sel = @(Get-Selected)
    $anyJob = @($sel | Where-Object { $script:jobs[$_.Name] }).Count -gt 0
    $anyIdle = @($sel | Where-Object { -not $script:jobs[$_.Name] }).Count -gt 0
    $one = $sel.Count -eq 1
    $script:buttons.add.Enabled = $script:units.Count -lt $MaxUnits
    $script:buttons.edit.Enabled = $one -and -not $anyJob
    $script:buttons.remove.Enabled = $sel.Count -gt 0 -and -not $anyJob
    foreach ($k in 'run', 'watch', 'dump') { $script:buttons[$k].Enabled = $anyIdle }
    foreach ($k in 'regress', 'restore') { $script:buttons[$k].Enabled = $one -and $anyIdle }
    $script:buttons.stop.Enabled = $anyJob
    $script:buttons.stopall.Enabled = $script:jobs.Count -gt 0
    foreach ($k in 'log', 'crash', 'folder') { $script:buttons[$k].Enabled = $one }
}

# ---------------------------------------------------------------- buttons
Add-Button 'add' '追加' "Dreamcast を登録（最大 $MaxUnits 台）" {
    if ($script:units.Count -ge $MaxUnits) { Show-Msg "登録できるのは $MaxUnits 台までです。" 'Warning'; return }
    $n = New-Unit
    $n.Name = (1..99 | ForEach-Object { 'DC{0:00}' -f $_ } | Where-Object { $nm = $_; -not @($script:units | Where-Object Name -eq $nm).Count } | Select-Object -First 1)
    $last = @($script:units | Select-Object -Last 1)
    if ($last.Count -and $last[0].Ip -match '^(\d+\.\d+\.\d+)\.(\d+)$' -and [int]$matches[2] -lt 254) { $n.Ip = "$($matches[1]).$([int]$matches[2] + 1)" } else { $n.Ip = '192.168.10.2' }
    if ($last.Count) { $n.Preset = $last[0].Preset; $n.Elf = $last[0].Elf; $n.Build = $last[0].Build; $n.BuildDir = $last[0].BuildDir; $n.Watch = $last[0].Watch; $n.NoNotify = $last[0].NoNotify }
    if (Edit-Unit $n $true) { [void]$script:units.Add($n); Save-Units; Update-Grid -Rebuild; $grid.ClearSelection(); $grid.Rows[$grid.Rows.Count - 1].Selected = $true }
}
Add-Button 'edit' '設定' '選んだ台の設定を変える（動いていないとき）' {
    $u = @(Get-Selected)[0]
    $old = $u.Name
    if (Edit-Unit $u $false) {
        if ($u.Name -ne $old -and (Test-Path (Get-UnitDir $old)) -and -not (Test-Path (Get-UnitDir $u.Name))) { Rename-Item (Get-UnitDir $old) $u.Name -ErrorAction SilentlyContinue }
        Save-Units; Update-Grid -Rebuild
    }
}
Add-Button 'remove' '削除' '選んだ台を一覧から外す（ログは残る）' {
    $sel = @(Get-Selected)
    if (-not (Confirm-Msg "$(($sel | ForEach-Object Name) -join ', ') を一覧から外しますか？（ログ logs\units\ は消しません）")) { return }
    foreach ($u in $sel) { $script:units.Remove($u) }
    Save-Units; Update-Grid -Rebuild
}
Add-Button 'run' '▶ 実行' 'ビルド → dcload-ip を待つ → 転送・実行 → ログ・クラッシュ解析（1 回）' {
    foreach ($u in @(Get-Selected)) { Start-Job2 $u 'run' (Get-AutoArgs $u) }
    Update-Grid
} -Gap
Add-Button 'watch' '⟳ 監視実行' '実行したあともソースを監視し、保存するたびにビルドして送り直す（-Watch）' {
    foreach ($u in @(Get-Selected)) { Start-Job2 $u 'watch' ((Get-AutoArgs $u) + '-Watch') }
    Update-Grid
}
Add-Button 'regress' '回帰テスト' 'テスト一覧（.ps1）を選んで実機で回帰テスト（-Regress）' {
    $u = @(Get-Selected)[0]
    $o = New-Object System.Windows.Forms.OpenFileDialog; $o.Filter = 'テスト一覧 (*.ps1)|*.ps1'; $o.InitialDirectory = Join-Path $DevkitRoot 'profiles'
    if ($o.ShowDialog($form) -ne 'OK') { return }
    Start-Job2 $u 'regress' ((Get-AutoArgs $u) + @('-Regress', $o.FileName)); Update-Grid
}
Add-Button 'stop' '■ 停止' '選んだ台を止める（Ctrl+C。もう一度押すと強制終了）' {
    foreach ($u in @(Get-Selected)) { Stop-Job2 $u.Name }
    Update-Grid
}
Add-Button 'stopall' 'すべて停止' '動いている台をすべて止める' {
    if (-not (Confirm-Msg "動いている $($script:jobs.Count) 台をすべて止めますか？")) { return }
    foreach ($n in @($script:jobs.Keys)) { Stop-Job2 $n }
    Update-Grid
}
Add-Button 'log' 'ログ' 'dc-tool-ip のログ（いま実行中、または最後の回）をメモ帳で開く' {
    $u = @(Get-Selected)[0]; $st = Read-Status $u.Name
    $f = if ($st.log -and $st.state -eq 'running') { $st.log } elseif ($st.last_log) { $st.last_log } else { $st.log }
    if (-not $f) { $f = Get-ChildItem (Get-UnitDir $u.Name) -Filter 'auto_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName }
    if ($f -and (Test-Path $f)) { Start-Process notepad.exe $f } else { Show-Msg 'まだログがありません。' }
} -Gap
Add-Button 'crash' 'クラッシュ報告' '最後のクラッシュ報告（*.crash.txt: 関数名・ソースの行）を開く' {
    $u = @(Get-Selected)[0]
    $f = Get-ChildItem (Get-UnitDir $u.Name) -Filter '*.crash.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 -ExpandProperty FullName
    if ($f) { Start-Process notepad.exe $f } else { Show-Msg "$($u.Name) のクラッシュ報告はありません。" }
}
Add-Button 'folder' 'フォルダ' 'この台のログのフォルダ（logs\units\<名前>）を開く' {
    $u = @(Get-Selected)[0]; $dir = Get-UnitDir $u.Name
    New-Item -ItemType Directory -Force $dir | Out-Null; Start-Process explorer.exe $dir
}
Add-Button 'dump' 'VMU 吸い出し' '選んだ台の VMU を丸ごと PC に読み込む（logs\vmu\<名前>_<スロット>_<日時>.bin。複数台は 1 台ずつ順番）' {
    foreach ($u in @(Get-Selected)) { Start-Job2 $u 'vmu-dump' @('-Dump', '-Slot', $u.Slot, '-NoNotify') }
    Update-Grid
} -Gap
Add-Button 'restore' 'VMU 書き戻し' 'イメージ（128 KB）を選んだ台の VMU に書き込む（書く前の VMU は *_before.bin に保存）' {
    $u = @(Get-Selected)[0]
    $o = New-Object System.Windows.Forms.OpenFileDialog; $o.Filter = 'VMU イメージ (*.bin)|*.bin|すべて (*.*)|*.*'; $o.InitialDirectory = Join-Path $DevkitRoot 'logs\vmu'
    if ($o.ShowDialog($form) -ne 'OK') { return }
    if ((Get-Item $o.FileName).Length -ne 131072) { Show-Msg 'VMU イメージ（128 KB）ではありません。' 'Warning'; return }
    if (-not (Confirm-Msg "$($u.Name)（$($u.Ip)）のスロット $($u.Slot.ToUpper()) の VMU を丸ごと上書きします。`n`n$($o.FileName)`n`n書く前の VMU は logs\vmu\*_before.bin に保存されます。書き込みますか？")) { return }
    Start-Job2 $u 'vmu-restore' @('-Restore', $o.FileName, '-Slot', $u.Slot, '-Yes', '-NoNotify'); Update-Grid
}
Add-Button 'vmugui' 'VMU 編集' 'VMU Workbench（セーブの編集画面）をブラウザで開く。Node.js が必要' {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Show-Msg 'VMU 編集には Node.js が必要です: https://nodejs.org/' 'Warning'; return }
    Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + (Q $vmuPs1) + ' -Gui') -WorkingDirectory $DevkitRoot
}

$grid.Add_SelectionChanged({ Update-Output; Update-Buttons })
$grid.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0 -and $script:buttons.edit.Enabled) { $script:buttons.edit.PerformClick() } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ try { Update-Grid } catch { $statusText.Text = "更新エラー: $_" } })

$form.Add_FormClosing({
    param($s, $e)
    $n = @($script:jobs.Values | Where-Object { -not $_.Proc.HasExited }).Count
    if ($n -eq 0) { return }
    $a = [System.Windows.Forms.MessageBox]::Show($form, "$n 台が動いています。`n`nはい: 止めてから閉じる`nいいえ: 動かしたまま閉じる（次に開いたときに引き継ぐ）",
        'Dreamcast BBA マネージャー', 'YesNoCancel', 'Question')
    if ($a -eq 'Cancel') { $e.Cancel = $true; return }
    if ($a -eq 'Yes') {
        foreach ($k in @($script:jobs.Keys)) { Stop-Job2 $k }
        $t0 = Get-Date
        while (@($script:jobs.Values | Where-Object { -not $_.Proc.HasExited }).Count -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep -Milliseconds 200 }
        foreach ($k in @($script:jobs.Keys)) { Stop-Job2 $k }     # still running after 10 s: end them
        Start-Sleep -Milliseconds 300
        foreach ($k in @($script:jobs.Keys)) { if ($script:jobs[$k].Proc.HasExited) { Complete-Job $k } }
    }
})

if ($SelfTest -eq 'jobs') {
    $script:units = New-Object System.Collections.ArrayList
    foreach ($i in 1, 2) { $n = New-Unit; $n.Name = "GT$i"; $n.Ip = "127.0.0.$i"; $n.Elf = $env:DC_TEST_ELF; [void]$script:units.Add($n) }
    foreach ($u in $script:units) { Remove-Item -Recurse -Force (Get-UnitDir $u.Name) -ErrorAction SilentlyContinue }
    $log = New-Object System.Collections.Generic.List[string]
    $snap = { param($what) Update-Grid; $log.Add(("{0,-28} GT1=[{1}] GT2=[{2}]" -f $what, $grid.Rows[0].Cells['State'].Value, $grid.Rows[1].Cells['State'].Value)) }
    Update-Grid -Rebuild
    foreach ($u in $script:units) { Start-Job2 $u 'watch' ((Get-AutoArgs $u) + '-Watch') }
    $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; Update-Grid } until (((Read-Status 'GT1').state -eq 'running' -and (Read-Status 'GT2').state -eq 'running') -or ((Get-Date) - $t0).TotalSeconds -gt 40)
    & $snap 'both running'
    Stop-Job2 'GT1'
    $t0 = Get-Date
    do { Start-Sleep -Milliseconds 300; Update-Grid } until (-not $script:jobs['GT1'] -or ((Get-Date) - $t0).TotalSeconds -gt 15)
    & $snap 'after Ctrl+C to GT1'
    $log.Add("GT1 stopped by Ctrl+C: $(-not $script:jobs['GT1'])   GT2 still running: $([bool]($script:jobs['GT2'] -and -not $script:jobs['GT2'].Proc.HasExited))")
    $log.Add("GT1 status: $(((Get-Content (Join-Path (Get-UnitDir 'GT1') 'dc_auto_status.txt')) | Where-Object { $_ -match '^(state|last_result)=' }) -join ' ')")
    $log.Add("GT1 output tail: $((Get-Content $script:finished['GT1'].Out | Select-Object -Last 3) -join ' / ')")
    Stop-Job2 'GT2'; Start-Sleep 4; Update-Grid
    if ($script:jobs['GT2']) { Stop-Job2 'GT2'; Start-Sleep 1; Update-Grid; $log.Add('GT2 needed the forced stop') }
    $left = @(Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($env:DC_TOOL_IP)) -ErrorAction SilentlyContinue).Count
    $log.Add("jobs left: $($script:jobs.Count)   stand-in dc-tool-ip left: $left")
    $log; Close-Pings; $form.Dispose(); return
}

Restore-Jobs
Update-Grid -Rebuild
if ($SelfTest -eq 'shot') {
    $form.Show(); [System.Windows.Forms.Application]::DoEvents()
    foreach ($i in 1..3) { Start-Sleep -Milliseconds 700; Update-Grid; [System.Windows.Forms.Application]::DoEvents() }   # ping results come in
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $png = Join-Path $DevkitRoot 'logs\gui_selftest.png'
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "rows=$($grid.Rows.Count) jobs=$($script:jobs.Count) screenshot=$png"
    Close-Pings; $form.Dispose(); return
}
$timer.Start()
[void]$form.ShowDialog()
$timer.Stop()
Close-Pings
$form.Dispose()
