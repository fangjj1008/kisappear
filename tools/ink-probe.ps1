param([string]$Path = "$PSScriptRoot\shot-idle.png", [double]$Scale = 2)
Add-Type -AssemblyName System.Drawing
$Ink = @(
    , @(232, 236, 244)
    , @(108, 116, 130)
    , @(150, 156, 168)
    , @(96, 160, 255)
    , @(74, 82, 98)
)
$b = New-Object System.Drawing.Bitmap $Path
$W = $b.Width; $H = $b.Height
$rad = [int](6 * $Scale)
$set = @{}
for ($x = 2; $x -lt ($W - 2); $x++) {
    for ($y = 2; $y -lt ($H - 2); $y++) {
        $dx = 0; $dy = 0
        if ($x -lt $rad) { $dx = $rad - $x }
        elseif ($x -ge ($W - $rad)) { $dx = $x - ($W - $rad - 1) }
        if ($y -lt $rad) { $dy = $rad - $y }
        elseif ($y -ge ($H - $rad)) { $dy = $y - ($H - $rad - 1) }
        if (($dx * $dx + $dy * $dy) -gt ($rad * $rad)) { continue }
        $c = $b.GetPixel($x, $y)
        foreach ($k in $Ink) {
            if ([Math]::Abs($c.R - $k[0]) -le 26 -and [Math]::Abs($c.G - $k[1]) -le 26 -and [Math]::Abs($c.B - $k[2]) -le 26) {
                $set[$x] = 1
                break
            }
        }
    }
}
$b.Dispose()
$cols = @($set.Keys | Sort-Object)
Write-Host "image $W x $H, ink columns ($($cols.Count)): $($cols -join ',')"
