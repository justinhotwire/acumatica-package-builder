# Acumatica Package Builder Skill

You are an expert at building Acumatica ERP customization packages from source code. Your job is to create deployment-ready zip packages that import and publish correctly the first time, with no errors.

## When to Use This Skill

Invoke this skill when:
- Building a customization package for deployment
- Preparing code for import into SM204505 (Customization Projects screen)
- Creating a zip from DLLs, ASPX files, and SQL scripts
- Packaging custom screens and graphs for Acumatica

## Package Building Workflow

### 1. Discover Source Structure

First, understand what's being packaged:

**Scan for custom assemblies:**
- Look for compiled DLLs in `bin/`, `bin/Release/`, `bin/Debug/`
- Identify namespace patterns (e.g., `AcuSales`, `MyCompany.Acumatica`)

**Scan for ASPX pages:**
- Find custom screens in `Pages/`, `CRMScripts/`, etc.
- Screen IDs typically follow pattern: `XX######.aspx` (e.g., AS201000.aspx)
- Extract TypeName to identify the PXGraph class

**Scan for SQL scripts:**
- Database initialization scripts
- Permission grant scripts
- Look in `Scripts/`, `SQL/`, `Database/`

**Scan for assets:**
- JavaScript bundles
- CSS files
- Images, fonts, etc.

**Scan for Graph classes:**
- Parse C# files to find PXGraph classes
- Extract namespace and class name (e.g., `AcuSales.Graph.Maintenance.TerritoryMaint`)
- Identify primary views (PXFilter, PXSelect, PXSelectJoin)
- Match graphs to ASPX screens

### 2. Validate ASPX Files

Before packaging, ensure ASPX files are clean:

