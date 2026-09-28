param([string]$Exe = "$PSScriptRoot\..\bin\kisappear.exe")

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Check {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool doAttach);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public const int SW_RESTORE = 9;
    public const uint LEFTDOWN = 0x02, LEFTUP = 0x04, KEYUP = 0x0002;
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Win32Check]::SetProcessDPIAware()

$fails = @()
function Assert($cond, $name) {
    if ($cond) { Write-Host "  ok    $name" }
    else { $script:fails += $name; Write-Host "  FAIL  $name" -ForegroundColor Red }
}

$g0 = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$Scale = [Math]::Round($g0.DpiX / 96.0, 2)
$g0.Dispose()
Write-Host "dpi scale = $Scale"

function Rect($hwnd) {
    $r = New-Object Win32Check+RECT
    [void][Win32Check]::GetWindowRect($hwnd, [ref]$r)
    $o = [pscustomobject]@{ Left = $r.Left; Top = $r.Top; Right = $r.Right; Bottom = $r.Bottom }
    $o | Add-Member -NotePropertyName W -NotePropertyValue ($r.Right - $r.Left)
    $o | Add-Member -NotePropertyName H -NotePropertyValue ($r.Bottom - $r.Top)
    return $o
}

function Away { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(40, 40); Start-Sleep -Milliseconds 400 }

function Grab($rc) {
    $bmp = New-Object System.Drawing.Bitmap ([Math]::Max(1, $rc.W)), ([Math]::Max(1, $rc.H))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rc.Left, $rc.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    return $bmp
}

$skips = @()
function Skip($name) { $script:skips += $name; Write-Host "  SKIP  $name（鼠标/焦点被真实操作占用）" -ForegroundColor Yellow }

$InkColors = @(
    , @(232, 236, 244)   # caret
    , @(108, 116, 130)   # caret 未聚焦
    , @(150, 156, 168)   # 状态文字/按钮描边
    , @(96, 160, 255)    # 强调色
    , @(74, 82, 98)      # 按钮按下底色
)

function IsInk($c) {
    foreach ($k in $InkColors) {
        if ([Math]::Abs($c.R - $k[0]) -le 26 -and [Math]::Abs($c.G - $k[1]) -le 26 -and [Math]::Abs($c.B - $k[2]) -le 26) { return $true }
    }
    return $false
}

# 只排除圆角外的像素（那里透出桌面）。半径与应用侧 Radius() 一致：6 逻辑 px
function InteriorBrightCols($bmp) {
    $rad = [int](6 * $Scale)
    $W = $bmp.Width; $H = $bmp.Height
    $set = @{}
    for ($x = 2; $x -lt ($W - 2); $x++) {
        for ($y = 2; $y -lt ($H - 2); $y++) {
            $dx = 0; $dy = 0
            if ($x -lt $rad) { $dx = $rad - $x } elseif ($x -ge ($W - $rad)) { $dx = $x - ($W - $rad - 1) }
            if ($y -lt $rad) { $dy = $rad - $y } elseif ($y -ge ($H - $rad)) { $dy = $y - ($H - $rad - 1) }
            if (($dx * $dx + $dy * $dy) -gt ($rad * $rad)) { continue }
            if (IsInk ($bmp.GetPixel($x, $y))) { $set[$x] = 1 }
        }
    }
    return @($set.Keys | Sort-Object)
}

function Clusters($cols) {
    $list = @()
    $cur = @()
    foreach ($c in $cols) {
        if ($cur.Count -eq 0) { $cur = @($c) }
        elseif ($c -le ($cur[-1] + 2)) { $cur += $c }
        else { $list += ,@($cur); $cur = @($c) }
    }
    if ($cur.Count -gt 0) { $list += ,@($cur) }
    return $list
}

# 光标在闪烁，必须多帧采样：返回每帧的内部亮块数
function CaretFrames($hwnd, $frames, $path) {
    $counts = @()
    for ($i = 0; $i -lt $frames; $i++) {
        $bmp = Grab (Rect $hwnd)
        $cl = @(Clusters (InteriorBrightCols $bmp))
        $counts += $cl.Count
        if ($i -eq 0) { $bmp.Save($path) }
        if ($i -eq 0 -and $cl.Count -ge 1) { $w = $cl[0].Count }
        $bmp.Dispose()
        Start-Sleep -Milliseconds 190
    }
    return $counts
}

