# open-publish.ps1
# Opens SM204505 in browser to publish a customization project
# After direct-upload.ps1, use this to complete the publish step

param(
    [string]$ProjectName,
    [string]$AcumaticaUrl = "http://localhost/AcumaticaERP"
)

$ErrorActionPreference = "Stop"

function Write-Status { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }

Write-Host ""
Write-Host "=== Acumatica Publish Helper ===" -ForegroundColor Magenta

# Build URL for SM204505
$screenUrl = "$AcumaticaUrl/Main?ScreenId=SM204505"

Write-Status "Opening SM204505 (Customization Projects)..."
Write-Status "URL: $screenUrl"

# Open in default browser
Start-Process $screenUrl

Write-Host ""
Write-Success "Browser opened!"
Write-Host ""
Write-Host "=== Manual Steps ===" -ForegroundColor Yellow

if ($ProjectName) {
    Write-Host "1. Login if prompted" -ForegroundColor White
    Write-Host "2. Select project: $ProjectName" -ForegroundColor White
    Write-Host "3. Click 'Publish' button" -ForegroundColor White
    Write-Host "4. Wait for publish to complete" -ForegroundColor White
} else {
    Write-Host "1. Login if prompted" -ForegroundColor White
    Write-Host "2. Select your project from the list" -ForegroundColor White
    Write-Host "3. Click 'Publish' button" -ForegroundColor White
    Write-Host "4. Wait for publish to complete" -ForegroundColor White
}

Write-Host ""
Write-Host "If screens don't appear after publish, run: iisreset" -ForegroundColor Gray
Write-Host ""
