@echo off
rem 读取厦大体育 H5 hrefstr（Windows 入口）。
rem 优先用 runtime\windows-*\python.exe（免安装），没有才找系统 Python。
rem 成功后把 hrefstr 复制到剪贴板并显示；本脚本不读也不写凭据。
rem
rem 维护提醒：本文件必须保存为 UTF-8（无 BOM）+ CRLF 换行，
rem 否则 cmd 解析 goto 标签会失败（双击后窗口一闪而过），中文也会乱码。
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
title 获取厦大体育 hrefstr

set "CHECK=import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)"
set "PYQ="
set "EXITCODE=0"

rem 双击时 cmd 的命令行里含本文件名；命令行里手动执行则没有。只在前者停住等按键。
set "INTERACTIVE=0"
echo !cmdcmdline!| find /i "%~nx0" >nul && set "INTERACTIVE=1"

rem 切到脚本目录，后面统一用不带空格的相对路径。
rem 原因：for /f 会把命令交给 cmd /c，如果命令以带引号的路径开头（"C:\...\python.exe"），
rem cmd 会剥掉首尾引号，拼出一个含引号的非法路径，报
rem "The filename, directory name, or volume label syntax is incorrect."。
set "PUSHED=0"
pushd "%~dp0" >nul 2>nul && set "PUSHED=1"
if not "%PUSHED%"=="1" (
    echo 无法进入脚本所在目录：%~dp0
    set "EXITCODE=2"
    goto done
)

rem 1) 随包便携运行时（相对路径，不带引号，避开上面那个坑）
if exist "runtime\windows-amd64\python.exe" set "PYQ=runtime\windows-amd64\python.exe"
if not defined PYQ if exist "runtime\windows-arm64\python.exe" set "PYQ=runtime\windows-arm64\python.exe"
if defined PYQ (
    %PYQ% -c "%CHECK%" >nul 2>nul
    if errorlevel 1 set "PYQ="
)
if defined PYQ goto have_python

rem 2) 系统 Python：py 启动器 → python → python3，都要求 3.8+
py -3 -c "%CHECK%" >nul 2>nul
if not errorlevel 1 set "PYQ=py -3"
if defined PYQ goto have_python
python -c "%CHECK%" >nul 2>nul
if not errorlevel 1 set "PYQ=python"
if defined PYQ goto have_python
python3 -c "%CHECK%" >nul 2>nul
if not errorlevel 1 set "PYQ=python3"
if defined PYQ goto have_python
goto no_python

:have_python
echo 正在读取 hrefstr（只读本机数据，不联网）…

rem 带 --json 时按机器可读原样输出，不动剪贴板。
set "JSON="
echo %*| find /i "--json" >nul && set "JSON=1"
if defined JSON goto plain_run

rem 把 stdout 收进变量，再交给 clip；stderr（诊断信息）照常显示在窗口里。
set "HREF="
for /f "delims=" %%L in ('%PYQ% "get_hrefstr.py" %*') do if not defined HREF set "HREF=%%L"
if not defined HREF (
    echo.
    echo 自动复制没成功，下面直接执行一次；结果请手动复制：
    %PYQ% "get_hrefstr.py" %*
    if errorlevel 1 goto failed
    goto done
)

<nul set /p "=!HREF!"|clip
echo 已复制到剪贴板：
echo.
echo !HREF!
goto done

:plain_run
%PYQ% "get_hrefstr.py" %*
if errorlevel 1 goto failed
goto done

:no_python
echo 未找到可用的 Python 3.8+，本目录也没有内置运行时。
echo.
echo 任选其一：
echo   1. 跑一次 fetch_runtime.bat：自动下载到 runtime\windows-amd64（约 11MB）
echo   2. 安装 Python 3：https://www.python.org/downloads/
echo      安装时勾选 "Add python.exe to PATH"
set "EXITCODE=2"
goto done

:failed
echo.
echo 读取失败。常见原因：
echo   1. 还没在微信里打开过「厦大体育 -^> 场馆预约」，打开一次让页面写入 LocalStorage
echo   2. 微信 4.x 的目录与旧版不同，可按上面提示用 --verbose 或 --db 排查
echo   3. 微信已切到新版 h5_token 分支（LocalStorage 里 isNewAjaxRes 为真）
set "EXITCODE=1"

:done
if "%PUSHED%"=="1" popd
if "%INTERACTIVE%"=="1" (
    echo.
    echo 按任意键关闭窗口。
    pause >nul
)
endlocal & exit /b %EXITCODE%
