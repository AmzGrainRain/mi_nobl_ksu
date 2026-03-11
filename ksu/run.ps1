[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===================== 初始化配置 =====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🔧 KernelSU 自动部署脚本 - 开始执行" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Remove-Item -Path .\kallsyms, .\kernelsu_patched.ko -ErrorAction SilentlyContinue

# 配置路径（转为绝对路径，避免相对路径歧义）
$ADB_HOME = Join-Path $PSScriptRoot "..\adb"
$PYTHON_HOME = Join-Path $PSScriptRoot "..\python"
$env:PATH += ";$ADB_HOME;$PYTHON_HOME"

# 定义核心变量
$KSU_MANAGER = ".\KernelSU_v3.1.0_32302-release.apk"
$KSUD = ".\ksud-aarch64-linux-android"
$VERSIONS_DIR = ".\versions"
$KSU_HOME = "/data/adb/ksu"

# 打印初始化信息
Write-Host "📋 初始化配置信息：" -ForegroundColor Cyan
Write-Host "   - ADB 路径：$ADB_HOME"
Write-Host "   - Python 路径：$PYTHON_HOME"
Write-Host "   - KSU 管理器APK：$KSU_MANAGER"
Write-Host "   - KSUD 二进制文件：$KSUD"
Write-Host "   - 版本文件目录：$VERSIONS_DIR`n"

# ===================== 1. 检查ADB Root权限 =====================
Write-Host "🔍 步骤 1/7：检查 ADB Root 权限..." -ForegroundColor Blue
$IS_ADB_ROOT = (adb root | Out-String).Trim()

if ($IS_ADB_ROOT -eq "adbd is already running as root") {
    Write-Host "✅ 已成功获取 adb root 权限！" -ForegroundColor Green
    Write-Host "   - 返回信息：$IS_ADB_ROOT`n"
} else {
    Write-Host "❌ 未能获取 adb root 权限！" -ForegroundColor Red
    Write-Host "   - 返回信息：$IS_ADB_ROOT`n"
    pause
    exit 1
}

# ===================== 2. 备份kptr状态并导出kallsyms =====================
Write-Host "🔍 步骤 2/7：备份 kptr 状态并导出 kallsyms 文件..." -ForegroundColor Blue
try {
    # 获取当前kptr_restrict值
    $KPTR_RESTRICT = (adb shell cat /proc/sys/kernel/kptr_restrict | Out-String).Trim()
    Write-Host "   - 当前 kptr_restrict 值：$KPTR_RESTRICT"

    # 临时修改kptr_restrict为0
    Write-Host "   - 临时设置 kptr_restrict 为 0..."
    adb shell "echo 0 > /proc/sys/kernel/kptr_restrict"
    $newKptr = (adb shell cat /proc/sys/kernel/kptr_restrict | Out-String).Trim()
    if ($newKptr -ne "0") {
        throw "设置 kptr_restrict 为 0 失败，当前值：$newKptr"
    }

    # 拉取到本地
    Write-Host "   - 拉取 kallsyms 文件到本地..."
    adb shell cat /proc/kallsyms > .\kallsyms

    # 恢复kptr_restrict原值
    Write-Host "   - 恢复 kptr_restrict 为原值：$KPTR_RESTRICT..."
    adb shell "echo $KPTR_RESTRICT > /proc/sys/kernel/kptr_restrict"
    $restoreKptr = (adb shell cat /proc/sys/kernel/kptr_restrict | Out-String).Trim()
    if ($restoreKptr -ne $KPTR_RESTRICT) {
        Write-Warning "⚠️ 恢复 kptr_restrict 值失败，当前值：$restoreKptr（预期：$KPTR_RESTRICT）"
    }

    # 输出成功日志
    Write-Host "✅ 已成功导出 kallsyms 文件！" -ForegroundColor Green
    Write-Host "   - 本地文件路径：$((Resolve-Path .\kallsyms).Path)`n"
}
catch {
    Write-Host "❌ 导出 kallsyms 失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

# ===================== 3. 选择versions目录下的.ko文件 =====================
Write-Host "🔍 步骤 3/7：选择 versions 目录下的 .ko 文件..." -ForegroundColor Blue
try {
    # 查找.ko文件
    Write-Host "   - 扫描目录：$VERSIONS_DIR"
    $koFiles = Get-ChildItem -Path $VERSIONS_DIR -Filter "*.ko" -File -ErrorAction Stop
    
    if ($koFiles.Count -eq 0) {
        throw "未找到任何 .ko 文件"
    }

    # 显示文件列表
    Write-Host "   - 找到 $($koFiles.Count) 个 .ko 文件："
    for ($i = 0; $i -lt $koFiles.Count; $i++) {
        $fileSize = ($koFiles[$i].Length / 1024 / 1024).ToString('0.00')  # MB
        Write-Host "     $($i+1). $($koFiles[$i].Name) ($fileSize MB)"
    }

    # 交互式选择
    do {
        $selection = Read-Host "`n   请输入选择的序号 [1-$($koFiles.Count)]"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $koFiles.Count) {
            $selectedIndex = [int]$selection - 1
            $KO_FILE = $koFiles[$selectedIndex].FullName
            break
        }
        else {
            Write-Host "   ❌ 输入无效！请输入 1-$($koFiles.Count) 之间的数字。" -ForegroundColor Red
        }
    } while ($true)
    
    # 输出选择结果
    Write-Host "✅ 已选择目标 .ko 文件！" -ForegroundColor Green
    Write-Host "   - 选择文件：$KO_FILE"
    Write-Host "   - 文件大小：$(((Get-Item $KO_FILE).Length / 1024 / 1024).ToString('0.00')) MB`n"
}
catch {
    Write-Host "❌ 读取 versions 目录/选择文件失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

# ===================== 4. 执行 PowerShell 补丁脚本 =====================
Write-Host "🔍 步骤 4/7：执行 PowerShell 补丁脚本..." -ForegroundColor Blue
try {
    Write-Host "   - 执行命令：.\patch_ksu_module.ps1 $KO_FILE .\kallsyms .\kernelsu_patched.ko"
    # 捕获脚本输出和返回值
    $patchOutput = (& .\patch_ksu_module.ps1 $KO_FILE .\kallsyms .\kernelsu_patched.ko 2>&1 | Out-String).Trim()
    $patchExitCode = $LASTEXITCODE

    # 检查返回值和文件是否生成
    if ($patchExitCode -ne 0) {
        throw "补丁脚本执行返回非 0 值（$patchExitCode），输出：$patchOutput"
    }
    if (-not (Test-Path .\kernelsu_patched.ko)) {
        throw "补丁脚本执行后未生成 kernelsu_patched.ko 文件，脚本输出：$patchOutput"
    }

    # 输出成功日志
    $patchedFileSize = ((Get-Item .\kernelsu_patched.ko).Length / 1024 / 1024).ToString('0.00')
    Write-Host "✅ 补丁脚本执行成功！" -ForegroundColor Green
    Write-Host "   - 脚本返回值：$patchExitCode"
    Write-Host "   - 生成文件：$((Resolve-Path .\kernelsu_patched.ko).Path)"
    Write-Host "   - 文件大小：$patchedFileSize MB"
    if ($patchOutput) {
        Write-Host "   - 脚本输出：`n$patchOutput`n"
    } else {
        Write-Host "   - 脚本输出：无`n"
    }
}
catch {
    Write-Host "❌ 补丁脚本执行失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

# ===================== 5. 推送并加载ko文件 =====================
Write-Host "🔍 步骤 5/7：推送并加载 ko 文件..." -ForegroundColor Blue
try {
    # 推送ko文件
    Write-Host "   - 推送 kernelsu_patched.ko 到安卓设备：/data/local/tmp/kernelsu_patched.ko"
    adb push .\kernelsu_patched.ko /data/local/tmp/kernelsu_patched.ko

    # 检查是否已加载kernelsu
    $kernelsuLoaded = (adb shell grep "kernelsu" /proc/modules | Out-String).Trim()
    Write-Host "   - 加载前 kernelsu 状态：$(if ($kernelsuLoaded) { $kernelsuLoaded } else { '未加载' })"

    # 未加载则执行insmod
    if ($kernelsuLoaded -eq "") {
        Write-Host "   - 执行 chmod 644 /data/local/tmp/kernelsu_patched.ko"
        adb shell "chmod 644 /data/local/tmp/kernelsu_patched.ko"
        
        Write-Host "   - 执行 insmod 加载 ko 文件..."
        $insmodResult = (adb shell "insmod /data/local/tmp/kernelsu_patched.ko" 2>&1 | Out-String).Trim()
        if ($insmodResult -and -not $insmodResult.Trim() -eq "") {
            Write-Warning "⚠️ insmod 执行返回非空信息：$insmodResult"
        }

        # 等待3秒后检查状态
        Write-Host "   - 等待 3 秒，检查加载状态..."
        Start-Sleep -Seconds 3
        $kernelsuLoaded = (adb shell grep "kernelsu" /proc/modules | Out-String).Trim()
    }

    # 输出结果
    Write-Host "✅ 推送/加载 ko 文件完成！" -ForegroundColor Green
    Write-Host "   - 加载后 kernelsu 状态：$(if ($kernelsuLoaded) { $kernelsuLoaded } else { '未加载' })`n"
}
catch {
    Write-Host "❌ 推送/加载 ko 文件失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

# ===================== 6. 部署KSUD和安装管理器 =====================
Write-Host "🔍 步骤 6/7：部署 KSUD 并安装 KSU 管理器..." -ForegroundColor Blue
try {
    # 创建目录
    Write-Host "   - 创建 KSU 目录：$KSU_HOME/bin $KSU_HOME/log $KSU_HOME/modules"
    adb shell "mkdir -p $KSU_HOME/bin $KSU_HOME/log $KSU_HOME/modules"

    # 推送KSUD
    Write-Host "   - 推送 KSUD 到：$KSU_HOME/bin/ksud"
    adb push $KSUD "$KSU_HOME/bin/ksud"

    # 设置权限
    Write-Host "   - 设置 KSUD 权限：chmod 755 $KSU_HOME/bin/ksud"
    adb shell "chmod 755 $KSU_HOME/bin/ksud"
    
    Write-Host "   - 设置目录所有者：chown -R 0:1000 $KSU_HOME"
    adb shell "chown -R 0:1000 $KSU_HOME"

    # 执行 KSUD 命令
    Write-Host "   - 执行 ksud late-load..."
    $postFsData = (adb shell "$KSU_HOME/bin/ksud late-load" 2>&1 | Out-String).Trim()
    Start-Sleep -Seconds 3`

    Write-Host "   - 删除 magisk 软链接：rm -f $KSU_HOME/bin/magisk"
    adb shell "rm -f $KSU_HOME/bin/magisk"

    # 删除原先的 KSU 管理器（如果有）
    if ((adb shell pm path me.weishu.kernelsu | Out-String).Trim() -ne '') {
        adb shell pm uninstall me.weishu.kernelsu
    }

    # 推送并安装APK
    $apkFileName = Split-Path -Path $KSU_MANAGER -Leaf
    Write-Host "   - 推送 KSU 管理器 APK 到：/data/local/tmp/$apkFileName"
    adb push $KSU_MANAGER "/data/local/tmp/$apkFileName"

    Write-Host "   - 安装 APK：pm install -r /data/local/tmp/$apkFileName"
    adb shell "pm install -r /data/local/tmp/$apkFileName"

    Write-Host "   - 删除临时 APK 文件：rm -f /data/local/tmp/$apkFileName"
    adb shell "rm -f /data/local/tmp/$apkFileName"

    # 输出部署结果
    Write-Host "✅ KSUD 部署&APK 安装完成！" -ForegroundColor Green
    Write-Host "   - ksud post-fs-data 输出：$($postFsData ? $postFsData : '无')"
    Write-Host "   - ksud services 输出：$($services ? $services : '无')"
    Write-Host "   - ksud boot-completed 输出：$($bootCompleted ? $bootCompleted : '无')"
}
catch {
    Write-Host "❌ KSUD 部署/APK 安装失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

# ===================== 7. 最终状态检查 =====================
Write-Host "🔍 步骤 7/7：最终状态检查..." -ForegroundColor Blue

# 多重检查
$kernelsuModule = (adb shell grep "kernelsu" /proc/modules | Out-String).Trim()
$ksudProcess = (adb shell "ps | grep ksud" 2>&1 | Out-String).Trim()
$ksuDirExists = (adb shell "test -d $KSU_HOME && echo 'exists' || echo 'not exists'" | Out-String).Trim()

# 输出检查结果
Write-Host "📊 最终状态检查结果：" -ForegroundColor Cyan
Write-Host "   - kernelsu 模块加载状态：$(if ($kernelsuModule) { "✅ 已加载`n     $kernelsuModule" } else { "❌ 未加载" })"
Write-Host "   - KSUD 进程状态：$(if ($ksudProcess) { "✅ 运行中`n     $ksudProcess" } else { "❌ 未找到进程" })"
Write-Host "   - KSU 目录存在性：$(if ($ksuDirExists -eq 'exists') { "✅ 存在" } else { "❌ 不存在" })`n"

Write-Host "========================================" -ForegroundColor Cyan
$kernelsuLoaded = (adb shell grep "kernelsu" /proc/modules | Out-String).Trim()
if ($kernelsuLoaded -ne "") {
    Write-Host "🎉 KernelSU 部署完成！" -ForegroundColor Green
    Write-Host "✅ 所有核心步骤执行成功！" -ForegroundColor Green
} else {
    Write-Host "⚠️ KernelSU 部署完成，但模块加载失败！" -ForegroundColor Yellow
    Write-Host "❌ 核心功能未生效，请检查日志排查问题！" -ForegroundColor Red
}
Write-Host "========================================`n"

pause