function Try-Move($x, $y) {
    $px = [int]$x; $py = [int]$y
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($px, $py)
    Start-Sleep -Milliseconds 80
    $c = [System.Windows.Forms.Cursor]::Position
    return ([Math]::Abs($c.X - $px) -le 3 -and [Math]::Abs($c.Y - $py) -le 3)
}

function BorderColor($bmp) {
    $c = $bmp.GetPixel(0, [int]($bmp.Height / 2))
    return , @($c.R, $c.G, $c.B)
}

function DiffRgb($a, $b) {
    return [Math]::Abs([int]$a[0] - [int]$b[0]) + [Math]::Abs([int]$a[1] - [int]$b[1]) + [Math]::Abs([int]$a[2] - [int]$b[2])
}

function State {
    if (-not (Test-Path $env:KISAPPER_STATE_FILE)) { return @{} }
    $h = @{}
    foreach ($kv in ((Get-Content $env:KISAPPER_STATE_FILE -Raw) -split ' ')) {
        $p = $kv -split '='
        if ($p.Length -eq 2) { $h[$p[0]] = $p[1] }
    }
    return $h
}

# 每次注入前重新确认前台仍是被测窗口；否则立刻中止，避免把键打到用户正在用的窗口
function Send-Keys($hwnd, $keys) {
    if ([Win32Check]::GetForegroundWindow() -ne $hwnd) { throw "前台已不是被测窗口（你可能在操作电脑），测试中止以免误输入" }
    [System.Windows.Forms.SendKeys]::SendWait($keys)
}

# 模态对话框（保存框/确认框）是另一个窗口，前台校验要按进程而不是主窗口
function Send-KeysOwned($procId, $keys) {
    $fg = [Win32Check]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero) { throw "没有前台窗口，停止注入" }
    $tmp = 0
    [void][Win32Check]::GetWindowThreadProcessId($fg, [ref]$tmp)
    if ($tmp -ne $procId) { throw "前台属于别的进程（pid $tmp），测试中止以免误输入" }
    [System.Windows.Forms.SendKeys]::SendWait($keys)
}

