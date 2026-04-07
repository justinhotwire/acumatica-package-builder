@echo off
echo Deploying AcuSales.Core.dll to Acumatica...
copy /Y "C:\Users\JUSTIN~1\AppData\Local\Temp\AcuSales.Core.dll" "C:\Program Files\Acumatica ERP\AcumaticaERP\Bin\"
if errorlevel 1 (
    echo ERROR: Copy failed
    exit /b 1
) else (
    echo SUCCESS: DLL deployed
)
