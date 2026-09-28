param([switch]$SelfTest, [switch]$PickHook)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class K3 {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool doAttach);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    public struct RECT { public int L, T, R, B; }
    public static string Class(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static IntPtr FocusOf(IntPtr hwnd) {
        int pid; uint t = GetWindowThreadProcessId(hwnd, out pid);
        int cur = K3.GetCurrentThreadId();
        IntPtr f = IntPtr.Zero;
        if (t != 0) { AttachThreadInput(cur, (int)t, true); f = GetFocus(); AttachThreadInput(cur, (int)t, false); }
        return f;
    }
}
"@
[void][K3]::SetProcessDPIAware()

# 深色面板上只应出现一条亮块（我们画的光标）。编辑控件的字形若漏画出来会变成多簇。
function BrightCols($bmp) {
    $W = $bmp.Width; $H = $bmp.Height
    $set = @{}
    for ($y = 4; $y -lt $H - 4; $y++) {
        for ($x = 4; $x -lt $W - 4; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $set[$x] = 1 }
        }
    }
    return @($set.Keys | Sort-Object)
}

function Clusters($cols) {
    $out = @(); $run = @()
    foreach ($x in $cols) {
        if ($run.Count -eq 0 -or $x -eq $run[-1] + 1) { $run += $x } else { $out += , @($run); $run = @($x) }
    }
    if ($run.Count -gt 0) { $out += , @($run) }
    return $out
}

# 反向测试：检查器本身必须能发现字形漏出来，否则它只是摆设
if ($SelfTest) {
    $bmp = New-Object System.Drawing.Bitmap 68, 47
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(24, 26, 31))
    $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 236, 244))
    $g.FillRectangle($b, 24, 12, 4, 22)
    $g.FillRectangle($b, 40, 14, 6, 18)
    $g.FillRectangle($b, 50, 14, 6, 18)
    $g.FillRectangle($b, 60, 14, 6, 18)
    $g.Dispose(); $b.Dispose()
    $n = @(Clusters (BrightCols $bmp)).Count
    $bmp.Dispose()
    if ($n -ge 4) { Write-Host "  reverse-test ok: synthetic 4 blocks detected $n"; exit 0 }
    Write-Host "  reverse-test FAIL: synthetic 4 blocks detected only $n"
    exit 1
}

function Invoke-Once([bool]$withTestPick) {
    $sf = Join-Path $env:TEMP ("kisapper-pickprobe-" + [guid]::NewGuid().ToString("N") + ".txt")
    $env:KISAPPER_STATE_FILE = $sf
    if ($withTestPick) { $env:KISAPPER_TEST_PICK = "1" } else { Remove-Item Env:\KISAPPER_TEST_PICK -ErrorAction SilentlyContinue }
    $pp = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
    Start-Sleep -Milliseconds 1800
    $txt = "(no state file)"
    if (Test-Path $sf) { $txt = (Get-Content $sf -Raw).Trim() }
    Stop-Process -Id $pp.Id -Force -ErrorAction SilentlyContinue
    if (Test-Path $sf) { Remove-Item $sf -Force }
    return $txt
}

# 取色钩子：没有真鼠标也要能确认全局钩子确实挂上了（钩子挂不上 = 用户看到的"点了没反应"）
if ($PickHook) {
    $off = Invoke-Once $false
    $on = Invoke-Once $true
    Write-Host "baseline: $off"
    Write-Host "testpick: $on"
    $ok = $true
    if ($on -notmatch "picking=1") { Write-Host "FAIL pick mode did not start" -ForegroundColor Red; $ok = $false }
    if ($on -notmatch "hook=1") { Write-Host "FAIL WH_MOUSE_LL hook not installed - clicking cannot apply color" -ForegroundColor Red; $ok = $false }
    if ($off -match "picking=1" -or $off -match "hook=1") { Write-Host "FAIL baseline already picking (check is vacuous)" -ForegroundColor Red; $ok = $false }
    if ($ok) { Write-Host "`nPICK HOOK PASSED"; exit 0 }
    exit 1
}