**Check Page directives:**
```aspx
<%@ Page Language="C#" MasterPageFile="~/MasterPages/FormDetail.master"
    AutoEventWireup="true" ValidateRequest="false" Title="Screen Title"
    Inherits="PX.Web.UI.PXPage" %>
```
- ✅ MUST have: `Language="C#"`, `AutoEventWireup="true"`, `MasterPageFile="~/MasterPages/*.master"`
- ✅ **MUST have: `Inherits="PX.Web.UI.PXPage"`** - This is the base class, NOT optional!
- ❌ MUST NOT have: `CodeFile="*.aspx.cs"` - Remove it!
- ❌ MUST NOT have: `Inherits="Page_AS201000"` (class name) - Use base class instead!
- ✅ The difference:
  - `Inherits="Page_AS201000"` = code-behind class (WRONG - doesn't exist)
  - `Inherits="PX.Web.UI.PXPage"` = base class inheritance (CORRECT)
- ✅ Reason: Acumatica uses PXGraph pattern, not code-behind. The graph is in TypeName, not Inherits.

**Check PXDataSource:**
```aspx
<px:PXDataSource ID="ds" runat="server"
    TypeName="YourNamespace.Graph.YourGraphMaint, YourAssembly"
    PrimaryView="ViewName">
```
- ✅ **TypeName MUST be assembly-qualified**: `Namespace.Class, AssemblyName`
  - Example: `TypeName="AcuSales.Graph.Maintenance.TerritoryMaint, AcuSales.Core"`
  - NOT: `TypeName="AcuSales.Graph.Maintenance.TerritoryMaint"` (missing assembly!)
- ✅ PrimaryView MUST exactly match a public view in the Graph class
- Example: If graph has `public PXFilter<MyFilter> Filter;` → use `PrimaryView="Filter"`
- ❌ Common mistake: ASPX says `PrimaryView="Filter"` but graph has `Stats` → screens redirect to 00000000!

**Remove HTML comments from control collections:**
```aspx
<!-- DO NOT DO THIS -->
<Items>
    <px:PXTabItem Text="General">...</px:PXTabItem>
    <!-- This comment will break ASPX validation -->
    <px:PXTabItem Text="Details">...</px:PXTabItem>
</Items>
```
- ❌ HTML comments between control items cause ASPPARSE errors
- ✅ Comments inside `<Template>` tags are fine
- Fix: Remove ALL comment-only lines with: `(Get-Content $file) | Where-Object { $_ -notmatch '^\s*<!--.*-->\s*$' } | Set-Content $file`

**Remove invalid properties:**
- ❌ `ParentField` on `PXTreeItemBinding` - doesn't exist in Acumatica API
- ❌ Any property not in official Acumatica control documentation
- Verify against Acumatica source or working examples

### 3. Generate project.xml

Create `project.xml` at the ROOT of the zip (not in a subdirectory!) with this structure:

**Critical attributes:**
```xml
<Customization
    level="0"                    <!-- "0" = new package, "1" = update existing -->
    description="Package Name"   <!-- Shows in SM204505 -->
    product-version="24.200.0010" <!-- Match target Acumatica version -->
>
```
- ❌ NEVER use `level=""` - causes "Object reference not set" errors
- ✅ Use `level="0"` for first deployment, `level="1"` for updates

**Files section:**
```xml
<!-- List ALL files with AppRelativePath using BACKSLASHES -->
<File AppRelativePath="Bin\YourCustom.dll" />
<File AppRelativePath="Frames\XX101000.aspx" />
<File AppRelativePath="Scripts\InitDatabase.sql" />
<File AppRelativePath="Scripts\assets\bundle.js" />
```
- ✅ Use backslashes: `Bin\file.dll` (Windows style)
- ❌ NOT forward slashes: `Bin/file.dll`
- ✅ List EVERY file that will be in the zip
- ⚠️ **CRITICAL: Folder name MUST match URL path!**
  - If URL is `~/Frames/XX101000.aspx` → use `Frames\` folder
  - If URL is `~/Pages/XX101000.aspx` → use `Pages\` folder
  - Mismatch = "file does not exist" errors!

**ScreenWithRights section (for each custom screen):**
```xml
<ScreenWithRights AccessRightsMergeRule="CopyFromTenant">
    <data-set>
        <relations format-version="4" relations-version="20250701" main-table="SiteMap">
            <link from="RolesInCache (ScreenID)" to="SiteMap (ScreenID)" />
            <link from="RolesInGraph (ScreenID)" to="SiteMap (ScreenID)" />
            <link from="RolesInMember (ScreenID)" to="SiteMap (ScreenID)" />
            <link from="Roles (Rolename, ApplicationName)" to="RolesInCache (Rolename, ApplicationName)" type="FromMaster" updateable="False" />
            <link from="Roles (Rolename, ApplicationName)" to="RolesInGraph (Rolename, ApplicationName)" type="FromMaster" updateable="False" />
            <link from="Roles (Rolename, ApplicationName)" to="RolesInMember (Rolename, ApplicationName)" type="FromMaster" updateable="False" />
        </relations>
        <layout>
            <table name="SiteMap">
                <table name="RolesInCache" uplink="(ScreenID) = (ScreenID)" />
                <table name="RolesInGraph" uplink="(ScreenID) = (ScreenID)" />
                <table name="RolesInMember" uplink="(ScreenID) = (ScreenID)" />
            </table>
            <table name="Roles" />
        </layout>
        <data>
            <SiteMap>
                <row Title="Your Screen Title"
                     Url="~/Frames/XX101000.aspx"
                     ScreenID="XX101000"
                     NodeID="unique-guid-here"
                     ParentID="00000000-0000-0000-0000-000000000000"
                     SelectedUI="D"
                     GraphType="Your.Namespace.Graph.YourGraphMaint">
                    <RolesInGraph Rolename="*" ApplicationName="/" Accessrights="0" />
                    <RolesInGraph Rolename="Administrator" ApplicationName="/" Accessrights="4" />
                </row>
            </SiteMap>
            <Roles>
                <row Rolename="Administrator" ApplicationName="/" Descr="System Administrator" Guest="0" />
            </Roles>
        </data>
    </data-set>
</ScreenWithRights>
```
- ✅ **GraphType is CRITICAL** - must be full namespace to your PXGraph class
- ✅ NodeID must be unique GUID per screen (use `[guid]::NewGuid()` in PowerShell)
- ✅ Accessrights: "4" = full access, "0" = view only
- ✅ Always include Administrator and * (all users) roles

**SiteMapNode section (for Modern UI):**
```xml
<SiteMapNode>
    <data-set>
        <relations format-version="4" relations-version="20250701" main-table="SiteMap">
            <link from="MUIScreen (NodeID)" to="SiteMap (NodeID)" />
            <link from="MUIWorkspace (WorkspaceID)" to="MUIScreen (WorkspaceID)" type="FromMaster" linkname="workspaceToScreen" split-location="yes" updateable="True" />
            <link from="MUISubcategory (SubcategoryID)" to="MUIScreen (SubcategoryID)" type="FromMaster" updateable="True" />
            <link from="MUITile (ScreenID)" to="SiteMap (ScreenID)" />
            <link from="MUIWorkspace (WorkspaceID)" to="MUITile (WorkspaceID)" type="FromMaster" linkname="workspaceToTile" split-location="yes" updateable="True" />
            <link from="MUIArea (AreaID)" to="MUIWorkspace (AreaID)" type="FromMaster" updateable="True" />
            <link from="MUIPinnedScreen (NodeID, WorkspaceID)" to="MUIScreen (NodeID, WorkspaceID)" type="WeakIfEmpty" isEmpty="Username" />
            <link from="MUIFavoriteWorkspace (WorkspaceID)" to="MUIWorkspace (WorkspaceID)" type="WeakIfEmpty" isEmpty="Username" />
        </relations>
        <layout>
            <table name="SiteMap">
                <table name="MUIScreen" uplink="(NodeID) = (NodeID)">
                    <table name="MUIPinnedScreen" uplink="(NodeID, WorkspaceID) = (NodeID, WorkspaceID)" />
                </table>
                <table name="MUITile" uplink="(ScreenID) = (ScreenID)" />
            </table>
            <table name="MUIWorkspace">
                <table name="MUIFavoriteWorkspace" uplink="(WorkspaceID) = (WorkspaceID)" />
            </table>
            <table name="MUISubcategory" />
            <table name="MUIArea" />
        </layout>
        <data>
            <SiteMap>
                <row Title="Your Screen Title"
                     Url="~/Frames/XX101000.aspx"
                     ScreenID="XX101000"
                     NodeID="same-guid-as-above"
                     ParentID="00000000-0000-0000-0000-000000000000"
                     SelectedUI="D" />
            </SiteMap>
        </data>
    </data-set>
</SiteMapNode>
```
- ✅ Use SAME NodeID as in ScreenWithRights section
- ✅ Required for Modern UI visibility

### 4. Build Package Structure

Create the zip with this exact structure:

```
YourCustomization.zip
├── project.xml              ← ROOT LEVEL! Not in _project/!
├── Bin/
│   └── YourCustom.dll
├── Frames/                  ← Use Frames\ for ~/Frames/ URLs!
│   ├── XX101000.aspx
│   └── XX102000.aspx
└── Scripts/
    ├── InitDatabase.sql
    └── assets/
        ├── bundle.js
        └── styles.css
```

⚠️ **The folder name MUST match the URL path in SiteMap!**
- Standard Acumatica screens use `~/Frames/`
- If your Url is `~/Frames/XX101000.aspx`, files go in `Frames\`
- If your Url is `~/Pages/XX101000.aspx`, files go in `Pages\`

**PowerShell build script:**
```powershell
$temp = 'temp-package-build'
$packageName = 'YourCustomization'

# Clean temp
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $temp -Force | Out-Null

# Copy project.xml to ROOT
Copy-Item 'project.xml' "$temp\project.xml"

# Copy DLL
New-Item -ItemType Directory -Path "$temp\Bin" -Force | Out-Null
Copy-Item 'YourProject\bin\Release\YourCustom.dll' "$temp\Bin\"

# Copy ASPX pages (use Frames to match ~/Frames/ URLs!)
Copy-Item 'Frames' "$temp\Frames" -Recurse

# Copy Scripts
Copy-Item 'Scripts' "$temp\Scripts" -Recurse

# Create zip
Push-Location $temp
Compress-Archive -Path * -DestinationPath "..\$packageName.zip" -Force
Pop-Location

# Cleanup
Remove-Item $temp -Recurse -Force

Write-Host "Package created: $packageName.zip" -ForegroundColor Green
```

### 5. Pre-Import Validation

Before delivering the package, verify:

**Structure check:**
```powershell
Expand-Archive -Path 'YourCustomization.zip' -DestinationPath 'verify-temp' -Force
$hasProjectXml = Test-Path 'verify-temp\project.xml'
$hasBin = Test-Path 'verify-temp\Bin'
$hasPages = Test-Path 'verify-temp\Pages'

if (-not $hasProjectXml) {
    Write-Error "project.xml not at root!"
}
```

**XML validation:**
- `level` attribute is "0" or "1" (not empty)
- All `<File>` entries have matching files in zip
- All screens have both ScreenWithRights and SiteMapNode entries
- All GraphType attributes are valid namespaces

**ASPX validation:**
```powershell
$aspxFiles = Get-ChildItem 'verify-temp\Frames\*.aspx'
foreach ($file in $aspxFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'CodeFile=') {
        Write-Error "Found CodeFile in $($file.Name) - REMOVE IT"
    }
    if ($content -match 'Inherits="Page_') {
        Write-Error "Found wrong Inherits in $($file.Name) - use 'PX.Web.UI.PXPage'"
    }
    if ($content -notmatch 'Inherits="PX\.Web\.UI\.PXPage"') {
        Write-Error "Missing Inherits='PX.Web.UI.PXPage' in $($file.Name)"
    }
    # Check for assembly-qualified TypeName
    if ($content -match 'TypeName="([^"]+)"' -and $Matches[1] -notmatch ',') {
        Write-Error "TypeName missing assembly name in $($file.Name) - use 'Namespace.Class, AssemblyName'"
    }
}
```

### 6. Deployment Instructions

Provide clear steps for the user:

```
## Import Instructions

