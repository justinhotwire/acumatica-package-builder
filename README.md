# Acumatica Package Builder Skill

## Overview

This skill builds Acumatica ERP customization packages correctly from source code. Instead of fixing broken packages, it creates deployment-ready zip files that import and publish successfully on the first try.

## When to Use

Invoke this skill when:
- Building a customization package for deployment to Acumatica
- Packaging custom screens, graphs, and DLLs for SM204505 import
- Need to create a properly structured customization zip
- Want to avoid common package errors before they happen

## What It Does

1. **Scans source code** to identify:
   - Custom DLLs (compiled assemblies)
   - ASPX screen files
   - PXGraph classes and their namespaces
   - SQL initialization scripts
   - JavaScript/CSS assets

2. **Validates ASPX files** to prevent ASPPARSE errors:
   - Removes `CodeFile` and `Inherits` attributes from Page directives
   - Removes HTML comments from control collections
   - Removes invalid control properties
   - Verifies PrimaryView matches graph view names

3. **Generates project.xml** with correct structure:
   - Places at zip root (not in subdirectory)
   - Sets proper `level` attribute ("0" for new, "1" for update)
   - Lists all files with backslash paths
   - Creates ScreenWithRights sections with GraphType attributes
   - Creates SiteMapNode sections for Modern UI
   - Generates unique NodeIDs for each screen

4. **Builds the zip package** with proper structure:
   - project.xml at root
   - Bin/ folder with DLLs
   - Pages/ folder with ASPX files
   - Scripts/ folder with SQL and assets

5. **Validates before delivery**:
   - Verifies project.xml is at root
   - Checks all referenced files exist
   - Validates XML schema
   - Confirms no ASPX validation issues

6. **Provides deployment instructions**:
   - Step-by-step import guide
   - Troubleshooting tips
   - Test recommendations

## Prevents Common Errors

### ❌ Errors This Skill Prevents

1. **"Object reference not set to an instance of an object"**
   - Caused by: Wrong XML location, empty `level` attribute
   - Prevention: project.xml at root with `level="0"`

2. **"Screens redirect to ScreenId=00000000"**
   - Caused by: Missing GraphType, PrimaryView mismatch
   - Prevention: Proper GraphType in sitemap, validated PrimaryView

3. **"The file '*.aspx.cs' does not exist"**
   - Caused by: CodeFile/Inherits attributes in ASPX
   - Prevention: Removes these attributes automatically

4. **"Literal content not allowed within control collection"**
   - Caused by: HTML comments between control items
   - Prevention: Strips HTML comments from ASPX files

5. **"Type does not have a public property named X"**
   - Caused by: Invalid control properties
   - Prevention: Validates against known invalid properties

## Skill Invocation

**Manually:**
```
/skill acumatica-package-builder
```

**Auto-triggered by keywords:**
- "build acumatica package"
- "create acumatica customization"
- "package acumatica customization"
- "generate acumatica zip"

## Workflow Example

```
User: Build the AcuSales customization package for deployment

Claude: [Invokes acumatica-package-builder skill]

Skill Output:
## Source Code Analysis
Found:
- DLL: AcuSales.Core.dll (AcuSales.* namespace)
- Screens: AS201000, AS301000, AS302000, AS401500
- Graphs:
  - AS201000 → AcuSales.Graph.Maintenance.TerritoryMaint
  - AS301000 → AcuSales.Graph.Workcenter.SalesWorkcenterMaint
  - AS302000 → AcuSales.Graph.Kanban.PipelineKanbanMaint
  - AS401500 → AcuSales.Graph.Workflow.ShareApprovalMaint
- SQL: InitializeDatabase.sql, GrantScreenPermissions.sql
- Assets: kanban.bundle.js, kanban.css

## ASPX Validation
✓ Removed CodeFile from 4 files
✓ Removed Inherits from 4 files
✓ Removed 8 HTML comments
✓ Removed invalid ParentField property
✓ Verified PrimaryView "Filter" matches graph view

## project.xml Generation
✓ Created at root level
✓ Set level="0" (new package)
✓ Added 4 ScreenWithRights entries with GraphType
✓ Added 4 SiteMapNode entries
✓ Generated unique NodeIDs for each screen
✓ Listed 8 files with backslash paths

## Package Built
Location: C:\...\AcuSales-Complete.zip
Size: 151,588 bytes
Structure:
  ✓ project.xml (root)
  ✓ Bin\AcuSales.Core.dll
  ✓ Pages\AS201000.aspx
  ✓ Pages\AS301000.aspx
  ✓ Pages\AS302000.aspx
  ✓ Pages\AS401500.aspx
  ✓ Scripts\InitializeDatabase.sql
  ✓ Scripts\GrantScreenPermissions.sql
  ✓ Scripts\kanban\dist\kanban.bundle.js
  ✓ Scripts\kanban\dist\kanban.css

## Import Instructions
1. Open SM204505 (Customization Projects)
2. Click "Import"
3. Select AcuSales-Complete.zip
4. Click "Upload" - should succeed without errors
5. Click "Publish" - should complete successfully
6. Run: iisreset /noforce
7. Clear browser cache
8. Test screens:
   - AS201000: Rep Workspace
   - AS301000: Rep Customers
   - AS302000: Pipeline Kanban
   - AS401500: Rep Config

All screens should load without redirecting to 00000000.
```

