# test-screens.ps1
# AGGRESSIVE Acumatica screen tester - clicks EVERYTHING to find bugs
# Uses Edge WebDriver wire protocol

param(
    [string[]]$ScreenIDs = @("AS201000", "AS301000", "AS302000", "AS401500"),
    [string]$AcumaticaUrl = "http://localhost/AcumaticaERP",
    [string]$Username = "admin",
    [string]$Password = "admin",
    [int]$TimeoutSeconds = 30,
    [int]$DriverPort = 9515,
    [switch]$Aggressive = $true,
    [string]$ScreenshotDir = "$env:TEMP\AcumaticaScreenshots"
)

$ErrorActionPreference = "Stop"

function Write-Status { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Attack { param($msg) Write-Host "[ATTACK] $msg" -ForegroundColor Magenta }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Red
Write-Host "  AGGRESSIVE ACUMATICA SCREEN TESTER" -ForegroundColor Red
Write-Host "  Breaking things so you don't have to" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Red
Write-Host "Screens: $($ScreenIDs -join ', ')" -ForegroundColor White
Write-Host "Mode: $(if ($Aggressive) { 'AGGRESSIVE - Click everything' } else { 'Basic' })" -ForegroundColor Yellow

# Create screenshot directory
if (-not (Test-Path $ScreenshotDir)) {
    New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null
}

$seleniumPath = "C:\Selenium"
$driverProcess = $null
$sessionId = $null

# Detect browser - prefer Edge over Chrome
$edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgePath)) {
    $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    $chromePath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
}

$useEdge = Test-Path $edgePath
$useChrome = (-not $useEdge) -and (Test-Path $chromePath)

if (-not $useEdge -and -not $useChrome) {
    Write-Err "No supported browser found (Edge or Chrome required)"
    exit 1
}

# Setup WebDriver
if ($useEdge) {
    $webDriverPath = "$seleniumPath\msedgedriver.exe"
    $browserVersion = (Get-Item $edgePath).VersionInfo.ProductVersion
    Write-Status "Using Edge $browserVersion"

    if (-not (Test-Path $webDriverPath)) {
        Write-Status "EdgeDriver not found. Downloading..."
        New-Item -ItemType Directory -Path $seleniumPath -Force | Out-Null

        $driverUrl = "https://msedgewebdriverstorage.blob.core.windows.net/edgewebdriver/$browserVersion/edgedriver_win64.zip"
        $driverZip = "$env:TEMP\edgedriver.zip"

        try {
            Invoke-WebRequest -Uri $driverUrl -OutFile $driverZip
            Expand-Archive -Path $driverZip -DestinationPath "$env:TEMP\edgedriver" -Force
            Copy-Item "$env:TEMP\edgedriver\msedgedriver.exe" $webDriverPath -Force
            Remove-Item $driverZip -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\edgedriver" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "EdgeDriver installed"
        } catch {
            Write-Err "Failed to download EdgeDriver: $_"
            exit 1
        }
    }
} else {
    $webDriverPath = "$seleniumPath\chromedriver.exe"
    $browserVersion = (Get-Item $chromePath).VersionInfo.ProductVersion
    Write-Status "Using Chrome $browserVersion"

    if (-not (Test-Path $webDriverPath)) {
        Write-Status "ChromeDriver not found. Downloading..."
        New-Item -ItemType Directory -Path $seleniumPath -Force | Out-Null

        $driverUrl = "https://storage.googleapis.com/chrome-for-testing-public/$browserVersion/win64/chromedriver-win64.zip"
        $driverZip = "$env:TEMP\chromedriver.zip"

        try {
            Invoke-WebRequest -Uri $driverUrl -OutFile $driverZip
            Expand-Archive -Path $driverZip -DestinationPath $env:TEMP -Force
            Copy-Item "$env:TEMP\chromedriver-win64\chromedriver.exe" $webDriverPath -Force
            Remove-Item $driverZip -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\chromedriver-win64" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "ChromeDriver installed"
        } catch {
            Write-Err "Failed to download ChromeDriver: $_"
            exit 1
        }
    }
}

