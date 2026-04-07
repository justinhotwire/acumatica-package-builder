# find-logs.ps1 - Find Acumatica logs

# Common Acumatica install locations
$paths = @(
    "C:\inetpub\wwwroot\AcumaticaERP",
    "C:\Program Files\Acumatica ERP\AcumaticaERP",
    "C:\Acumatica\Site",
    "C:\AcumaticaERP"
)

# Find the Acumatica site
foreach ($path in $paths) {
    if (Test-Path $path) {
        Write-Host "Found Acumatica at: $path" -ForegroundColor Green

        # Look for logs
        $logPath = Join-Path $path "App_Data\Logs"
        if (Test-Path $logPath) {
            Write-Host "Logs at: $logPath" -ForegroundColor Cyan
            Get-ChildItem $logPath -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
                Write-Host ""
                Write-Host "=== $($_.Name) ===" -ForegroundColor Yellow
                Get-Content $_.FullName -Tail 50 | Select-String -Pattern "Exception|Error|AS301|AS302|AS401"
            }
        }

        # Check for error log in App_Data
        $errorLog = Join-Path $path "App_Data\error.log"
        if (Test-Path $errorLog) {
            Write-Host ""
            Write-Host "=== error.log ===" -ForegroundColor Red
            Get-Content $errorLog -Tail 30
        }

        break
    }
}

# Also check Event Viewer for recent ASP.NET errors
Write-Host ""
Write-Host "=== Recent Application Errors ===" -ForegroundColor Magenta
try {
    Get-WinEvent -LogName Application -MaxEvents 20 -ErrorAction SilentlyContinue |
        Where-Object { $_.LevelDisplayName -eq 'Error' -and $_.TimeCreated -gt (Get-Date).AddHours(-1) } |
        ForEach-Object {
            if ($_.Message -match 'Acumatica|ASP.NET|AS301|AS302|AS401') {
                Write-Host "$($_.TimeCreated): $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))..."
            }
        }
} catch {
    Write-Host "Could not read Event Viewer: $_" -ForegroundColor Yellow
}
