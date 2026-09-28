param([string]$Name = "shot-idle")
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap (Join-Path $PSScriptRoot "$Name.png")
Write-Host "size $($bmp.Width)x$($bmp.Height)"
for ($y = 0; $y -lt $bmp.Height; $y++) {
    $line = ""
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $c = $bmp.GetPixel($x, $y)
        $lum = ($c.R + $c.G + $c.B) / 3
        if ($lum -lt 40) { $ch = "." }
        elseif ($lum -lt 90) { $ch = "-" }
        elseif ($lum -lt 150) { $ch = "+" }
        elseif ($lum -lt 210) { $ch = "o" }
        else { $ch = "#" }
        $line += $ch
    }
    Write-Host ("{0,3} {1}" -f $y, $line)
}
$bmp.Dispose()