# WebDriver REST API helper functions
$baseUrl = "http://localhost:$DriverPort"

function Invoke-WebDriver {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [hashtable]$Body = $null
    )

    $uri = "$baseUrl$Endpoint"
    $params = @{
        Method = $Method
        Uri = $uri
        ContentType = "application/json"
    }

    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    try {
        $response = Invoke-RestMethod @params
        return $response
    } catch {
        $errorBody = $_.ErrorDetails.Message
        throw "WebDriver error: $errorBody"
    }
}

function New-Session {
    $capabilities = @{
        capabilities = @{
            alwaysMatch = @{}
        }
    }

    if ($useEdge) {
        $capabilities.capabilities.alwaysMatch = @{
            browserName = "MicrosoftEdge"
            "ms:edgeOptions" = @{
                args = @("--start-maximized", "--disable-extensions", "--disable-popup-blocking")
            }
        }
    } else {
        $capabilities.capabilities.alwaysMatch = @{
            browserName = "chrome"
            "goog:chromeOptions" = @{
                args = @("--start-maximized", "--disable-extensions", "--disable-popup-blocking")
            }
        }
    }

    $response = Invoke-WebDriver -Method POST -Endpoint "/session" -Body $capabilities
    return $response.value.sessionId
}

function Remove-Session {
    param([string]$SessionId)
    Invoke-WebDriver -Method DELETE -Endpoint "/session/$SessionId" | Out-Null
}

function Set-Url {
    param([string]$SessionId, [string]$Url)
    Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/url" -Body @{ url = $Url } | Out-Null
}

function Get-CurrentUrl {
    param([string]$SessionId)
    $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/url"
    return $response.value
}

function Get-PageSource {
    param([string]$SessionId)
    $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/source"
    return $response.value
}

function Get-Title {
    param([string]$SessionId)
    $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/title"
    return $response.value
}

function Find-Element {
    param([string]$SessionId, [string]$Using, [string]$Value)
    try {
        $response = Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element" -Body @{
            using = $Using
            value = $Value
        }
        if ($response.value.ELEMENT) {
            return $response.value.ELEMENT
        } elseif ($response.value.'element-6066-11e4-a52e-4f735466cecf') {
            return $response.value.'element-6066-11e4-a52e-4f735466cecf'
        }
    } catch {
        return $null
    }
    return $null
}

function Find-Elements {
    param([string]$SessionId, [string]$Using, [string]$Value)
    try {
        $response = Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/elements" -Body @{
            using = $Using
            value = $Value
        }
        $elements = @()
        foreach ($el in $response.value) {
            if ($el.ELEMENT) {
                $elements += $el.ELEMENT
            } elseif ($el.'element-6066-11e4-a52e-4f735466cecf') {
                $elements += $el.'element-6066-11e4-a52e-4f735466cecf'
            }
        }
        return $elements
    } catch {
        return @()
    }
}

function Send-Keys {
    param([string]$SessionId, [string]$ElementId, [string]$Text)
    Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element/$ElementId/value" -Body @{
        text = $Text
    } | Out-Null
}

function Click-Element {
    param([string]$SessionId, [string]$ElementId)
    try {
        Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element/$ElementId/click" -Body @{} | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Clear-Element {
    param([string]$SessionId, [string]$ElementId)
    try {
        Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element/$ElementId/clear" -Body @{} | Out-Null
    } catch { }
}

function Get-ElementAttribute {
    param([string]$SessionId, [string]$ElementId, [string]$Attribute)
    try {
        $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/element/$ElementId/attribute/$Attribute"
        return $response.value
    } catch {
        return $null
    }
}

function Get-ElementText {
    param([string]$SessionId, [string]$ElementId)
    try {
        $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/element/$ElementId/text"
        return $response.value
    } catch {
        return ""
    }
}

function Take-Screenshot {
    param([string]$SessionId, [string]$Filename)
    try {
        $response = Invoke-WebDriver -Method GET -Endpoint "/session/$SessionId/screenshot"
        $bytes = [Convert]::FromBase64String($response.value)
        $filepath = Join-Path $ScreenshotDir "$Filename.png"
        [IO.File]::WriteAllBytes($filepath, $bytes)
        return $filepath
    } catch {
        return $null
    }
}

function Press-Escape {
    param([string]$SessionId)
    try {
        # Send Escape key to body
        $body = Find-Element -SessionId $SessionId -Using "css selector" -Value "body"
        if ($body) {
            Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element/$body/value" -Body @{
                text = "`u{E00C}"  # Escape key
            } | Out-Null
        }
    } catch { }
}

