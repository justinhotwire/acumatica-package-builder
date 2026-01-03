# build-customization-template.ps1
# Template script for building Acumatica customization packages correctly from source
#
# This script:
# 1. Builds the C# project DLL
# 2. Validates ASPX files (removes CodeFile, Inherits, HTML comments)
# 3. Copies files to temp directory
# 4. Creates zip with proper structure (project.xml at root)
# 5. Validates the final package
#
# Usage: .\build-customization-template.ps1 -PackageName "AcuSales" -DllName "AcuSales.Core.dll"

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectPath = ".",

    [Parameter(Mandatory=$true)]
    [string]$PackageName,

    [Parameter(Mandatory=$true)]
    [string]$DllName,

    [Parameter(Mandatory=$false)]
    [string]$Level = "0"
)

$ErrorActionPreference = "Stop"
$temp = 'temp-package-build'

Write-Host ""
Write-Host "=== Acumatica Customization Package Builder ===" -ForegroundColor Cyan
Write-Host "Package: $PackageName" -ForegroundColor White
Write-Host "Level: $Level" -ForegroundColor White
Write-Host ""

# Step 1: Build DLL if C# project exists
$csprojFiles = Get-ChildItem -Path $ProjectPath -Filter "*.csproj" -Recurse
if ($csprojFiles.Count -gt 0) {
    Write-Host "[1/6] Building DLL..." -ForegroundColor Yellow
    $csproj = $csprojFiles[0].FullName
    dotnet build $csproj --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "DLL build failed"
    }
    Write-Host "  ✓ DLL built successfully" -ForegroundColor Green
} else {
    Write-Host "[1/6] Skipping DLL build (no .csproj found)" -ForegroundColor Gray
}

# Step 2: Validate and fix ASPX files
Write-Host "[2/6] Validating ASPX files..." -ForegroundColor Yellow
$aspxPath = Join-Path $ProjectPath "Pages"
if (Test-Path $aspxPath) {
    $aspxFiles = Get-ChildItem -Path $aspxPath -Filter "*.aspx"
    $fixedCount = 0

    foreach ($file in $aspxFiles) {
        $content = Get-Content -Path $file.FullName -Raw
        $originalContent = $content

        # Remove CodeFile attribute
        $content = $content -replace 'CodeFile="[^"]+"\s*', ''

        # Remove Inherits attribute
        $content = $content -replace 'Inherits="[^"]+"\s*', ''

        # Remove ParentField attribute (invalid property)
        $content = $content -replace 'ParentField="[^"]+"\s*', ''

        # Remove HTML comment-only lines
        $lines = $content -split "`r`n"
        $newLines = @()
        foreach ($line in $lines) {
            if ($line -notmatch '^\s*<!--.*-->\s*$') {
                $newLines += $line
            }
        }
        $content = $newLines -join "`r`n"

        # Update file if changes were made
        if ($content -ne $originalContent) {
            Set-Content -Path $file.FullName -Value $content -NoNewline
            $fixedCount++
        }
    }

    Write-Host "  ✓ Validated $($aspxFiles.Count) ASPX files ($fixedCount fixed)" -ForegroundColor Green
} else {
    Write-Host "  ! No Pages directory found" -ForegroundColor Yellow
}

# Step 3: Clean and create temp directory
Write-Host "[3/6] Preparing package structure..." -ForegroundColor Yellow
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $temp -Force | Out-Null

# Copy project.xml to ROOT
$projectXmlSource = Join-Path $ProjectPath "package\project.xml"
if (-not (Test-Path $projectXmlSource)) {
    $projectXmlSource = Join-Path $ProjectPath "project.xml"
}
if (Test-Path $projectXmlSource) {
    Copy-Item $projectXmlSource "$temp\project.xml"
    Write-Host "  ✓ Copied project.xml to root" -ForegroundColor Green
} else {
    Write-Error "project.xml not found at $projectXmlSource"
}

# Copy DLL to Bin folder
$dllSource = Get-ChildItem -Path $ProjectPath -Filter $DllName -Recurse |
    Where-Object { $_.DirectoryName -like "*\bin\Release*" } |
    Select-Object -First 1

if ($dllSource) {
    New-Item -ItemType Directory -Path "$temp\Bin" -Force | Out-Null
    Copy-Item $dllSource.FullName "$temp\Bin\$DllName"
    Write-Host "  ✓ Copied $DllName to Bin\" -ForegroundColor Green
} else {
    Write-Error "DLL not found: $DllName in Release build"
}

