# check-screen.ps1
# Quick check for screen errors using form-based login

param(
    [string]$ScreenID = "AS301000",
    [string]$AcumaticaUrl = "http://localhost/AcumaticaERP",
    [string]$Username = "admin",
    [string]$Password = "admin"
)

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    # Use form-based login instead of REST API
    $loginUrl = "$AcumaticaUrl/Frames/Login.aspx"

    # Get login page first (for viewstate)
    $loginPage = Invoke-WebRequest -Uri $loginUrl -SessionVariable session -UseBasicParsing

    # Extract hidden fields if needed
    $viewstate = ""
    if ($loginPage.Content -match '__VIEWSTATE.*?value="([^"]*)"') {
        $viewstate = $Matches[1]
    }

    # Try direct screen access with basic auth in URL
    $screenUrl = "$AcumaticaUrl/Main?ScreenId=$ScreenID"

    Write-Host "Checking $ScreenID..." -ForegroundColor Cyan
    Write-Host "URL: $screenUrl"

    # Access screen
    $response = Invoke-WebRequest -Uri $screenUrl -WebSession $session -TimeoutSec 60 -UseBasicParsing

    Write-Host ""
    Write-Host "=== Analysis for $ScreenID ===" -ForegroundColor Cyan

    # Check for specific error patterns
    $errors = @()
    $warnings = @()

    if ($response.Content -match "Server Error in") { $errors += "Server Error found" }
    if ($response.Content -match "PX\.Data\.PXException") { $errors += "PXException found" }
    if ($response.Content -match "ScreenId=00000000") { $errors += "Redirect to 00000000" }
    if ($response.Content -match "Object reference not set") { $errors += "Null reference error" }
    if ($response.Content -match "The page should be inherited") { $errors += "PXPage inheritance error" }
    if ($response.Content -match "aspxerror") { $errors += "ASP.NET error" }
    if ($response.Content -match "Login\.aspx") { $warnings += "Redirected to login page" }
    if ($response.Content -match "stack trace") { $errors += "Stack trace in response" }

    # Check title
    if ($response.Content -match "<title>([^<]+)</title>") {
        $title = $Matches[1]
        Write-Host "Page Title: $title"
        if ($title -match "Error|Exception") {
            $errors += "Error in page title: $title"
        }
    }

    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Content Length: $($response.Content.Length) chars"

    if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
        Write-Host "No critical errors detected!" -ForegroundColor Green
    } else {
        if ($warnings.Count -gt 0) {
            Write-Host "WARNINGS:" -ForegroundColor Yellow
            foreach ($w in $warnings) {
                Write-Host "  - $w" -ForegroundColor Yellow
            }
        }
        if ($errors.Count -gt 0) {
            Write-Host "ERRORS FOUND:" -ForegroundColor Red
            foreach ($err in $errors) {
                Write-Host "  - $err" -ForegroundColor Red
            }
        }
    }

} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