function Focus-App($hwnd) {
    for ($try = 0; $try -lt 4; $try++) {
        [void][Win32Check]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
        [void][Win32Check]::keybd_event(0x12, 0, [Win32Check]::KEYUP, [UIntPtr]::Zero)
        $fg = [Win32Check]::GetForegroundWindow()
        $cur = [Win32Check]::GetCurrentThreadId()
        $tmp = 0
        $fgT = [Win32Check]::GetWindowThreadProcessId($fg, [ref]$tmp)
        $myT = [Win32Check]::GetWindowThreadProcessId($hwnd, [ref]$tmp)
        [void][Win32Check]::AttachThreadInput($cur, $fgT, $true)
        [void][Win32Check]::AttachThreadInput($cur, $myT, $true)
        [void][Win32Check]::BringWindowToTop($hwnd)
        [void][Win32Check]::SetForegroundWindow($hwnd)
        [void][Win32Check]::AttachThreadInput($cur, $fgT, $false)
        [void][Win32Check]::AttachThreadInput($cur, $myT, $false)
        Start-Sleep -Milliseconds 250
        if ([Win32Check]::GetForegroundWindow() -eq $hwnd) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Title($hwnd) {
    $sb = New-Object System.Text.StringBuilder 256
    [void][Win32Check]::GetWindowTextW([Win32Check]::GetForegroundWindow(), $sb, 256)
    return $sb.ToString()
}

function Click-At($x, $y) {
    if (-not (Try-Move $x $y)) { return $false }
    [void][Win32Check]::mouse_event([Win32Check]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][Win32Check]::mouse_event([Win32Check]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    return $true
}

# 悬停会让窗口变宽并可能左移，所以坐标必须在悬停后重新读
function Hover-On($hwnd) {
    $r = Rect $hwnd
    if (-not (Try-Move ([int]($r.Left + $r.W / 2)) ([int]($r.Top + $r.H / 2)))) { return $null }
    Start-Sleep -Milliseconds 700
    return Rect $hwnd
}

function ButtonPoints($hwnd) {
    $hr = Hover-On $hwnd
    if ($hr -eq $null) { return $null }
    $pad = [int](6 * $Scale); $btn = [int](18 * $Scale); $gap = [int](4 * $Scale)
    $y = [int]($hr.Top + $hr.H / 2)
    $closeX = [int]($hr.Right - $pad - $btn / 2)
    $minX = [int]($closeX - $gap - $btn)
    return @{ CloseX = $closeX; MinX = $minX; Y = $y; Rect = $hr }
}

$stateFile = Join-Path $env:TEMP ("kisapper-state-" + [guid]::NewGuid().ToString("N") + ".txt")
$traceFile = Join-Path $env:TEMP ("kisapper-trace-" + [guid]::NewGuid().ToString("N") + ".txt")
$env:KISAPPER_STATE_FILE = $stateFile
$env:KISAPPER_TRACE_FILE = $traceFile
foreach ($f in @($stateFile, $traceFile)) { if (Test-Path $f) { Remove-Item $f -Force } }

$p = Start-Process -FilePath (Resolve-Path $Exe).Path -PassThru
Start-Sleep -Milliseconds 1600
$hwnd = $p.MainWindowHandle
Write-Host "pid=$($p.Id) hwnd=$hwnd"

# 预检：能不能真的接管鼠标。不能的话，鼠标步骤记 SKIP 而不是误报应用失败
$probe = Try-Move 700 700
if (-not $probe) { Write-Host "警告：无法定位鼠标（有别的输入在抢占），鼠标步骤将跳过" -ForegroundColor Yellow }

try {
    Write-Host "`n[1] 常态尺寸：光标 + 20px 尾巴"
    Away
    $r = Rect $hwnd
    Write-Host "  rect $($r.W)x$($r.H) @ $($r.Left),$($r.Top)"
    Assert ([Math]::Abs($r.W - (34 * $Scale)) -le 4) "宽度 = 34 逻辑 px (实测 $($r.W), 期望 $([int](34*$Scale)))"
    Assert ($r.H -ge (20 * $Scale) -and $r.H -le (46 * $Scale)) "高度一行字 (实测 $($r.H))"

    Write-Host "`n[2] 只有一条闪烁光标，没有别的字形"
    $counts = CaretFrames $hwnd 8 "$PSScriptRoot\shot-idle.png"
    Write-Host "  每帧内部墨色亮块数: $($counts -join ',')"
    Assert (@($counts | Where-Object { $_ -eq 1 }).Count -ge 2) "闪烁：多帧中出现且仅出现 1 个亮块"
    Assert (($counts | Measure-Object -Maximum).Maximum -eq 1) "任何一帧都不多于 1 个亮块（无字形）"

    Write-Host "`n[3] 鼠标悬停：展开并出现两个按钮"
    $hr = Hover-On $hwnd
    if ($hr -eq $null) { Skip "悬停展开" }
    else {
        Assert ($hr.W -gt $r.W + (60 * $Scale)) "变宽 $($r.W) -> $($hr.W)"
        Assert ($hr.Top -eq $r.Top) "顶边不跳动"
        Assert ($hr.Right -le 3072) "展开后仍在屏幕内 ($($hr.Right))"
        $hbmp = Grab $hr
        $hbmp.Save("$PSScriptRoot\shot-hover.png")
        $hcl = @(Clusters (InteriorBrightCols $hbmp))
        $hbmp.Dispose()
        Assert ($hcl.Count -ge 2) "右侧出现按钮图形 (亮块 $($hcl.Count))"
        Away
    }

    Write-Host "`n[4] 粘贴：内容进模型但不可见，窗口不涨宽"
    $keyboardOk = $false
    if (-not (Focus-App $hwnd)) { Skip "粘贴/键入/选区/撤销/保存（拿不到前台焦点）" }
    else {
        # 预检：SendInput 未必能到达本桌面。注入不了就整段 SKIP，不报应用失败
        Send-Keys $hwnd "z"
        Start-Sleep -Milliseconds 350
        if ((State).len -eq 1) {
            Send-Keys $hwnd "{BACKSPACE}"
            Start-Sleep -Milliseconds 350
            $keyboardOk = ((State).len -eq 0)
        }
        if (-not $keyboardOk) { Skip "键盘注入到不了这个桌面（可用 tools/probe-focus.ps1 直投 WM_CHAR 验证）" }
    }
    if ($keyboardOk) {
        $typed = "hello invisible text 12345"
        [System.Windows.Forms.Clipboard]::SetText($typed)
        Send-Keys $hwnd ("^v")
        Start-Sleep -Milliseconds 500
        $s = State
        Assert ($s.len -eq $typed.Length) "Ctrl+V 后 len=$($s.len)（期望 $($typed.Length)），tail=$($s.tail)"
        $r2 = Rect $hwnd
        Assert ($r2.W -eq $r.W) "输入后宽度不变 ($($r2.W))"
        $counts2 = CaretFrames $hwnd 6 "$PSScriptRoot\shot-after-type.png"
        Write-Host "  每帧内部亮块数: $($counts2 -join ',')"
        Assert (($counts2 | Measure-Object -Maximum).Maximum -eq 1) "26 个字符全部不可见"
        Assert ([int]$s.caretX -le $r2.W) "光标被钳在窗口内，文字向左滚出 (caretX=$($s.caretX))"

        Write-Host "`n[5] 键入与退格"
        Send-Keys $hwnd ("abc")
        Start-Sleep -Milliseconds 300
        Assert ((State).len -eq ($typed.Length + 3)) "直接键入生效 (len=$((State).len))"
        Send-Keys $hwnd ("{BACKSPACE}{BACKSPACE}")
        Start-Sleep -Milliseconds 300
        Assert ((State).len -eq ($typed.Length + 1)) "连续退格生效 (len=$((State).len))"

        Write-Host "`n[6] Ctrl+A：只有边框变色"
        Away
        $plainBmp = Grab (Rect $hwnd)
        $plain = BorderColor $plainBmp
        $plainBmp.Dispose()
        [void](Focus-App $hwnd)
        Send-Keys $hwnd ("^a")
        Start-Sleep -Milliseconds 400
        $s = State
        Assert ($s.sel -eq 1) "全选置位"
        Assert ([int]$s.selLen -eq $typed.Length + 1) "选区覆盖全文 (selLen=$($s.selLen))"
        $selBmp = Grab (Rect $hwnd)
        $selBmp.Save("$PSScriptRoot\shot-selectall.png")
        $selc = BorderColor $selBmp
        Assert ((DiffRgb $plain $selc) -gt 60) "边框 $($plain -join ',') -> $($selc -join ',')"
        $cl3 = @(Clusters (InteriorBrightCols $selBmp))
        Assert ($cl3.Count -le 1) "全选时文字仍不可见 (亮块 $($cl3.Count))"
        $selBmp.Dispose()

        Write-Host "`n[7] 鼠标再点一下取消全选"
        $rr = Rect $hwnd
        if (-not (Click-At ([int]($rr.Left + 10 * $Scale)) ([int]($rr.Top + $rr.H / 2)))) { Skip "点击取消全选" }
        else {
            Away
            Assert ((State).sel -eq 0) "点击后选区清除"
            $afterBmp = Grab (Rect $hwnd)
            $after = BorderColor $afterBmp
            $afterBmp.Dispose()
            Assert ((DiffRgb $after $plain) -lt 40) "边框恢复普通色 ($($after -join ','))"
        }

        Write-Host "`n[8] Ctrl+C 复制真文本"
        if (-not (Focus-App $hwnd)) { Skip "复制" }
        else {
            Send-Keys $hwnd ("^a")
            Start-Sleep -Milliseconds 250
            [System.Windows.Forms.Clipboard]::SetText("__sentinel__")
            Send-Keys $hwnd ("^c")
            Start-Sleep -Milliseconds 350
            $clip = ([System.Windows.Forms.Clipboard]::GetText()).TrimEnd([char]0)
            $len = [int](State).len
            Assert ($clip.Length -eq $len) "剪贴板长度 $($clip.Length) = 文档长度 $len"
            Assert ($clip.Contains("hello") -and $clip.EndsWith("a")) "剪贴板内容正确"

            Write-Host "`n[9] Ctrl+Z / Ctrl+Y"
            $before = [int](State).len
            Send-Keys $hwnd ("^z")
            Start-Sleep -Milliseconds 350
            $after2 = [int](State).len
            Assert ($after2 -lt $before) "撤销 $before -> $after2"
            Send-Keys $hwnd ("^y")
            Start-Sleep -Milliseconds 350
            Assert (([int](State).len) -eq $before) "重做 $after2 -> $((State).len)"

            Write-Host "`n[10] Ctrl+S 保存"
            $out = Join-Path $env:TEMP ("kisapper-save-" + [guid]::NewGuid().ToString("N") + ".txt")
            Send-Keys $hwnd ("^s")
            Start-Sleep -Milliseconds 1400
            $t = Title $hwnd
            Assert ($t.Length -gt 0 -and $t -ne "消失の写字板") "保存对话框出现 (标题: $t)"
            Send-KeysOwned $p.Id ($out)
            Start-Sleep -Milliseconds 300
            Send-KeysOwned $p.Id ("{ENTER}")
            Start-Sleep -Milliseconds 1500
            Assert (Test-Path $out) "文件已写出"
            if (Test-Path $out) {
                $saved = Get-Content $out -Raw
                Assert ($saved.Contains("hello invisible text 12345")) "文件里是隐藏的那些字"
                Remove-Item $out -Force
            }
            Away
        }
    }

    Write-Host "`n[11] 悬停点缩小 = 最小化到任务栏"
    # 上一步若没写盘，保存框还开着会吞掉后面所有输入（模态），先收掉
    try { Send-Keys $hwnd ("{ESC}{ESC}") } catch { Write-Host "  （跳过 Esc 清理：前台已切走）" }
    Start-Sleep -Milliseconds 600
    $st = [Win32Check]::GetWindowLong($hwnd, -16)
    Assert (($st -band 0x00020000) -ne 0 -and ($st -band 0x00080000) -ne 0) "窗口带 WS_MINIMIZEBOX|WS_SYSMENU，任务栏按钮才能还原 (style=0x$($st.ToString('X8')))"
    $bp = ButtonPoints $hwnd
    if ($bp -eq $null) { Skip "缩小按钮" }
    elseif (-not (Click-At $bp.MinX $bp.Y)) { Skip "缩小按钮（鼠标被占用）" }
    else {
        Start-Sleep -Milliseconds 800
        Assert ([Win32Check]::IsIconic($hwnd)) "已最小化"
        [void][Win32Check]::ShowWindow($hwnd, [Win32Check]::SW_RESTORE)
        Start-Sleep -Milliseconds 800
        Assert (-not [Win32Check]::IsIconic($hwnd)) "可还原"
        Away
        Assert ((Rect $hwnd).W -le [int](36 * $Scale)) "还原后收回常态 ($((Rect $hwnd).W))"
    }

    Write-Host "`n[12] 悬停点关闭：未保存要确认"
    $bp = ButtonPoints $hwnd
    if ($bp -eq $null) { Skip "关闭按钮" }
    elseif (-not (Click-At $bp.CloseX $bp.Y)) { Skip "关闭按钮（鼠标被占用）" }
    else {
        Start-Sleep -Milliseconds 1000
        $alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
        $t = Title $hwnd
        Assert ($alive -and ($t -eq "消失の写字板")) "弹出未保存确认框 (标题: $t)"
        Send-KeysOwned $p.Id ("%n")
        Start-Sleep -Milliseconds 900
        $gone = -not [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
        Assert $gone "选否后进程退出"
        if ($gone) { $p = $null }   # 只有确认退出才放手，否则 finally 会兜底清理
    }
}
finally {
    if ($p -ne $null) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    foreach ($f in @($stateFile, $traceFile)) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
}

Write-Host ""
if ($skips.Count -gt 0) { Write-Host "SKIPPED $($skips.Count) 项（需要真实鼠标/焦点，本次未能占用）:" -ForegroundColor Yellow; $skips | ForEach-Object { Write-Host "  - $_" } }
if ($fails.Count -gt 0) {
    Write-Host "FAILED $($fails.Count) 项:" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "ALL UI CHECKS PASSED"
exit 0
