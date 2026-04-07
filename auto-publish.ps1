# auto-publish.ps1
# Automates publishing a customization project in Acumatica
# Uses Selenium WebDriver to login and click Publish

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [string]$AcumaticaUrl = "http://localhost/AcumaticaERP",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [int]$TimeoutSeconds = 120,
    [switch]$RestartIIS = $true  # Restart IIS after publish (default: yes)
)

$ErrorActionPreference = "Stop"

function Write-Status { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Acumatica Auto-Publish ===" -ForegroundColor Magenta
Write-Host "Project: $ProjectName" -ForegroundColor White
Write-Host "URL: $AcumaticaUrl" -ForegroundColor White

# Check for Selenium WebDriver
$seleniumPath = "C:\Selenium"
$webDriverPath = "$seleniumPath\chromedriver.exe"
$seleniumDll = "$seleniumPath\WebDriver.dll"

if (-not (Test-Path $seleniumDll)) {
    Write-Status "Selenium not found. Installing..."

    # Create Selenium directory
    New-Item -ItemType Directory -Path $seleniumPath -Force | Out-Null

    # Download Selenium WebDriver NuGet package
    $nugetUrl = "https://www.nuget.org/api/v2/package/Selenium.WebDriver/4.16.2"
    $nugetZip = "$env:TEMP\selenium.nupkg"

    Write-Status "Downloading Selenium..."
    Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetZip

    # Extract DLL
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($nugetZip)
    $entry = $zip.Entries | Where-Object { $_.FullName -like "*net6.0/WebDriver.dll" } | Select-Object -First 1
    if ($entry) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $seleniumDll, $true)
    }
    $zip.Dispose()
    Remove-Item $nugetZip -Force

    Write-Success "Selenium installed"
}

if (-not (Test-Path $webDriverPath)) {
    Write-Status "ChromeDriver not found. Downloading..."

    # Get Chrome version
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chromePath)) {
        $chromePath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    }

    if (Test-Path $chromePath) {
        $chromeVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
        $majorVersion = $chromeVersion.Split('.')[0]
        Write-Status "Chrome version: $chromeVersion (major: $majorVersion)"

        # Download matching ChromeDriver
        $driverUrl = "https://storage.googleapis.com/chrome-for-testing-public/$chromeVersion/win64/chromedriver-win64.zip"
        $driverZip = "$env:TEMP\chromedriver.zip"

        try {
            Invoke-WebRequest -Uri $driverUrl -OutFile $driverZip
            Expand-Archive -Path $driverZip -DestinationPath $env:TEMP -Force
            Copy-Item "$env:TEMP\chromedriver-win64\chromedriver.exe" $webDriverPath -Force
            Remove-Item $driverZip -Force
            Remove-Item "$env:TEMP\chromedriver-win64" -Recurse -Force
            Write-Success "ChromeDriver installed"
        } catch {
            Write-Err "Failed to download ChromeDriver. Please install manually."
            Write-Err "Download from: https://chromedriver.chromium.org/downloads"
            exit 1
        }
    } else {
        Write-Err "Chrome not found. Please install Chrome or Edge."
        exit 1
    }
}

# Load Selenium
Write-Status "Loading Selenium..."
Add-Type -Path $seleniumDll

# Create Chrome options
$chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
$chromeOptions.AddArgument("--start-maximized")
$chromeOptions.AddArgument("--disable-extensions")

# Create ChromeDriver service
$driverService = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($seleniumPath)
$driverService.HideCommandPromptWindow = $true

Write-Status "Starting Chrome..."
$driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($driverService, $chromeOptions)

try {
    # Navigate to login
    $loginUrl = "$AcumaticaUrl/Frames/Login.aspx"
    Write-Status "Navigating to: $loginUrl"
    $driver.Navigate().GoToUrl($loginUrl)

    Start-Sleep -Seconds 2

    # Login
    Write-Status "Logging in as $Username..."

    $usernameField = $driver.FindElement([OpenQA.Selenium.By]::Id("txtUser"))
    $usernameField.Clear()
    $usernameField.SendKeys($Username)

    $passwordField = $driver.FindElement([OpenQA.Selenium.By]::Id("txtPass"))
    $passwordField.Clear()
    $passwordField.SendKeys($Password)

    $loginButton = $driver.FindElement([OpenQA.Selenium.By]::Id("btnLogin"))
    $loginButton.Click()

    Write-Status "Waiting for login..."
    Start-Sleep -Seconds 5

    # Navigate to SM204505
    $custUrl = "$AcumaticaUrl/Main?ScreenId=SM204505"
    Write-Status "Navigating to Customization Projects..."
    $driver.Navigate().GoToUrl($custUrl)

    Start-Sleep -Seconds 3

    # Wait for page to load
    Write-Status "Waiting for screen to load..."
    $wait = New-Object OpenQA.Selenium.Support.UI.WebDriverWait($driver, [TimeSpan]::FromSeconds(30))

    # Find and select the project
    Write-Status "Looking for project: $ProjectName"
    Start-Sleep -Seconds 2

    # Click on the project name in the grid
    $projectCell = $driver.FindElement([OpenQA.Selenium.By]::XPath("//td[contains(text(),'$ProjectName')]"))
    $projectCell.Click()

    Start-Sleep -Seconds 1

    # Find and click Publish button
    Write-Status "Clicking Publish..."
    $publishButton = $driver.FindElement([OpenQA.Selenium.By]::XPath("//div[contains(@id,'Publish')]//button | //button[contains(text(),'Publish')]"))
    $publishButton.Click()

    Write-Status "Publish initiated! Waiting for completion..."

    # Wait for publish to complete (look for success message or progress bar to disappear)
    $startTime = Get-Date
    $timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

    while (((Get-Date) - $startTime) -lt $timeout) {
        Start-Sleep -Seconds 5

        # Check for completion indicators
        try {
            $successMsg = $driver.FindElements([OpenQA.Selenium.By]::XPath("//*[contains(text(),'successfully')]"))
            if ($successMsg.Count -gt 0) {
                Write-Host ""
                Write-Success "Publish completed successfully!"
                break
            }
        } catch { }

        # Check for error
        try {
            $errorMsg = $driver.FindElements([OpenQA.Selenium.By]::XPath("//*[contains(@class,'error')]"))
            if ($errorMsg.Count -gt 0) {
                Write-Err "Publish failed! Check the screen for details."
                break
            }
        } catch { }

        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        Write-Host "`r  Publishing... ($elapsed/$TimeoutSeconds sec)" -NoNewline
    }

    Write-Host ""
    Write-Success "Auto-publish complete!"

    # Keep browser open briefly to see result
    Start-Sleep -Seconds 3

    # Restart IIS
    if ($RestartIIS) {
        Write-Host ""
        Write-Host "=== Restarting IIS ===" -ForegroundColor Magenta
        Write-Status "Running iisreset..."
        $iisResult = Start-Process -FilePath "iisreset" -Wait -PassThru -NoNewWindow
        if ($iisResult.ExitCode -eq 0) {
            Write-Success "IIS restarted successfully"
        } else {
            Write-Warn "IIS restart may have failed (exit code: $($iisResult.ExitCode))"
        }
    }

} catch {
    Write-Err "Automation error: $_"
    Write-Err "You may need to complete the publish manually in the browser."

    # Keep browser open on error
    Write-Host "Press Enter to close browser..."
    Read-Host
} finally {
    $driver.Quit()
}

Write-Host ""
