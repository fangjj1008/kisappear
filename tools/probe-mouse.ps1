param([string]$Exe = "")
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

if ($Exe -eq "") { $Exe = Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe" }

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class M2 {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool doAttach);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    public static string Class(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static IntPtr FocusOf(IntPtr hwnd) {
        int pid; uint t = GetWindowThreadProcessId(hwnd, out pid);
        int cur = GetCurrentThreadId();
        IntPtr f = IntPtr.Zero;
        if (t != 0) { AttachThreadInput(cur, (int)t, true); f = GetFocus(); AttachThreadInput(cur, (int)t, false); }
        return f;
    }
}
"@
[void][M2]::SetProcessDPIAware()

$state = Join-Path $env:TEMP ("kisapper-mouse-" + [guid]::NewGuid().ToString("N") + ".txt")
$env:KISAPPER_STATE_FILE = $state
if (Test-Path $state) { Remove-Item $state -Force }

function ReadState { if (Test-Path $state) { (Get-Content $state -Raw).Trim() } else { "(no state file)" } }

$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle

# 找到真正吃点击的那个控件：铺满客户区的输入宿主（WinForms 子窗口枚举不到它，取焦点句柄）
$host2 = [M2]::FocusOf($h)
$par = if ($host2 -ne [IntPtr]::Zero) { [M2]::GetParent($host2) } else { [IntPtr]::Zero }
Write-Host "main=$h host=$host2 class=$([M2]::Class($host2)) parent=$par"
if ($host2 -eq [IntPtr]::Zero) { Write-Host "FAIL cannot find the edit host child"; Stop-Process -Id $p.Id -Force; exit 1 }
if ($par -ne $h) { Write-Host "FAIL host is not a child of the main window - routing test invalid"; Stop-Process -Id $p.Id -Force; exit 1 }

$before = ReadState
Write-Host "before: $before"

# 向宿主控件投一次左键按下+抬起（点在我们画的文本区，不是按钮）
# lParam = MAKEINTPARAM(x, y)，x/y 是控件客户区坐标；宿主铺满客户区且位于 (0,0)，父窗口坐标一致
$lParam = [IntPtr](24 -bor (20 -shl 16))
[void][M2]::SendMessage($host2, 0x0201, [IntPtr]1, $lParam)      # WM_LBUTTONDOWN, MK_LBUTTON
Start-Sleep -Milliseconds 200
[void][M2]::SendMessage($host2, 0x0202, [IntPtr]0, $lParam)      # WM_LBUTTONUP
Start-Sleep -Milliseconds 700

$after = ReadState
Write-Host "after:  $after"

$ok = $true
if ($before -notmatch "lastMouse=none") {
    Write-Host "FAIL baseline already has lastMouse - assertion is vacuous" -ForegroundColor Red; $ok = $false
}
if ($after -notmatch "lastMouse=up@24,20") {
    Write-Host "FAIL the click never reached the form - host is eating mouse input" -ForegroundColor Red; $ok = $false
}
if ($after -notmatch "lastMouse=down@24,20") {
    Write-Host "note: down event not in the last dump (up overwrote it) - check up only" -ForegroundColor Yellow
}

# 右键也要转给父窗口，否则右键菜单/拖动全废
[void][M2]::SendMessage($host2, 0x0204, [IntPtr]2, $lParam)      # WM_RBUTTONDOWN, MK_RBUTTON
Start-Sleep -Milliseconds 200
[void][M2]::SendMessage($host2, 0x0205, [IntPtr]0, $lParam)      # WM_RBUTTONUP
Start-Sleep -Milliseconds 700
$rr = ReadState
Write-Host "right:  $rr"
if ($rr -notmatch "lastMouse=up@24,20/Right") {
    Write-Host "FAIL right click did not reach the form" -ForegroundColor Red; $ok = $false
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
if (Test-Path $state) { Remove-Item $state -Force }
if ($ok) { Write-Host "`nMOUSE ROUTING PASSED" -ForegroundColor Green; exit 0 }
exit 1