$state = Join-Path $env:TEMP ("kisapper-hostprobe-" + [guid]::NewGuid().ToString("N") + ".txt")
$env:KISAPPER_STATE_FILE = $state
if (Test-Path $state) { Remove-Item $state -Force }

$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle
$f = [K3]::FocusOf($h)
Write-Host "main=$h focus=$f focusClass=$([K3]::Class($f))"

function ReadState { if (Test-Path $state) { (Get-Content $state -Raw).Trim() } else { "(no state file)" } }
Write-Host "before: $(ReadState)"

$text = "The quick brown fox jumps over 13 lazy dogs, again and again 0123456789"
foreach ($ch in $text.ToCharArray()) {
    [void][K3]::SendMessage($f, 0x0102, [IntPtr][int]$ch, [IntPtr]::Zero)
}
Start-Sleep -Milliseconds 800
Write-Host "after:  $(ReadState)"

$r = New-Object K3+RECT
[void][K3]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T

$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$Scale = [Math]::Round($g0.DpiX / 96.0, 0)
$g0.Dispose()
# 逻辑常量 pad=6 caretW=2 tail=20 -> 常态宽 34，光标钉在 x=12（逻辑 px）
$expW = [int](34 * $Scale); $expCaretX = [int](12 * $Scale)
Write-Host "rect ${w}x${hh} dpi=$Scale  width should stay $expW after 71 chars"

$counts = @()
$caretAt = @()
for ($i = 0; $i -lt 6; $i++) {
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    if ($i -eq 0) { $bmp.Save("$PSScriptRoot\shot-hostprobe.png") }
    $cl = @(Clusters (BrightCols $bmp))
    $counts += $cl.Count
    if ($cl.Count -eq 1) { $caretAt += $cl[0][0] }
    if ($i -eq 0) { foreach ($c in $cl) { Write-Host ("  block cols {0}-{1} width {2}" -f $c[0], $c[-1], $c.Count) } }
    $g.Dispose(); $bmp.Dispose()
    Start-Sleep -Milliseconds 260
}
Write-Host "blocks per frame = $($counts -join ',')  (0 = caret blink off)"

$bad = @($counts | Where-Object { $_ -gt 1 })
$alive = @($counts | Where-Object { $_ -eq 1 })
$ok = $true
if ($bad.Count -gt 0) { Write-Host "FAIL glyphs leaked (>1 bright block in a frame)" -ForegroundColor Red; $ok = $false }
if ($alive.Count -lt 2) { Write-Host "FAIL caret never drawn" -ForegroundColor Red; $ok = $false }
if ([Math]::Abs($w - $expW) -gt 4) { Write-Host "FAIL window grew: got $w want $expW" -ForegroundColor Red; $ok = $false }
if ($caretAt.Count -ge 2) {
    $worst = 0
    foreach ($x in $caretAt) { $d = [Math]::Abs($x - $expCaretX); if ($d -gt $worst) { $worst = $d } }
    if ($worst -gt [int](3 * $Scale)) { Write-Host "FAIL caret column $($caretAt -join ',') not pinned near $expCaretX" -ForegroundColor Red; $ok = $false }
    else { Write-Host "  caret column = $($caretAt -join ',') (want $expCaretX)" }
} else { Write-Host "FAIL caret column not measured" -ForegroundColor Red; $ok = $false }
$st = ReadState
if ($st -notmatch "len=71") { Write-Host "FAIL text not in model: $st" -ForegroundColor Red; $ok = $false }
if ($st -notmatch "imediag=ctx=1") { Write-Host "FAIL host has no IME context, Chinese cannot be typed" -ForegroundColor Red; $ok = $false }

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
if (Test-Path $state) { Remove-Item $state -Force }
if ($ok) { Write-Host "`nHOST PROBE PASSED" -ForegroundColor Green; exit 0 }
exit 1
param([switch]$SelfTest, [switch]$PickHook)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class K3 {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool doAttach);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    public struct RECT { public int L, T, R, B; }
    public static string Class(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static IntPtr FocusOf(IntPtr hwnd) {
        int pid; uint t = GetWindowThreadProcessId(hwnd, out pid);
        int cur = K3.GetCurrentThreadId();
        IntPtr f = IntPtr.Zero;
        if (t != 0) { AttachThreadInput(cur, (int)t, true); f = GetFocus(); AttachThreadInput(cur, (int)t, false); }
        return f;
    }
}
"@
[void][K3]::SetProcessDPIAware()