## Files in This Skill

- `skill.json` - Skill manifest and metadata
- `prompt.md` - Main skill instructions and building logic
- `README.md` - This file
- `examples/` - Templates and reference scripts
  - `build-customization-template.ps1` - Reusable build script
  - `project-template.xml` - Reference template for project.xml

## Key Validations

### Package Structure
- ✓ project.xml at root (not in `_project/`)
- ✓ Proper `level` attribute ("0" or "1", never empty)
- ✓ All files use backslash paths in AppRelativePath
- ✓ Bin/, Pages/, Scripts/ folder structure

### Screen Registration
- ✓ GraphType matches full C# namespace
- ✓ Unique NodeID (GUID) for each screen
- ✓ Both ScreenWithRights and SiteMapNode entries
- ✓ Administrator and * (all users) roles included

### ASPX Files
- ✓ No CodeFile attributes in Page directives
- ✓ No Inherits attributes in Page directives
- ✓ No HTML comments between control items
- ✓ No invalid control properties
- ✓ PrimaryView matches graph view name exactly
- ✓ TypeName matches graph namespace exactly

## Comparison with acumatica-package-fixer

**acumatica-package-fixer (reactive):**
- Fixes already-broken packages
- Analyzes import errors after they occur
- Rebuilds packages to correct issues
- Use when: Package already exists but fails to import

**acumatica-package-builder (proactive):**
- Builds packages correctly from the start
- Prevents errors before they happen
- Creates deployment-ready packages
- Use when: Building a new package from source code

**Recommendation**: Use `acumatica-package-builder` for new packages, `acumatica-package-fixer` only if you have a broken package to repair.

## Technical Details

### Supported Acumatica Versions
- 24.200.0010 and later
- XML schema: format-version="4", relations-version="20250701"

### Required project.xml Elements

**Minimum structure:**
```xml
<Customization level="0" description="Package Name" product-version="24.200.0010">
    <File AppRelativePath="Bin\Custom.dll" />
    <File AppRelativePath="Pages\XX101000.aspx" />

    <ScreenWithRights AccessRightsMergeRule="CopyFromTenant">
        <!-- Full role and screen registration -->
    </ScreenWithRights>

    <SiteMapNode>
        <!-- Modern UI integration -->
    </SiteMapNode>
</Customization>
```

**Critical attributes:**
- `level`: Must be "0" or "1", never empty
- `GraphType`: Required in SiteMap rows - full namespace
- `NodeID`: Unique GUID for each screen
- `AppRelativePath`: Backslashes only

## Dependencies

- PowerShell (for zip operations and build scripts)
- .NET SDK (for building C# projects)
- Access to source code directory
- Read/Write permissions in working directory

## Maintenance

When updating this skill:
1. Test against latest Acumatica versions
2. Update XML schema versions if Acumatica changes format
3. Add new validation checks based on discovered issues
4. Update examples with real-world packages

## Related Skills

- `acumatica-package-fixer` - For fixing already-broken packages
- `acumatica-deployment` - For deploying via Visual Studio
- `archon` - For accessing Acumatica documentation

## Version History

- **1.0.0** (2026-01-02)
  - Initial release
  - Supports Acumatica 24.200.0010+
  - Builds packages with proper structure
  - Validates ASPX files automatically
  - Generates project.xml with ScreenWithRights and SiteMapNode
  - Prevents common import errors

## Support

For issues or improvements, update this skill's prompt.md with:
- New validation checks
- Additional error patterns to prevent
- Schema updates for new Acumatica versions
- Improved build automation
