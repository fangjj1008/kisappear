param([string]$Name = "shot-idle", [int]$Factor = 8)
Add-Type -AssemblyName System.Drawing
$src = Join-Path $PSScriptRoot "$Name.png"
$bmp = New-Object System.Drawing.Bitmap $src
$w = $bmp.Width * $Factor
$h = $bmp.Height * $Factor
$out = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($out)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($bmp, 0, 0, $w, $h)
$g.Dispose()
$dst = Join-Path $PSScriptRoot "big-$Name.png"
$out.Save($dst)
$out.Dispose()
$bmp.Dispose()
Write-Host "$dst ${w}x${h} (from $($bmp.Width)x$($bmp.Height))"