# 深色面板上只应出现一条亮块（我们画的光标）。编辑控件的字形若漏画出来会变成多簇。
function BrightCols($bmp) {
    $W = $bmp.Width; $H = $bmp.Height
    $set = @{}
    for ($y = 4; $y -lt $H - 4; $y++) {
        for ($x = 4; $x -lt $W - 4; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.R -gt 150 -and $c.G -gt 150 -and $c.B -gt 150) { $set[$x] = 1 }
        }
    }
    return @($set.Keys | Sort-Object)
}

function Clusters($cols) {
    $out = @(); $run = @()
    foreach ($x in $cols) {
        if ($run.Count -eq 0 -or $x -eq $run[-1] + 1) { $run += $x } else { $out += , @($run); $run = @($x) }
    }
    if ($run.Count -gt 0) { $out += , @($run) }
    return $out
}

# 反向测试：检查器本身必须能发现字形漏出来，否则它只是摆设
if ($SelfTest) {
    $bmp = New-Object System.Drawing.Bitmap 68, 47
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(24, 26, 31))
    $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 236, 244))
    $g.FillRectangle($b, 24, 12, 4, 22)
    $g.FillRectangle($b, 40, 14, 6, 18)
    $g.FillRectangle($b, 50, 14, 6, 18)
    $g.FillRectangle($b, 60, 14, 6, 18)
    $g.Dispose(); $b.Dispose()
    $n = @(Clusters (BrightCols $bmp)).Count
    $bmp.Dispose()
    if ($n -ge 4) { Write-Host "  reverse-test ok: synthetic 4 blocks detected $n"; exit 0 }
    Write-Host "  reverse-test FAIL: synthetic 4 blocks detected only $n"
    exit 1
}

function Invoke-Once([bool]$withTestPick) {
    $sf = Join-Path $env:TEMP ("kisapper-pickprobe-" + [guid]::NewGuid().ToString("N") + ".txt")
    $env:KISAPPER_STATE_FILE = $sf
    if ($withTestPick) { $env:KISAPPER_TEST_PICK = "1" } else { Remove-Item Env:\KISAPPER_TEST_PICK -ErrorAction SilentlyContinue }
    $pp = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
    Start-Sleep -Milliseconds 1800
    $txt = "(no state file)"
    if (Test-Path $sf) { $txt = (Get-Content $sf -Raw).Trim() }
    Stop-Process -Id $pp.Id -Force -ErrorAction SilentlyContinue
    if (Test-Path $sf) { Remove-Item $sf -Force }
    return $txt
}

# 取色钩子：没有真鼠标也要能确认全局钩子确实挂上了（钩子挂不上 = 用户看到的"点了没反应"）
if ($PickHook) {
    $off = Invoke-Once $false
    $on = Invoke-Once $true
    Write-Host "baseline: $off"
    Write-Host "testpick: $on"
    $ok = $true
    if ($on -notmatch "picking=1") { Write-Host "FAIL pick mode did not start" -ForegroundColor Red; $ok = $false }
    if ($on -notmatch "hook=1") { Write-Host "FAIL WH_MOUSE_LL hook not installed - clicking cannot apply color" -ForegroundColor Red; $ok = $false }
    if ($off -match "picking=1" -or $off -match "hook=1") { Write-Host "FAIL baseline already picking (check is vacuous)" -ForegroundColor Red; $ok = $false }
    if ($ok) { Write-Host "`nPICK HOOK PASSED"; exit 0 }
    exit 1
}