function Check-ForErrors {
    param([string]$SessionId, [string]$ScreenId)

    $errors = @()
    $pageSource = Get-PageSource -SessionId $SessionId
    $title = Get-Title -SessionId $SessionId
    $currentUrl = Get-CurrentUrl -SessionId $SessionId

    # Error patterns to detect
    $errorPatterns = @(
        @{ Pattern = "Server Error"; Desc = "Server Error" },
        @{ Pattern = "ScreenId=00000000"; Desc = "Redirect to blank screen" },
        @{ Pattern = "Object reference not set"; Desc = "Null reference error" },
        @{ Pattern = "The page should be inherited"; Desc = "Missing PXPage inheritance" },
        @{ Pattern = "Operand type clash"; Desc = "SQL type mismatch" },
        @{ Pattern = "type clash"; Desc = "Type clash error" },
        @{ Pattern = "Invalid column name"; Desc = "Invalid SQL column" },
        @{ Pattern = "PXSelector attribute is missing"; Desc = "Missing PXSelector" },
        @{ Pattern = "cannot be found"; Desc = "DAC/Field not found" },
        @{ Pattern = "NullReferenceException"; Desc = "Null reference exception" },
        @{ Pattern = "ArgumentNullException"; Desc = "Argument null exception" },
        @{ Pattern = "InvalidOperationException"; Desc = "Invalid operation" },
        @{ Pattern = "An error has occurred"; Desc = "Generic error" },
        @{ Pattern = "Exception of type"; Desc = "Unhandled exception" },
        @{ Pattern = "Stack Trace:"; Desc = "Stack trace visible" }
    )

    foreach ($ep in $errorPatterns) {
        if ($pageSource -match [regex]::Escape($ep.Pattern)) {
            $errors += $ep.Desc
        }
    }

    # Check title for errors
    if ($title -match "Error|Exception|failed") {
        $errors += "Error in page title: $title"
    }

    # Check if redirected away from screen
    if ($currentUrl -notmatch $ScreenId -and $currentUrl -match "00000000") {
        $errors += "Redirected to invalid screen"
    }

    return $errors
}