# Copy Pages folder
$pagesSource = Join-Path $ProjectPath "Pages"
if (-not (Test-Path $pagesSource)) {
    $pagesSource = Join-Path $ProjectPath "package\Pages"
}
if (Test-Path $pagesSource) {
    Copy-Item $pagesSource "$temp\Pages" -Recurse
    $pageCount = (Get-ChildItem "$temp\Pages" -Filter "*.aspx").Count
    Write-Host "  ✓ Copied $pageCount ASPX pages" -ForegroundColor Green
} else {
    Write-Host "  ! No Pages folder found" -ForegroundColor Yellow
}

# Copy Scripts folder
$scriptsSource = Join-Path $ProjectPath "Scripts"
if (-not (Test-Path $scriptsSource)) {
    $scriptsSource = Join-Path $ProjectPath "package\Scripts"
}
if (Test-Path $scriptsSource) {
    Copy-Item $scriptsSource "$temp\Scripts" -Recurse
    Write-Host "  ✓ Copied Scripts folder" -ForegroundColor Green
} else {
    Write-Host "  ! No Scripts folder found" -ForegroundColor Yellow
}

# Step 4: Create zip file
Write-Host "[4/6] Creating zip package..." -ForegroundColor Yellow
$zipPath = "$PackageName-Complete.zip"
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

Push-Location $temp
Compress-Archive -Path * -DestinationPath "..\$zipPath" -Force
Pop-Location

if (Test-Path $zipPath) {
    $zipSize = (Get-Item $zipPath).Length
    Write-Host "  ✓ Created $zipPath ($zipSize bytes)" -ForegroundColor Green
} else {
    Write-Error "Failed to create zip file"
}

# Step 5: Validate package structure
Write-Host "[5/6] Validating package structure..." -ForegroundColor Yellow
$verifyTemp = 'temp-verify'
Remove-Item $verifyTemp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zipPath -DestinationPath $verifyTemp -Force

$validationErrors = @()

# Check project.xml at root
if (-not (Test-Path "$verifyTemp\project.xml")) {
    $validationErrors += "project.xml not at root level"
}

# Check for old _project subdirectory
if (Test-Path "$verifyTemp\_project") {
    $validationErrors += "Found _project subdirectory (should not exist)"
}

# Check level attribute in project.xml
if (Test-Path "$verifyTemp\project.xml") {
    $xmlContent = Get-Content "$verifyTemp\project.xml" -Raw
    if ($xmlContent -match 'level=""') {
        $validationErrors += "Empty level attribute in project.xml"
    }
    if ($xmlContent -notmatch 'level="[01]"') {
        $validationErrors += "Missing or invalid level attribute"
    }
}

# Check for CodeFile/Inherits in ASPX
if (Test-Path "$verifyTemp\Pages") {
    $aspxIssues = Get-ChildItem "$verifyTemp\Pages\*.aspx" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match 'CodeFile=') { "$($_.Name): has CodeFile" }
        if ($content -match 'Inherits="Page_') { "$($_.Name): has Inherits" }
    }
    if ($aspxIssues) {
        $validationErrors += $aspxIssues
    }
}

Remove-Item $verifyTemp -Recurse -Force

if ($validationErrors.Count -eq 0) {
    Write-Host "  ✓ Package structure valid" -ForegroundColor Green
} else {
    Write-Host "  ✗ Validation errors found:" -ForegroundColor Red
    foreach ($error in $validationErrors) {
        Write-Host "    - $error" -ForegroundColor Red
    }
    throw "Package validation failed"
}

# Step 6: Cleanup
Write-Host "[6/6] Cleaning up..." -ForegroundColor Yellow
Remove-Item $temp -Recurse -Force
Write-Host "  ✓ Cleanup complete" -ForegroundColor Green

# Success summary
Write-Host ""
Write-Host "=== BUILD SUCCESSFUL ===" -ForegroundColor Green
Write-Host ""
Write-Host "Package: $(Resolve-Path $zipPath)" -ForegroundColor Cyan
Write-Host "Size: $zipSize bytes" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Open Acumatica → SM204505 (Customization Projects)" -ForegroundColor White
Write-Host "2. Click 'Import' and select $zipPath" -ForegroundColor White
Write-Host "3. Click 'Publish' (should complete without errors)" -ForegroundColor White
Write-Host "4. Run: iisreset /noforce" -ForegroundColor White
Write-Host "5. Clear browser cache and test screens" -ForegroundColor White
Write-Host ""
