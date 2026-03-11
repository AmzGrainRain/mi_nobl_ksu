[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ADB_PATH = (Resolve-Path -Path ..\adb).Path
$env:PATH += ";$ADB_PATH"

# 定义核心变量
$KSU_MANAGER = ".\KernelSU_v3.1.0-29-gf0615d3c_32331-release.apk"
$KSUD = ".\ksud-aarch64-linux-android"
$KSU_HOME = "/data/adb/ksu"

# 1. 初始准备阶段
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第一步：准备进入 Fastboot 模式" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📱 请完成以下操作：" -ForegroundColor Yellow
Write-Host "   1. 打开开发者模式（设置-关于手机-连续点击版本号）" -ForegroundColor White
Write-Host "   2. 解锁手机并进入系统桌面" -ForegroundColor White
Write-Host "   3. 确保手机已连接电脑并允许 USB 调试`n" -ForegroundColor White
Write-Host "✅ 操作完成后按任意键继续..." -NoNewline -ForegroundColor Green
[void][System.Console]::ReadKey($true)

# 检查设备连接状态
Write-Host "`n🔍 正在检测已连接的设备..." -ForegroundColor Yellow
adb devices
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 检测到ADB命令执行失败，请检查 ADB 环境或设备连接！" -ForegroundColor Red
    pause
    exit 1
}

# 重启到 Fastboot 模式
Write-Host "`n🚀 正在重启设备进入 Fastboot 模式..." -ForegroundColor Yellow
adb reboot bootloader
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 命令执行失败！" -ForegroundColor Red
    pause
    exit 1
}

# 2. Fastboot 模式操作阶段
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第二步：Fastboot 模式配置" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📱 请确认设备已进入 Fastboot 模式（屏幕显示 Fastboot 字样）`n" -ForegroundColor Yellow
Write-Host "✅ 确认后按任意键继续..." -NoNewline -ForegroundColor Green
[void][System.Console]::ReadKey($true)

# 执行 Fastboot 配置命令
Write-Host "`n⚙️  正在通过漏洞设置 SELinux 为 Permissive ..." -ForegroundColor Yellow
fastboot oem set-gpu-preemption 0 androidboot.selinux=permissive
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 命令执行失败！" -ForegroundColor Red
    pause
    exit 1
}

# 继续启动系统
Write-Host "🚀 正在引导设备进入系统..." -ForegroundColor Yellow
fastboot continue
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 命令执行失败！" -ForegroundColor Red
    pause
    exit 1
}

# 3. 检查 SELinux 状态
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第三步：检查 SELinux 状态" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
$SELINUX_STATUS = (adb shell getenforce | Out-String).Trim()

if ($SELINUX_STATUS -eq "Enforcing") {
    Write-Host "✅ SELinux 状态正常！" -ForegroundColor Green
    Write-Host "   - 返回信息：$SELINUX_STATUS`n"
} else {
    Write-Host "❌ SELinux 状态异常！" -ForegroundColor Red
    Write-Host "   - 返回信息：$SELINUX_STATUS`n"
    pause
    exit 1
}

# 4. 部署 KernelSU
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第四步：部署 KernelSU" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📋 初始化配置信息：" -ForegroundColor Cyan
Write-Host "   - ADB 路径：$ADB_HOME"
Write-Host "   - KSU 管理器 APK：$KSU_MANAGER"
Write-Host "   - KSUD 二进制文件：$KSUD`n"
Write-Host "✅ 确认后按任意键继续..." -NoNewline -ForegroundColor Green

try {
    # 推送 ksud 二进制文件
    Write-Host "   - 推送 KSUD 到：/data/local/tmp/ksud"
    adb push $KSUD "/data/local/tmp/ksud"

    # 设置权限
    Write-Host "   - 设置 KSUD 权限：chmod 755 /data/local/tmp/ksud"
    adb shell "chmod 755 /data/local/tmp/ksud"
    
    Write-Host "   - 设置目录所有者：chown -R 0:1000 $KSU_HOME"
    adb shell "chown -R 0:1000 $KSU_HOME"

    # 执行 ksud late-load
    Write-Host "   - 执行 ksud late-load..."
    adb shell "/data/local/tmp/ksud late-load"
    Start-Sleep -Seconds 3`

    # 安装 KernelSU Manager
    if ((adb shell pm path me.weishu.kernelsu | Out-String).Trim() -eq '') {
        $apkFileName = Split-Path -Path $KSU_MANAGER -Leaf
        Write-Host "   - 推送 KSU 管理器 APK 到：/data/local/tmp/$apkFileName"
        adb push $KSU_MANAGER "/data/local/tmp/$apkFileName"

        Write-Host "   - 安装 APK：pm install -r /data/local/tmp/$apkFileName"
        adb shell "pm install -r /data/local/tmp/$apkFileName"

        Write-Host "   - 删除临时 APK 文件：rm -f /data/local/tmp/$apkFileName"
        adb shell "rm -f /data/local/tmp/$apkFileName"
    }

    # 输出部署结果
    $kernelsuModule = (adb shell grep "kernelsu" /proc/modules | Out-String).Trim()
    if ($kernelsuModule -ne "") {
        Write-Host "✅ KernelSU 部署完成！" -ForegroundColor Green
    } else {
        Write-Host "❌ KernelSU 部署失败！" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ KernelSU 部署失败！" -ForegroundColor Red
    Write-Host "   - 错误详情：$_`n"
    pause
    exit 1
}

pause