# AGGRESSIVE field clicking function
function Attack-AllFields {
    param([string]$SessionId, [string]$ScreenId)

    $fieldErrors = @()
    $clickCount = 0

    Write-Attack "Attacking all fields on $ScreenId..."

    # Field selectors to attack (Acumatica-specific)
    $attackSelectors = @(
        # Input fields
        "input.editor_input",
        "input[type='text']",
        "textarea",

        # Dropdowns and selectors
        "div.editorCombo",
        "div[data-cmd='BtnOpenSelector']",
        "span.btnCont",
        "div.dropDownBtn",

        # Buttons in field controls
        "div.toolsBtn",
        "button.toolBarBtn",

        # Grid cells
        "td.GridRow",
        "div[class*='cell']",

        # Tab controls
        "span.tabHeader",
        "div.tabHeaderContent",

        # Any clickable control
        "div[onclick]",
        "span[onclick]"
    )

    foreach ($selector in $attackSelectors) {
        $elements = Find-Elements -SessionId $SessionId -Using "css selector" -Value $selector

        if ($elements.Count -gt 0) {
            Write-Status "  Found $($elements.Count) elements: $selector"
        }

        # Limit to first 15 elements per selector type
        $maxElements = [Math]::Min($elements.Count, 15)

        for ($i = 0; $i -lt $maxElements; $i++) {
            $el = $elements[$i]
            $clickCount++

            # Get element info for logging
            $elId = Get-ElementAttribute -SessionId $SessionId -ElementId $el -Attribute "id"
            $elClass = Get-ElementAttribute -SessionId $SessionId -ElementId $el -Attribute "class"
            $elName = if ($elId) { $elId } else { $elClass.Split(' ')[0] }

            # Click the element
            $clicked = Click-Element -SessionId $SessionId -ElementId $el

            if ($clicked) {
                Start-Sleep -Milliseconds 300

                # Check for errors after click
                $clickErrors = Check-ForErrors -SessionId $SessionId -ScreenId $ScreenId

                if ($clickErrors.Count -gt 0) {
                    Write-Err "    ERROR after clicking $elName"
                    foreach ($err in $clickErrors) {
                        Write-Err "      - $err"
                        $fieldErrors += @{
                            Element = $elName
                            Selector = $selector
                            Index = $i
                            Error = $err
                        }
                    }

                    # Screenshot the error
                    $ssPath = Take-Screenshot -SessionId $SessionId -Filename "${ScreenId}_error_${clickCount}"
                    if ($ssPath) {
                        Write-Warn "      Screenshot: $ssPath"
                    }
                }

                # Press Escape to close any popups/dialogs
                Press-Escape -SessionId $SessionId
                Start-Sleep -Milliseconds 200
            }
        }
    }

    Write-Status "  Clicked $clickCount elements total"
    return $fieldErrors
}

# Tab through all fields
function Tab-ThroughFields {
    param([string]$SessionId, [string]$ScreenId)

    Write-Attack "Tabbing through all fields on $ScreenId..."

    $errors = @()
    $body = Find-Element -SessionId $SessionId -Using "css selector" -Value "body"

    if ($body) {
        # Tab through 30 fields
        for ($i = 0; $i -lt 30; $i++) {
            try {
                # Send Tab key
                Invoke-WebDriver -Method POST -Endpoint "/session/$SessionId/element/$body/value" -Body @{
                    text = "`u{E004}"  # Tab key
                } | Out-Null

                Start-Sleep -Milliseconds 200

                # Check for errors every 5 tabs
                if ($i % 5 -eq 0) {
                    $tabErrors = Check-ForErrors -SessionId $SessionId -ScreenId $ScreenId
                    if ($tabErrors.Count -gt 0) {
                        foreach ($err in $tabErrors) {
                            $errors += @{ TabIndex = $i; Error = $err }
                            Write-Err "    Tab $i error: $err"
                        }
                    }
                }
            } catch { }
        }
    }

    return $errors
}

$allErrors = @()

