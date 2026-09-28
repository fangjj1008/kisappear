$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class K2 {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool attach);
    [DllImport("user32.dll")] public static extern IntPtr GetFocus();
    [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    public static string Class(IntPtr h) {
        var sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }
    public static IntPtr FocusOf(IntPtr hwnd) {
        int pid; uint t = GetWindowThreadProcessId(hwnd, out pid);
        int cur = GetCurrentThreadId();
        IntPtr f = IntPtr.Zero;
        if (t != 0 && (int)t != cur) {
            AttachThreadInput(cur, (int)t, true);
            f = GetFocus();
            AttachThreadInput(cur, (int)t, false);
        } else { f = GetFocus(); }
        return f;
    }
}
"@
[void][K2]::SetProcessDPIAware()

$state = Join-Path $env:TEMP "kisapper-kbd2-state.txt"
if (Test-Path $state) { Remove-Item $state -Force }
$env:KISAPPER_STATE_FILE = $state
$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle
$f = [K2]::FocusOf($h)
Write-Host "main=$h class=$([K2]::Class($h))"
Write-Host "focus=$f valid=$([K2]::IsWindow($f)) class=$([K2]::Class($f)) parent=$([K2]::GetParent($f))"
$gp = [K2]::GetParent($f)
if ($gp -ne [IntPtr]::Zero) { Write-Host "parent class=$([K2]::Class($gp))" }

function ReadState { if (Test-Path $state) { (Get-Content $state -Raw) } else { "(无)" } }
Write-Host "before: $(ReadState)"

Write-Host "`n-- 向焦点窗口发 WM_CHAR('X','Y') --"
foreach ($ch in @('X','Y')) { [void][K2]::SendMessage($f, 0x0102, [IntPtr][int][char]$ch, [IntPtr]::Zero) }
Start-Sleep -Milliseconds 700
Write-Host "after:  $(ReadState)"

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $state -Force -ErrorAction SilentlyContinue
