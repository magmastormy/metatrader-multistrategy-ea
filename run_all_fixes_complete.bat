@echo off
echo ========================================
echo RUNNING ALL COMPILATION FIXES
echo ========================================

echo.
echo 1. Fixing array parameters...
powershell -ExecutionPolicy Bypass -File .\fix_array_parameters_final.ps1

echo.
echo 2. Adding CommonTypes to Core files...
powershell -ExecutionPolicy Bypass -File .\fix_all_core_files.ps1

echo.
echo 3. Fixing missing types...
powershell -ExecutionPolicy Bypass -File .\fix_missing_types.ps1

echo.
echo 4. Running comprehensive fix...
powershell -ExecutionPolicy Bypass -File .\comprehensive_fix.ps1

echo.
echo ========================================
echo ALL FIXES COMPLETE!
echo ========================================
echo.
echo Now compiling EA...
call .\compile_EA.bat

pause
