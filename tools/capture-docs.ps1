param([string]$Out = "$PSScriptRoot\..\docs\images")
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class CD {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out P p);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(int a, int b, bool d);
  [DllImport("user32.dll")] public static extern IntPtr GetFocus();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rr,B; }
  public static IntPtr FocusOf(IntPtr hwnd){int pid;uint t=GetWindowThreadProcessId(hwnd,out pid);int c=GetCurrentThreadId();
    IntPtr f=IntPtr.Zero; if(t!=0){AttachThreadInput(c,(int)t,true);f=GetFocus();AttachThreadInput(c,(int)t,false);} return f;}
}
"@
[void][CD]::SetProcessDPIAware()
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }
$Out = (Resolve-Path $Out).Path

function GrabZoom([IntPtr]$h, [int]$scale, [string]$name) {
  $r = New-Object CD+R; [void][CD]::GetWindowRect($h, [ref]$r)
  $w = $r.Rr - $r.L; $hh = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $hh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
  $big = New-Object System.Drawing.Bitmap ($w*$scale), ($hh*$scale)
  $g2 = [System.Drawing.Graphics]::FromImage($big)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $g2.DrawImage($bmp, 0, 0, $w*$scale, $hh*$scale); $g2.Dispose(); $bmp.Dispose()
  $big.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()
  Write-Host "  $name  ($w x $hh -> $($w*$scale) x $($hh*$scale))"
}

function Launch([bool]$pick) {
  if ($pick) { $env:KISAPPER_TEST_PICK = "1" } else { Remove-Item Env:\KISAPPER_TEST_PICK -ErrorAction SilentlyContinue }
  $pp = Start-Process -FilePath (Resolve-Path "$PSScriptRoot\..\bin\kisappear.exe").Path -PassThru
  Start-Sleep -Milliseconds 1700
  return $pp
}

# --- 1) idle: only a caret
$p1 = Launch $false
Start-Sleep -Milliseconds 600
GrabZoom $p1.MainWindowHandle 4 "01-idle.png"

# --- 2) typed a lot: still invisible, width unchanged
$f1 = [CD]::FocusOf($p1.MainWindowHandle)
foreach ($ch in "The quick brown fox 1234567890".ToCharArray()) {
  [void][CD]::SendMessage($f1, 0x0102, [IntPtr][int][char]$ch, [IntPtr]::Zero)
}
Start-Sleep -Milliseconds 700
GrabZoom $p1.MainWindowHandle 4 "02-typed.png"

# --- 3) hover: slide the window under the real mouse so the app's own hover poll fires
$c = New-Object CD+P; [void][CD]::GetCursorPos([ref]$c)
$r = New-Object CD+R; [void][CD]::GetWindowRect($p1.MainWindowHandle, [ref]$r)
$w = $r.Rr - $r.L; $hh = $r.B - $r.T
[void][CD]::SetWindowPos($p1.MainWindowHandle, [IntPtr]::Zero, ([int]$c.X - [int]($w/2)), ([int]$c.Y - [int]($hh/2)), 0, 0, 0x0001 -bor 0x0010)
Start-Sleep -Milliseconds 900
GrabZoom $p1.MainWindowHandle 4 "03-hover.png"
Stop-Process -Id $p1.Id -Force -ErrorAction SilentlyContinue

# --- 4) pick mode, entered the way a user enters it: hover to expand, then click the eyedropper.
#        KISAPPER_TEST_PICK is no good here: the hover poll freezes while picking, so the status bar never shows.
$p2 = Launch $false
$c2 = New-Object CD+P; [void][CD]::GetCursorPos([ref]$c2)
$r2 = New-Object CD+R; [void][CD]::GetWindowRect($p2.MainWindowHandle, [ref]$r2)
$w2 = $r2.Rr - $r2.L; $h2 = $r2.B - $r2.T
[void][CD]::SetWindowPos($p2.MainWindowHandle, [IntPtr]::Zero, ([int]$c2.X - 20), ([int]$c2.Y - [int]($h2/2)), 0, 0, 0x0001 -bor 0x0010)
Start-Sleep -Milliseconds 900
$f2 = [CD]::FocusOf($p2.MainWindowHandle)
# 取色按钮在展开后的右侧第三格附近；点它 = 进入取色模式（消息投给宿主，由它转发给窗口）
$bp = [IntPtr](272 -bor ([int]($h2/2) -shl 16))
[void][CD]::SendMessage($f2, 0x0201, [IntPtr]1, $bp)
Start-Sleep -Milliseconds 250
[void][CD]::SendMessage($f2, 0x0202, [IntPtr]0, $bp)
Start-Sleep -Milliseconds 900
GrabZoom $p2.MainWindowHandle 4 "04-pick.png"
Stop-Process -Id $p2.Id -Force -ErrorAction SilentlyContinue
Write-Host "saved to $Out"