$state = Join-Path $env:TEMP ("kisapper-hostprobe-" + [guid]::NewGuid().ToString("N") + ".txt")
$env:KISAPPER_STATE_FILE = $state
if (Test-Path $state) { Remove-Item $state -Force }

$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle
$f = [K3]::FocusOf($h)
Write-Host "main=$h focus=$f focusClass=$([K3]::Class($f))"

function ReadState { if (Test-Path $state) { (Get-Content $state -Raw).Trim() } else { "(no state file)" } }
Write-Host "before: $(ReadState)"

$text = "The quick brown fox jumps over 13 lazy dogs, again and again 0123456789"
foreach ($ch in $text.ToCharArray()) {
    [void][K3]::SendMessage($f, 0x0102, [IntPtr][int]$ch, [IntPtr]::Zero)
}
Start-Sleep -Milliseconds 800
Write-Host "after:  $(ReadState)"

$r = New-Object K3+RECT
[void][K3]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T

$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$Scale = [Math]::Round($g0.DpiX / 96.0, 0)
$g0.Dispose()
# 逻辑常量 pad=6 caretW=2 tail=20 -> 常态宽 34，光标钉在 x=12（逻辑 px）
$expW = [int](34 * $Scale); $expCaretX = [int](12 * $Scale)
Write-Host "rect ${w}x${hh} dpi=$Scale  width should stay $expW after 71 chars"

$counts = @()
$caretAt = @()
for ($i = 0; $i -lt 6; $i++) {
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    if ($i -eq 0) { $bmp.Save("$PSScriptRoot\shot-hostprobe.png") }
    $cl = @(Clusters (BrightCols $bmp))
    $counts += $cl.Count
    if ($cl.Count -eq 1) { $caretAt += $cl[0][0] }
    if ($i -eq 0) { foreach ($c in $cl) { Write-Host ("  block cols {0}-{1} width {2}" -f $c[0], $c[-1], $c.Count) } }
    $g.Dispose(); $bmp.Dispose()
    Start-Sleep -Milliseconds 260
}
Write-Host "blocks per frame = $($counts -join ',')  (0 = caret blink off)"

$bad = @($counts | Where-Object { $_ -gt 1 })
$alive = @($counts | Where-Object { $_ -eq 1 })
$ok = $true
if ($bad.Count -gt 0) { Write-Host "FAIL glyphs leaked (>1 bright block in a frame)" -ForegroundColor Red; $ok = $false }
if ($alive.Count -lt 2) { Write-Host "FAIL caret never drawn" -ForegroundColor Red; $ok = $false }
if ([Math]::Abs($w - $expW) -gt 4) { Write-Host "FAIL window grew: got $w want $expW" -ForegroundColor Red; $ok = $false }
if ($caretAt.Count -ge 2) {
    $worst = 0
    foreach ($x in $caretAt) { $d = [Math]::Abs($x - $expCaretX); if ($d -gt $worst) { $worst = $d } }
    if ($worst -gt [int](3 * $Scale)) { Write-Host "FAIL caret column $($caretAt -join ',') not pinned near $expCaretX" -ForegroundColor Red; $ok = $false }
    else { Write-Host "  caret column = $($caretAt -join ',') (want $expCaretX)" }
} else { Write-Host "FAIL caret column not measured" -ForegroundColor Red; $ok = $false }
$st = ReadState
if ($st -notmatch "len=71") { Write-Host "FAIL text not in model: $st" -ForegroundColor Red; $ok = $false }
if ($st -notmatch "imediag=ctx=1") { Write-Host "FAIL host has no IME context, Chinese cannot be typed" -ForegroundColor Red; $ok = $false }

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
if (Test-Path $state) { Remove-Item $state -Force }
if ($ok) { Write-Host "`nHOST PROBE PASSED" -ForegroundColor Green; exit 0 }
exit 1
