$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class K {
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string win);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool attach);
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static IntPtr FocusOf(IntPtr hwnd) {
        int pid; uint t = GetWindowThreadProcessId(hwnd, out pid);
        int cur = GetCurrentThreadId();
        IntPtr f = IntPtr.Zero;
        if (t != 0 && t != (uint)cur) {
            AttachThreadInput(cur, (int)t, true);
            f = GetFocus();
            AttachThreadInput(cur, (int)t, false);
        } else { f = GetFocus(); }
        return f;
    }
}
"@
[void][K]::SetProcessDPIAware()

$state = Join-Path $env:TEMP "kisapper-kbd-state.txt"
if (Test-Path $state) { Remove-Item $state -Force }
$env:KISAPPER_STATE_FILE = $state
$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle
$child = [K]::FindWindowEx($h, [IntPtr]::Zero, $null, $null)
Write-Host "main=$h  child(输入宿主)=$child"
Write-Host "该线程焦点窗口 = $([K]::FocusOf($h))"

function ReadState { if (Test-Path $state) { Get-Content $state -Raw } else { "(无)" } }
Write-Host "初始: $(ReadState)"

Write-Host "`n-- 直接向子控件 HWND 发 WM_CHAR('A','B','C') --"
foreach ($ch in @('A','B','C')) {
    [void][K]::SendMessage($child, 0x0102, [IntPtr][int][char]$ch, [IntPtr]::Zero)
}
Start-Sleep -Milliseconds 600
Write-Host "  $(ReadState)"

Write-Host "`n-- 再发一个 WM_KEYDOWN/UP Backspace --"
[void][K]::SendMessage($child, 0x0100, [IntPtr]8, [IntPtr]::Zero)
[void][K]::SendMessage($child, 0x0101, [IntPtr]8, [IntPtr]::Zero)
[void][K]::PostMessage($child, 0x0102, [IntPtr]8, [IntPtr]::Zero)
Start-Sleep -Milliseconds 600
Write-Host "  $(ReadState)"

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $state -Force -ErrorAction SilentlyContinue