1. Open Acumatica in browser
2. Navigate to SM204505 (Customization Projects)
3. Click "Import"
4. Select YourCustomization.zip
5. Click "Upload" and wait for validation
6. Click "Publish"
7. Monitor for errors (should show "Published successfully")
8. Restart IIS app pool: iisreset /noforce
9. Clear browser cache (Ctrl+Shift+Delete)
10. Test custom screens: XX101000, XX102000, etc.

## Troubleshooting

If screens redirect to ScreenId=00000000:
- Verify GraphType matches C# namespace exactly
- Verify PrimaryView matches view name in graph
- Check trace logs for null reference errors

If ASPPARSE errors during publish:
- Check for CodeFile/Inherits in ASPX files
- Check for HTML comments between controls
- Check for invalid control properties
```

## Critical Success Factors

### ❌ Common Mistakes That Break Packages

1. **Wrong XML location**: `_project/Customization.xml` instead of `project.xml` at root
2. **Empty level**: `level=""` instead of `level="0"` or `level="1"`
3. **Missing GraphType**: Screens won't register without it
4. **PrimaryView mismatch**: ASPX says "Filter" but graph has "Stats"
5. **Missing Inherits**: MUST have `Inherits="PX.Web.UI.PXPage"` - causes "page should be inherited from PXPage" error
6. **Wrong Inherits**: `Inherits="Page_AS201000"` (class) instead of `Inherits="PX.Web.UI.PXPage"` (base)
7. **CodeFile attribute**: `CodeFile="AS201000.aspx.cs"` - causes "file does not exist" errors
8. **Missing assembly in TypeName**: `TypeName="Namespace.Class"` instead of `TypeName="Namespace.Class, AssemblyName"`
9. **Folder/URL mismatch**: Files in `Pages\` but URL uses `~/Frames/` - causes "file does not exist"
10. **HTML comments in collections**: Breaks ASPX validation
11. **Wrong path slashes**: `Bin/file.dll` instead of `Bin\file.dll`
12. **Invalid properties**: Like `ParentField` on PXTreeItemBinding
13. **Stale cached files**: Old ASPX still deployed in Acumatica - need to manually delete from `C:\Program Files\Acumatica ERP\AcumaticaERP\Frames\`

### ✅ Success Checklist

Before delivering package, verify:

- [ ] project.xml at zip root (not in subdirectory)
- [ ] level="0" or level="1" (not empty)
- [ ] All File AppRelativePath use backslashes
- [ ] **Folder name matches URL path** (Frames\ for ~/Frames/)
- [ ] All screens have ScreenWithRights entries
- [ ] All screens have SiteMapNode entries
- [ ] All GraphType attributes match C# namespaces exactly
- [ ] All PrimaryView attributes match graph view names exactly
- [ ] No CodeFile attributes in ASPX Page directives
- [ ] **All ASPX have `Inherits="PX.Web.UI.PXPage"`** (base class, NOT class name!)
- [ ] **All TypeName are assembly-qualified** (`Namespace.Class, AssemblyName`)
- [ ] No HTML comments between control collection items
- [ ] No invalid control properties
- [ ] Unique NodeID (GUID) for each screen
- [ ] Both Administrator and * roles included

## Build Script Template

Use this template for repeatable builds:

```powershell
# build-customization.ps1
param(
    [string]$ProjectPath = ".",
    [string]$PackageName = "CustomizationPackage",
    [string]$DllName = "Custom.dll",
    [string]$Level = "0"
)

