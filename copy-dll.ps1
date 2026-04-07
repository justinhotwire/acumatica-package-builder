# copy-dll.ps1
# Copies AcuSales.Core.dll to Acumatica via temp copy

$ErrorActionPreference = "Stop"

$src = "c:\Users\JustinBoyd\OneDrive - hotwiretech.com\Repos\AcuSales\AcuSales.Core\bin\Release\AcuSales.Core.dll"
$tmp = "$env:TEMP\AcuSales.Core.dll"
$dst = "C:\Program Files\Acumatica ERP\AcumaticaERP\Bin\AcuSales.Core.dll"

Write-Host "Source: $src"
Write-Host "Temp: $tmp"
Write-Host "Destination: $dst"

# Check source exists
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "ERROR: Source not found" -ForegroundColor Red
    exit 1
}

Write-Host "Source exists, size: $((Get-Item -LiteralPath $src).Length) bytes"

# Copy to temp first (to avoid OneDrive issues)
try {
    [System.IO.File]::Copy($src, $tmp, $true)
    Write-Host "Copied to temp" -ForegroundColor Cyan
} catch {
    Write-Host "ERROR copying to temp: $_" -ForegroundColor Red
    exit 1
}

# Copy from temp to destination
try {
    Copy-Item -Path $tmp -Destination $dst -Force
    Write-Host "SUCCESS: DLL deployed to Acumatica" -ForegroundColor Green
} catch {
    Write-Host "ERROR copying to destination: $_" -ForegroundColor Red
    exit 1
}

# Verify
if (Test-Path $dst) {
    $info = Get-Item $dst
    Write-Host "Verified: $dst ($($info.Length) bytes)" -ForegroundColor Green
}
