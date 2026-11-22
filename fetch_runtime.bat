@echo off
rem 下载「便携 Python」到 runtime\windows-amd64（免安装、不需要管理员权限、只写本目录）。
rem get_hrefstr.bat 会自动优先使用它。
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
title 下载便携 Python

set "DIR=%~dp0"
set "VER=3.13.9"
set "DEST=%DIR%runtime\windows-amd64"
set "ZIP=%TEMP%\gethrefstr-python-%VER%.zip"

rem ARM64 Windows 也能跑 amd64 版（走模拟），所以只有明确的 ARM64 才换包。
set "ARCH=amd64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"
echo 下载 Python %VER% (%ARCH%) …

if exist "%ZIP%" del /q "%ZIP%"
curl.exe -fL --retry 2 -o "%ZIP%" "https://registry.npmmirror.com/-/binary/python/%VER%/python-%VER%-embed-%ARCH%.zip" 2>nul
if not exist "%ZIP%" curl.exe -fL --retry 2 -o "%ZIP%" "https://www.python.org/ftp/python/%VER%/python-%VER%-embed-%ARCH%.zip" 2>nul
if not exist "%ZIP%" goto fail

if exist "%DEST%" rd /s /q "%DEST%"
mkdir "%DEST%"
tar -xf "%ZIP%" -C "%DEST%"
if not exist "%DEST%\python.exe" goto fail
del /q "%ZIP%"

echo 完成：%DEST%
"%DEST%\python.exe" -V
echo.
echo 现在可以直接双击 get_hrefstr.bat 了。
pause
exit /b 0

:fail
echo.
echo 下载或解压失败。可以手动下载：
echo   https://www.python.org/ftp/python/%VER%/python-%VER%-embed-%ARCH%.zip
echo 解压到目录：%DEST%
pause
exit /b 1
