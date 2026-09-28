param([string]$Out = (Join-Path $env:TEMP "Kisappear-ime-test.exe"))

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe not found" }

$srcs = Get-ChildItem (Join-Path $root "src\*.cs") | ForEach-Object { $_.FullName }
$icon = Join-Path $root "图标.png"
$res = @()
if (Test-Path $icon) { $res = @("/resource:$icon,Kisappear.AppIcon") }

& $csc /nologo /target:winexe /optimize+ "/out:$Out" `
    "/reference:System.dll" "/reference:System.Core.dll" "/reference:System.Drawing.dll" "/reference:System.Windows.Forms.dll" `
    "/codepage:65001" $res $srcs
if ($LASTEXITCODE -ne 0) { throw "compile failed" }
Write-Host "compiled -> $Out"