$ErrorActionPreference = "Stop"
$temp = 'temp-package-build'

Write-Host "Building $PackageName customization package..." -ForegroundColor Cyan

# Build DLL if C# project exists
if (Test-Path "$ProjectPath\*.csproj") {
    Write-Host "Building DLL..." -ForegroundColor Yellow
    dotnet build "$ProjectPath" --configuration Release
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
}

# Clean temp
Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $temp -Force | Out-Null

# Generate project.xml (you would generate this dynamically)
Copy-Item "$ProjectPath\package\project.xml" "$temp\project.xml"

# Copy DLL
if (Test-Path "$ProjectPath\bin\Release\$DllName") {
    New-Item -ItemType Directory -Path "$temp\Bin" -Force | Out-Null
    Copy-Item "$ProjectPath\bin\Release\$DllName" "$temp\Bin\"
}

# Copy ASPX pages (Frames folder for ~/Frames/ URLs)
if (Test-Path "$ProjectPath\Frames") {
    Copy-Item "$ProjectPath\Frames" "$temp\Frames" -Recurse
}

# Copy Scripts
if (Test-Path "$ProjectPath\Scripts") {
    Copy-Item "$ProjectPath\Scripts" "$temp\Scripts" -Recurse
}

# Validate ASPX files
if (Test-Path "$temp\Frames") {
    $issues = @()
    Get-ChildItem "$temp\Frames\*.aspx" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match 'CodeFile=') { $issues += "$($_.Name): has CodeFile attribute - REMOVE" }
        if ($content -match 'Inherits="Page_') { $issues += "$($_.Name): wrong Inherits class - use 'PX.Web.UI.PXPage'" }
        if ($content -notmatch 'Inherits="PX\.Web\.UI\.PXPage"') { $issues += "$($_.Name): missing Inherits='PX.Web.UI.PXPage'" }
        if ($content -match 'TypeName="([^"]+)"') {
            if ($Matches[1] -notmatch ',') { $issues += "$($_.Name): TypeName missing assembly - use 'Namespace.Class, AssemblyName'" }
        }
    }
    if ($issues) {
        Write-Error "ASPX validation failed:`n$($issues -join "`n")"
    }
}

# Create zip
Write-Host "Creating package..." -ForegroundColor Yellow
Push-Location $temp
Compress-Archive -Path * -DestinationPath "..\$PackageName.zip" -Force
Pop-Location

# Cleanup
Remove-Item $temp -Recurse -Force

# Verify
if (Test-Path "$PackageName.zip") {
    $size = (Get-Item "$PackageName.zip").Length
    Write-Host "`nSUCCESS: $PackageName.zip created" -ForegroundColor Green
    Write-Host "Size: $size bytes" -ForegroundColor Cyan
    Write-Host "Ready for SM204505 import" -ForegroundColor Green
} else {
    Write-Error "Failed to create package"
}
```

## When Invoked

1. **Scan the project** to identify DLLs, ASPX files, SQL scripts, graphs
2. **Validate ASPX files** and fix CodeFile/Inherits/comments if needed
3. **Generate project.xml** with proper ScreenWithRights and SiteMapNode entries
4. **Build the zip** with correct structure (project.xml at root)
5. **Validate the package** before delivery
6. **Provide import instructions** to the user

Remember: Build it right the first time. No "Object reference not set" errors, no ASPPARSE errors, no screen redirects to 00000000.

## Debugging When Things Go Wrong

When package import or publish fails, check these locations:

### Acumatica Logs
```
C:\Program Files\Acumatica ERP\AcumaticaERP\App_Data\Logs\
```
- Look for recent .log files
- Search for ERROR, Exception, or your screen ID

### Windows Event Viewer
```powershell
# Check Application log for ASP.NET errors
Get-WinEvent -LogName Application -MaxEvents 50 | Where-Object { $_.Message -like "*Acumatica*" -or $_.Message -like "*ASP.NET*" }
```

### SQL Server Logs
```sql
-- Check for recent errors
SELECT TOP 50 * FROM sys.dm_exec_requests WHERE status = 'suspended'
-- Check custom table existence
SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE 'AS%'
```

### Request Trace in Acumatica
1. Navigate to SM201500 (Request Profiler)
2. Start profiling
3. Reproduce the error
4. Stop and review exceptions

### Common Error Patterns

| Error Message | Likely Cause | Fix |
|--------------|--------------|-----|
| "page should be inherited from PXPage" | Missing `Inherits="PX.Web.UI.PXPage"` | Add to Page directive |
| "file does not exist" | CodeFile attribute or path mismatch | Remove CodeFile, check Frames vs Pages |
| "ScreenId=00000000" | PrimaryView mismatch or no SiteMap entry | Verify view name, check ScreenWithRights |
| "Object reference not set" | Empty level attribute or corrupt project.xml | Set level="0" or level="1" |
| "Nullable object must have a value" | Acumatica state issue, not package | Try: unpublish all, clear cache, republish |
| "Graph type not found" | Wrong namespace or missing assembly in TypeName | Use full `Namespace.Class, Assembly` |

### Clean Slate Recovery
When nothing else works:
```powershell
# 1. Stop IIS
iisreset /stop

# 2. Delete cached ASPX from Acumatica folder
Remove-Item "C:\Program Files\Acumatica ERP\AcumaticaERP\Frames\AS*.aspx" -Force

# 3. Clear Acumatica temp files
Remove-Item "C:\Program Files\Acumatica ERP\AcumaticaERP\App_RuntimeCode\*" -Recurse -Force

# 4. Restart IIS
iisreset /start

# 5. In Acumatica: SM204505 > Unpublish All > Re-import package > Publish
```