try {
    # Start WebDriver process
    Write-Status "Starting WebDriver on port $DriverPort..."
    $driverProcess = Start-Process -FilePath $webDriverPath -ArgumentList "--port=$DriverPort" -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2

    # Create session
    Write-Status "Creating browser session..."
    $sessionId = New-Session
    Write-Success "Session created: $($sessionId.Substring(0, 8))..."

    # Navigate to login
    $loginUrl = "$AcumaticaUrl/Frames/Login.aspx"
    Write-Status "Navigating to: $loginUrl"
    Set-Url -SessionId $sessionId -Url $loginUrl
    Start-Sleep -Seconds 3

    # Login
    Write-Status "Logging in as $Username..."

    $userElement = Find-Element -SessionId $sessionId -Using "css selector" -Value "#txtUser"
    if ($userElement) {
        Clear-Element -SessionId $sessionId -ElementId $userElement
        Send-Keys -SessionId $sessionId -ElementId $userElement -Text $Username
    } else {
        throw "Could not find username field"
    }

    $passElement = Find-Element -SessionId $sessionId -Using "css selector" -Value "#txtPass"
    if ($passElement) {
        Clear-Element -SessionId $sessionId -ElementId $passElement
        Send-Keys -SessionId $sessionId -ElementId $passElement -Text $Password
    } else {
        throw "Could not find password field"
    }

    $loginBtn = Find-Element -SessionId $sessionId -Using "css selector" -Value "#btnLogin"
    if ($loginBtn) {
        Click-Element -SessionId $sessionId -ElementId $loginBtn | Out-Null
    } else {
        throw "Could not find login button"
    }

    Write-Status "Waiting for login..."
    Start-Sleep -Seconds 5

    Write-Success "Logged in!"

    # Test each screen
    foreach ($screenID in $ScreenIDs) {
        Write-Host ""
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "  TESTING: $screenID" -ForegroundColor Cyan
        Write-Host "=============================================" -ForegroundColor Cyan

        $screenUrl = "$AcumaticaUrl/Main?ScreenId=$screenID"
        Set-Url -SessionId $sessionId -Url $screenUrl

        Start-Sleep -Seconds 4

        # Check page loaded
        $title = Get-Title -SessionId $sessionId
        Write-Status "Title: $title"

        # Initial error check
        $pageErrors = Check-ForErrors -SessionId $sessionId -ScreenId $screenID

        if ($pageErrors.Count -gt 0) {
            Write-Err "Page load errors:"
            foreach ($err in $pageErrors) {
                Write-Err "  - $err"
                $allErrors += @{ Screen = $screenID; Phase = "Load"; Error = $err }
            }

            # Screenshot the error
            Take-Screenshot -SessionId $sessionId -Filename "${screenID}_load_error" | Out-Null
        } else {
            Write-Success "Page loaded without errors"
        }

        # AGGRESSIVE mode - attack all fields
        if ($Aggressive) {
            # Attack fields by clicking
            $fieldErrors = Attack-AllFields -SessionId $sessionId -ScreenId $screenID
            if ($fieldErrors.Count -gt 0) {
                foreach ($fe in $fieldErrors) {
                    $allErrors += @{ Screen = $screenID; Phase = "FieldClick"; Element = $fe.Element; Error = $fe.Error }
                }
            }

            # Tab through fields
            $tabErrors = Tab-ThroughFields -SessionId $sessionId -ScreenId $screenID
            if ($tabErrors.Count -gt 0) {
                foreach ($te in $tabErrors) {
                    $allErrors += @{ Screen = $screenID; Phase = "TabThrough"; TabIndex = $te.TabIndex; Error = $te.Error }
                }
            }
        }

        # Final screenshot
        $ssPath = Take-Screenshot -SessionId $sessionId -Filename "${screenID}_final"
        Write-Status "Screenshot: $ssPath"

        Start-Sleep -Seconds 1
    }

    # SUMMARY
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor White
    Write-Host "  TEST SUMMARY" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor White

    if ($allErrors.Count -eq 0) {
        Write-Success "ALL SCREENS PASSED! No errors found."
        Write-Success "Screenshots saved to: $ScreenshotDir"
    } else {
        Write-Err "FOUND $($allErrors.Count) ERROR(S):"
        Write-Host ""

        $groupedErrors = $allErrors | Group-Object -Property Screen
        foreach ($group in $groupedErrors) {
            Write-Host "$($group.Name):" -ForegroundColor Yellow
            foreach ($err in $group.Group) {
                $detail = if ($err.Element) { " [$($err.Element)]" } else { "" }
                Write-Err "  [$($err.Phase)]$detail $($err.Error)"
            }
        }

        Write-Host ""
        Write-Warn "Screenshots saved to: $ScreenshotDir"
    }

    Write-Host ""
    Write-Host "Browser will stay open for inspection." -ForegroundColor Yellow
    Write-Host "Press Enter to close..." -ForegroundColor Yellow
    Read-Host

} catch {
    Write-Err "Fatal error: $_"
    Write-Host ""
    Write-Host "Press Enter to close browser..." -ForegroundColor Yellow
    Read-Host
} finally {
    if ($sessionId) {
        try {
            Remove-Session -SessionId $sessionId
        } catch { }
    }
    if ($driverProcess -and -not $driverProcess.HasExited) {
        Stop-Process -Id $driverProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

# Return error count for CI/CD usage
exit $allErrors.Count
