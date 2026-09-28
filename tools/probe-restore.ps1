$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class R {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public const uint WM_SYSCOMMAND = 0x112;
    public static IntPtr SC_MIN = (IntPtr)0xF020, SC_RESTORE = (IntPtr)0xF120;
    public struct RECT { public int L, T, Rt, B; }
}
"@
[void][R]::SetProcessDPIAware()

$state = Join-Path $env:TEMP "kisapper-restore-state.txt"
if (Test-Path $state) { Remove-Item $state -Force }
$env:KISAPPER_STATE_FILE = $state
$p = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
Start-Sleep -Milliseconds 1600
$h = $p.MainWindowHandle

function Report($tag) {
    $rc = New-Object R+RECT
    [void][R]::GetWindowRect($h, [ref]$rc)
    $w = $rc.Rt - $rc.L; $hh = $rc.B - $rc.T
    $st = [R]::GetWindowLong($h, -16)
    $s = if (Test-Path $state) { Get-Content $state -Raw } else { "(无)" }
    Write-Host ("{0}: rect {1}x{2} @ {3},{4}  iconic={5} style=0x{6:X8}  state: {7}" -f $tag, $w, $hh, $rc.L, $rc.T, [R]::IsIconic($h), $st, $s)
    $bmp = New-Object System.Drawing.Bitmap ([Math]::Max(1,$w)), ([Math]::Max(1,$hh))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rc.L, $rc.T, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save("$PSScriptRoot\restore-$tag.png")
    $bmp.Dispose()
}

Report "before"
[void][R]::PostMessage($h, [R]::WM_SYSCOMMAND, [R]::SC_MIN, [IntPtr]::Zero)
Start-Sleep -Milliseconds 900
Report "minimized"
[void][R]::PostMessage($h, [R]::WM_SYSCOMMAND, [R]::SC_RESTORE, [IntPtr]::Zero)
Start-Sleep -Milliseconds 1200
Report "restored"
Write-Host "  foreground = $([R]::GetForegroundWindow())  ours = $h"
Start-Sleep -Milliseconds 1500
Report "restored-later"

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $state -Force -ErrorAction SilentlyContinue
