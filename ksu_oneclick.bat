@echo off
chcp 65001 >nul
setlocal

echo ═══════════════════════════════════════════════
echo   KernelSU 一键加载 v2
echo   每次开机后运行此脚本
echo ═══════════════════════════════════════════════
echo.

set "DIR=%~dp0"
set "KO=%DIR%android15-6.6_kernelsu.ko"
set "PATCHED=%DIR%kernelsu_patched.ko"
set "KSUD=%DIR%ksud-aarch64-linux-android"
set "PATCHER=%DIR%patch_ksu_module.py"
set "KALLSYMS=%DIR%kallsyms.txt"

:: ─── 检查 ADB ───
echo 检查 ADB 连接...
adb get-state >nul 2>&1
if errorlevel 1 (
    echo [X] 没有 ADB 设备，请连接手机
    goto :fail
)
echo [OK] ADB 已连接
echo.

:: ─── 推送脚本 + ksud ───
echo 推送文件到设备...
adb push "%DIR%ksu_step1.sh" /data/local/tmp/ksu_step1.sh >nul 2>&1
adb push "%DIR%ksu_step2.sh" /data/local/tmp/ksu_step2.sh >nul 2>&1
adb push "%KSUD%" /data/local/tmp/ksud-aarch64 >nul 2>&1
echo [OK] 文件已推送
echo.

:: ═════════════════════════════════════
echo [1/5] 拉取 kallsyms...
:: ═════════════════════════════════════

:: 始终重新拉取（重启后 KASLR 地址变了）
if exist "%KALLSYMS%" del "%KALLSYMS%" >nul 2>&1
if exist "%PATCHED%" del "%PATCHED%" >nul 2>&1

adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "sh" i32 1 s16 "/data/local/tmp/ksu_step1.sh" s16 "/storage/emulated/0/ksu_result.txt" i32 60 >nul 2>&1

echo 等待 kallsyms 拉取...
timeout /t 15 /nobreak >nul

:: 拉取到 PC
adb pull /data/local/tmp/kallsyms.txt "%KALLSYMS%" >nul 2>&1
if not exist "%KALLSYMS%" (
    echo [!] 第一次拉取失败，多等10秒重试...
    timeout /t 10 /nobreak >nul
    adb pull /data/local/tmp/kallsyms.txt "%KALLSYMS%" >nul 2>&1
)
if not exist "%KALLSYMS%" (
    echo [X] kallsyms 拉取失败
    goto :fail
)
echo [OK] kallsyms 已拉取
echo.

:: ═════════════════════════════════════
echo [2/5] 补丁内核模块 (PC端 Python)...
:: ═════════════════════════════════════

.\python\python.exe "%PATCHER%" "%KO%" "%KALLSYMS%" "%PATCHED%"
if errorlevel 1 (
    echo [X] 补丁失败
    goto :fail
)
if not exist "%PATCHED%" (
    echo [X] 补丁文件未生成
    goto :fail
)
echo [OK] 补丁完成
echo.

:: ═════════════════════════════════════
echo [3-5/5] 加载模块 + 部署ksud + 触发Manager...
:: ═════════════════════════════════════

:: 推送补丁后的 ko
adb push "%PATCHED%" /data/local/tmp/kernelsu_patched.ko >nul 2>&1

:: 执行 step2 (insmod + ksud + trigger)
adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "sh" i32 1 s16 "/data/local/tmp/ksu_step2.sh" s16 "/storage/emulated/0/ksu_result.txt" i32 60 >nul 2>&1

echo 等待加载完成...
timeout /t 25 /nobreak >nul

:: 显示完整结果
echo.
echo ══════════ 执行结果 ══════════
adb shell cat /storage/emulated/0/ksu_result.txt
echo.

:: 检查是否成功
adb shell cat /storage/emulated/0/ksu_result.txt 2>nul | findstr "ALL_DONE" >nul 2>&1
if not errorlevel 1 (
    echo ═══════════════════════════════════════════════
    echo   加载完成！打开 KernelSU Manager 检查状态
    echo   如需重启框架(LSPosed): restart_framework.bat
    echo ═══════════════════════════════════════════════
) else (
    echo ═══════════════════════════════════════════════
    echo   [!] 可能未完全成功，请检查上面的输出
    echo ═══════════════════════════════════════════════
)
echo.
pause
goto :eof

:fail
echo.
echo [X] 加载失败，请检查上面的错误信息
pause
