# direct-upload.ps1
# Direct SQL upload for Acumatica customization packages
# Bypasses SM204505 UI and uploads directly to database
#
# Database schema discovered:
#   CustProject -> CustObject -> UploadFile -> UploadFileRevision

param(
    [Parameter(Mandatory=$true)]
    [string]$PackagePath,

    [string]$Server = "localhost",
    [string]$Database = "AcumaticaDB",
    [string]$Username = "sa",
    [string]$Password = "Password1",

    [string]$OutputZip,   # Path for output zip (defaults to ProjectName.zip in current dir)
    [switch]$NoZip,       # Skip creating output zip
    [switch]$Force,       # Overwrite existing project
    [switch]$WhatIf,      # Preview without making changes
    [switch]$OpenBrowser, # Open SM204505 in browser after upload
    [switch]$AutoPublish, # Automatically click Publish using Selenium
    [switch]$RestartIIS,  # Run iisreset after publish
    [string]$AcumaticaUrl = "http://localhost/AcumaticaERP",  # Acumatica URL
    [string]$AcumaticaUser = "admin",  # Acumatica login
    [string]$AcumaticaPass = "admin"   # Acumatica password
)

$ErrorActionPreference = "Stop"

function Write-Status { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Acumatica Direct SQL Upload ===" -ForegroundColor Magenta

# Validate package exists
if (-not (Test-Path $PackagePath)) {
    Write-Err "Package not found: $PackagePath"
    exit 1
}

$PackagePath = Resolve-Path $PackagePath
$packageName = [System.IO.Path]::GetFileNameWithoutExtension($PackagePath)
Write-Status "Package: $packageName"
Write-Status "Target: $Server/$Database"

# Create temp extraction directory
$tempDir = Join-Path $env:TEMP ("acumatica-upload-" + [guid]::NewGuid().ToString().Substring(0,8))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Status "Extracting to: $tempDir"

try {
    # Extract package
    Expand-Archive -Path $PackagePath -DestinationPath $tempDir -Force

    # Find project.xml
    $projectXmlPath = Join-Path $tempDir "project.xml"
    if (-not (Test-Path $projectXmlPath)) {
        Write-Err "project.xml not found at package root!"
        exit 1
    }

    # Parse project.xml
    [xml]$projectXml = Get-Content $projectXmlPath -Raw
    $customization = $projectXml.Customization

    $projectName = $customization.description
    $projectLevel = [int]($customization.level)

    Write-Success "Found project: $projectName (level=$projectLevel)"

    # Get file list from project.xml
    # Files can be under <Files><File/></Files> or directly under <Customization><File/></Customization>
    $files = @()
    $fileNodes = if ($customization.Files.File) { $customization.Files.File } else { $customization.File }
    foreach ($fileNode in $fileNodes) {
        $relativePath = $fileNode.AppRelativePath
        $fullPath = Join-Path $tempDir $relativePath.Replace("\", [System.IO.Path]::DirectorySeparatorChar)

        if (Test-Path $fullPath) {
            $sizeBytes = (Get-Item $fullPath).Length
            $sizeKB = [math]::Round($sizeBytes / 1024, 1)
            $files += @{
                RelativePath = $relativePath
                FullPath = $fullPath
                FileID = [guid]::NewGuid()
                Size = $sizeBytes
                SizeKB = $sizeKB
            }
        } else {
            Write-Warn "File listed but not found: $relativePath"
        }
    }

    Write-Success "Found $($files.Count) files to upload"
    foreach ($f in $files) {
        Write-Status ("  " + $f.RelativePath + " (" + $f.SizeKB + " KB)")
    }

    if ($WhatIf) {
        Write-Host ""
        Write-Host "[WhatIf] Would upload to $Server/$Database" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would create/update project: $projectName" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would upload $($files.Count) files" -ForegroundColor Yellow
        exit 0
    }

    # Connect to SQL Server
    Write-Status "Connecting to SQL Server..."

    $connString = "Server=$Server;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    $conn.Open()
    Write-Success "Connected to database"

    try {
        # Start transaction
        $transaction = $conn.BeginTransaction()

        # Check if project exists
        $checkCmd = $conn.CreateCommand()
        $checkCmd.Transaction = $transaction
        $checkCmd.CommandText = "SELECT ProjID, IsWorking FROM CustProject WHERE Name = @Name"
        $checkCmd.Parameters.AddWithValue("@Name", $projectName) | Out-Null

        $reader = $checkCmd.ExecuteReader()
        $existingProjID = $null
        $isWorking = $false
        if ($reader.Read()) {
            $existingProjID = $reader.GetGuid(0)
            $isWorking = $reader.GetBoolean(1)
        }
        $reader.Close()

        if ($existingProjID -and -not $Force) {
            Write-Warn "Project '$projectName' already exists (ID: $existingProjID)"
            Write-Warn "Use -Force to overwrite"
            $transaction.Rollback()
            exit 1
        }

        # Generate or use existing project ID
        $projID = if ($existingProjID) { $existingProjID } else { [guid]::NewGuid() }
        $projRevisionID = [guid]::NewGuid()

        # Get admin user ID for CreatedByID (needed for all operations)
        $userCmd = $conn.CreateCommand()
        $userCmd.Transaction = $transaction
        $userCmd.CommandText = "SELECT TOP 1 CreatedByID FROM CustProject WHERE CreatedByID IS NOT NULL"
        $adminUserID = $userCmd.ExecuteScalar()
        if (-not $adminUserID) {
            # Fallback to first user in system
            $userCmd.CommandText = "SELECT TOP 1 pKID FROM Users WHERE Username = 'admin'"
            $adminUserID = $userCmd.ExecuteScalar()
        }
        if (-not $adminUserID) {
            $adminUserID = [guid]::NewGuid()  # Last resort fallback
        }

        if ($existingProjID) {
            Write-Status "Updating existing project: $projID"

            # Delete existing CustObjects for this project
            $deleteCmd = $conn.CreateCommand()
            $deleteCmd.Transaction = $transaction
            $deleteCmd.CommandText = "DELETE FROM CustObject WHERE ProjectID = @ProjID"
            $deleteCmd.Parameters.AddWithValue("@ProjID", $projID) | Out-Null
            $deleted = $deleteCmd.ExecuteNonQuery()
            Write-Status "Removed $deleted existing objects"

            # Update project
            $updateCmd = $conn.CreateCommand()
            $updateCmd.Transaction = $transaction
            $updateCmd.CommandText = "UPDATE CustProject SET Level = @Level, Description = @Description, LastModifiedDateTime = GETDATE() WHERE ProjID = @ProjID"
            $updateCmd.Parameters.AddWithValue("@ProjID", $projID) | Out-Null
            $updateCmd.Parameters.AddWithValue("@Level", $projectLevel) | Out-Null
            $updateCmd.Parameters.AddWithValue("@Description", $projectName) | Out-Null
            $updateCmd.ExecuteNonQuery() | Out-Null
        } else {
            Write-Status "Creating new project: $projID"

            # Insert new project
            $noteID = [guid]::NewGuid()
            $insertCmd = $conn.CreateCommand()
            $insertCmd.Transaction = $transaction
            $insertCmd.CommandText = "INSERT INTO CustProject (CompanyID, ProjID, Name, IsWorking, Description, Level, CreatedByID, CreatedDateTime, LastModifiedByID, LastModifiedDateTime, NoteID) VALUES (1, @ProjID, @Name, 0, @Description, @Level, @CreatedByID, GETDATE(), @CreatedByID, GETDATE(), @NoteID)"
            $insertCmd.Parameters.AddWithValue("@ProjID", $projID) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Name", $projectName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Description", $projectName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Level", $projectLevel) | Out-Null
            $insertCmd.Parameters.AddWithValue("@CreatedByID", $adminUserID) | Out-Null
            $insertCmd.Parameters.AddWithValue("@NoteID", $noteID) | Out-Null
            $insertCmd.ExecuteNonQuery() | Out-Null
        }

        # Upload each file
        $uploadedCount = 0
        foreach ($file in $files) {
            Write-Status "Uploading: $($file.RelativePath)"

            $fileID = $file.FileID
            $objectID = [guid]::NewGuid()
            $objectName = "File#$($file.RelativePath)"
            $uploadFileName = "CstFile-$projectName-$($file.RelativePath.Replace('\', '-'))"

            # Read file content
            $fileContent = [System.IO.File]::ReadAllBytes($file.FullPath)
            $fileSizeKB = [math]::Ceiling($fileContent.Length / 1024)

            # 1. Create UploadFile record
            $ufNoteID = [guid]::NewGuid()
            $companyMask = [byte[]]@(0xAA)  # Standard company mask
            $ufCmd = $conn.CreateCommand()
            $ufCmd.Transaction = $transaction
            $ufCmd.CommandText = "INSERT INTO UploadFile (CompanyID, FileID, Name, ShortName, CreatedByID, CreatedDateTime, Versioned, LastRevisionID, IsHidden, IsPublic, IsSystem, NoteID, CompanyMask, IsAccessRightsFromEntities) VALUES (1, @FileID, @Name, @ShortName, @CreatedByID, GETDATE(), 0, 1, 0, 0, 0, @NoteID, @CompanyMask, 1)"
            $ufCmd.Parameters.AddWithValue("@FileID", $fileID) | Out-Null
            $ufCmd.Parameters.AddWithValue("@Name", $uploadFileName) | Out-Null
            $ufCmd.Parameters.AddWithValue("@ShortName", $uploadFileName) | Out-Null
            $ufCmd.Parameters.AddWithValue("@CreatedByID", $adminUserID) | Out-Null
            $ufCmd.Parameters.AddWithValue("@NoteID", $ufNoteID) | Out-Null
            $ufCmd.Parameters.Add("@CompanyMask", [System.Data.SqlDbType]::VarBinary, 32).Value = $companyMask
            $ufCmd.ExecuteNonQuery() | Out-Null

            # 2. Create UploadFileRevision with binary data
            $ufrCmd = $conn.CreateCommand()
            $ufrCmd.Transaction = $transaction
            $ufrCmd.CommandText = "INSERT INTO UploadFileRevision (CompanyID, FileID, FileRevisionID, Data, Size, CreatedByID, CreatedDateTime, OriginalName, CompanyMask) VALUES (1, @FileID, 1, @Data, @Size, @CreatedByID, GETDATE(), @OriginalName, @CompanyMask)"
            $ufrCmd.Parameters.AddWithValue("@FileID", $fileID) | Out-Null
            $ufrCmd.Parameters.Add("@Data", [System.Data.SqlDbType]::VarBinary, -1).Value = $fileContent
            $ufrCmd.Parameters.AddWithValue("@Size", $fileSizeKB) | Out-Null
            $ufrCmd.Parameters.AddWithValue("@CreatedByID", $adminUserID) | Out-Null
            $ufrCmd.Parameters.AddWithValue("@OriginalName", [System.IO.Path]::GetFileName($file.FullPath)) | Out-Null
            $ufrCmd.Parameters.Add("@CompanyMask", [System.Data.SqlDbType]::VarBinary, 32).Value = $companyMask
            $ufrCmd.ExecuteNonQuery() | Out-Null

            # 3. Create CustObject reference
            $contentXml = "<File AppRelativePath=`"$($file.RelativePath)`" FileID=`"$fileID`" />"
            $coNoteID = [guid]::NewGuid()

            $coCmd = $conn.CreateCommand()
            $coCmd.Transaction = $transaction
            $coCmd.CommandText = "INSERT INTO CustObject (CompanyID, ObjectID, Name, Type, ProjectID, ProjectRevisionID, Content, IsDisabled, CreatedDateTime, LastModifiedDateTime, NoteID, CreatedByID, LastModifiedByID) VALUES (1, @ObjectID, @Name, 'File', @ProjectID, @ProjectRevisionID, @Content, 0, GETDATE(), GETDATE(), @NoteID, @CreatedByID, @CreatedByID)"
            $coCmd.Parameters.AddWithValue("@ObjectID", $objectID) | Out-Null
            $coCmd.Parameters.AddWithValue("@Name", $objectName) | Out-Null
            $coCmd.Parameters.AddWithValue("@ProjectID", $projID) | Out-Null
            $coCmd.Parameters.AddWithValue("@ProjectRevisionID", $projRevisionID) | Out-Null
            $coCmd.Parameters.AddWithValue("@Content", $contentXml) | Out-Null
            $coCmd.Parameters.AddWithValue("@NoteID", $coNoteID) | Out-Null
            $coCmd.Parameters.AddWithValue("@CreatedByID", $adminUserID) | Out-Null
            $coCmd.ExecuteNonQuery() | Out-Null

            $uploadedCount++
        }

        # Commit transaction
        $transaction.Commit()
        Write-Host ""
        Write-Success "Upload complete!"
        Write-Success "Project ID: $projID"
        Write-Success "Files uploaded: $uploadedCount"

        # Save zip copy (always, unless -NoZip specified)
        if (-not $NoZip) {
            if ($OutputZip) {
                $zipOutputPath = if ([System.IO.Path]::IsPathRooted($OutputZip)) { $OutputZip } else { Join-Path (Get-Location) $OutputZip }
            } else {
                # Auto-generate: ProjectName.zip in current directory
                $safeName = $projectName -replace '[^\w\-]', ''
                $zipOutputPath = Join-Path (Get-Location) "$safeName.zip"
            }
            Copy-Item -Path $PackagePath -Destination $zipOutputPath -Force
            Write-Success "Zip saved to: $zipOutputPath"
        }

        # Auto-publish using Selenium
        if ($AutoPublish) {
            Write-Host ""
            Write-Host "=== Auto-Publishing ===" -ForegroundColor Magenta
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            $autoPublishScript = Join-Path $scriptDir "auto-publish.ps1"

            if (Test-Path $autoPublishScript) {
                & $autoPublishScript -ProjectName $projectName -AcumaticaUrl $AcumaticaUrl -Username $AcumaticaUser -Password $AcumaticaPass -RestartIIS:$RestartIIS
            } else {
                Write-Warn "auto-publish.ps1 not found. Opening browser instead..."
                Start-Process "$AcumaticaUrl/Main?ScreenId=SM204505"
            }
        }
        # Open browser if requested
        elseif ($OpenBrowser) {
            Write-Host ""
            Write-Host "=== Opening Browser ===" -ForegroundColor Magenta
            $screenUrl = "$AcumaticaUrl/Main?ScreenId=SM204505"
            Write-Status "Opening: $screenUrl"
            Start-Process $screenUrl
            Write-Success "Browser opened! Select '$projectName' and click Publish."
        } else {
            Write-Host ""
            Write-Host "=== Next Steps ===" -ForegroundColor Magenta
            Write-Host "1. Open SM204505 (Customization Projects)" -ForegroundColor White
            Write-Host "2. Find project: $projectName" -ForegroundColor White
            Write-Host "3. Click 'Publish'" -ForegroundColor White
            Write-Host "4. If screens don't appear, run: iisreset" -ForegroundColor White
            Write-Host ""
            Write-Host "Or run with -OpenBrowser to open SM204505 automatically" -ForegroundColor Gray
        }

        # Restart IIS if requested
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
        Write-Err "Database error: $_"
        if ($transaction) { $transaction.Rollback() }
        throw
    } finally {
        $conn.Close()
    }

} finally {
    # Cleanup temp directory
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
