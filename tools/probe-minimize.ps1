$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class P {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] public static extern IntPtr FindWindowW(string cls, string title);
    public static int GWL_STYLE = -16, GWL_EXSTYLE = -20;
    public const uint WM_SYSCOMMAND = 0x0112;
    public static IntPtr SC_RESTORE = (IntPtr)0xF120, SC_MINIMIZE = (IntPtr)0xF020;
}
"@

$state = Join-Path $env:TEMP "kisapper-probe-state.txt"
if (Test-Path $state) { Remove-Item $state -Force }
$env:KISAPPER_STATE_FILE = $state
$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1500
$h = $p.MainWindowHandle

function Dump($label) {
    $st = [P]::GetWindowLong($h, [P]::GWL_STYLE)
    $ex = [P]::GetWindowLong($h, [P]::GWL_EXSTYLE)
    Write-Host ("{0}: style=0x{1:X8} exstyle=0x{2:X8} visible={3} iconic={4} MINIMIZEBOX={5} SYSMENU={6} TOPMOST={7}" -f `
        $label, $st, $ex, [P]::IsWindowVisible($h), [P]::IsIconic($h),
        (($st -band 0x00020000) -ne 0), (($st -band 0x00080000) -ne 0), (($ex -band 0x8) -ne 0))
}

Dump "startup"

Write-Host "`n-- 用 SC_MINIMIZE 走任务栏同一条路径最小化 --"
[void][P]::PostMessage($h, [P]::WM_SYSCOMMAND, [P]::SC_MINIMIZE, [IntPtr]::Zero)
Start-Sleep -Milliseconds 800
Dump "after SC_MINIMIZE"
Write-Host "  state file: $(Get-Content $state -Raw)"

Write-Host "`n-- 任务栏点击实际发出的 SC_RESTORE --"
[void][P]::PostMessage($h, [P]::WM_SYSCOMMAND, [P]::SC_RESTORE, [IntPtr]::Zero)
Start-Sleep -Milliseconds 800
Dump "after SC_RESTORE"
Write-Host "  state file: $(Get-Content $state -Raw)"

Write-Host "`n-- 对比：ShowWindow(SW_RESTORE=9) --"
[void][P]::PostMessage($h, [P]::WM_SYSCOMMAND, [P]::SC_MINIMIZE, [IntPtr]::Zero)
Start-Sleep -Milliseconds 600
[void][P]::ShowWindow($h, 9)
Start-Sleep -Milliseconds 600
Dump "after ShowWindow(9)"

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $state -Force -ErrorAction SilentlyContinue
