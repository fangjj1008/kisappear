$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Diag {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$awareBefore = [Diag]::IsProcessDPIAware()
[void][Diag]::SetProcessDPIAware()
$awareAfter = [Diag]::IsProcessDPIAware()

$scr = [System.Windows.Forms.Screen]::PrimaryScreen
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
Write-Host "ps dpi aware: before=$awareBefore after=$awareAfter"
Write-Host "screen bounds: $($scr.Bounds)  working: $($scr.WorkingArea)"
Write-Host "graphics dpi: $($g.DpiX) x $($g.DpiY)"
$g.Dispose()

$state = Join-Path $env:TEMP "kisapper-diag-state.txt"
$trace = Join-Path $env:TEMP "kisapper-diag-trace.txt"
if (Test-Path $state) { Remove-Item $state -Force }
if (Test-Path $trace) { Remove-Item $trace -Force }
$env:KISAPPER_STATE_FILE = $state
$env:KISAPPER_TRACE_FILE = $trace
$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1500
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(40, 40)
Start-Sleep -Milliseconds 400
$r = New-Object Diag+RECT
[void][Diag]::GetWindowRect($p.MainWindowHandle, [ref]$r)
Write-Host "hwnd=$($p.MainWindowHandle) rect=($($r.Left),$($r.Top))-($($r.Right),$($r.Bottom)) size=$($r.Right-$r.Left)x$($r.Bottom-$r.Top)"
Write-Host "app state: $(Get-Content $state -Raw)"
Write-Host "--- trace ---"
if (Test-Path $trace) { Get-Content $trace | ForEach-Object { Write-Host $_ } }
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $state -Force -ErrorAction SilentlyContinue
Remove-Item $trace -Force -ErrorAction SilentlyContinue
