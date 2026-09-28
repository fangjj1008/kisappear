param([switch]$Test)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path $csc)) { throw "csc.exe (.NET Framework 4) not found" }

$bin = Join-Path $root "bin"
New-Item -ItemType Directory -Force $bin | Out-Null

$refs = @(
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.Drawing.dll",
    "/reference:System.Windows.Forms.dll",
    "/codepage:65001"
)

if ($Test) {
    $srcs = @((Join-Path $root "src\LineMath.cs"), (Join-Path $root "tests\LineMathTests.cs"))
    $out = Join-Path $bin "LineMathTests.exe"
    & $csc /nologo /target:exe "/main:Kisappear.Tests.LineMathTests" "/out:$out" $refs $srcs
    if ($LASTEXITCODE -ne 0) { throw "test build failed" }
    & $out
    exit $LASTEXITCODE
}

$srcs = Get-ChildItem (Join-Path $root "src\*.cs") | ForEach-Object { $_.FullName }
$out = Join-Path $bin "kisappear.exe"
$icon = Join-Path $root "图标.png"
$res = @()
if (Test-Path $icon) { $res = @("/resource:$icon,Kisappear.AppIcon") } else { Write-Warning "图标.png 缺失，exe 将没有任务栏图标" }
& $csc /nologo /target:winexe /optimize+ "/out:$out" $refs $res $srcs
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Write-Host "built $out"
