[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ADB_PATH = (Resolve-Path -Path .\adb).Path
$env:PATH += ";$ADB_PATH"

# 定义核心变量
$KSU_MANAGER = ".\KernelSU_v3.1.0-29-gf0615d3c_32331-release.apk"
$KSUD = ".\ksud-aarch64-linux-android"

# 1. 初始准备阶段
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第一步：准备进入 Fastboot 模式" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📱 请完成以下操作：" -ForegroundColor Yellow
Write-Host "   1. 打开开发者模式（设置-关于手机-连续点击版本号）" -ForegroundColor White
Write-Host "   2. 解锁手机并进入系统桌面" -ForegroundColor White
Write-Host "   3. 确保手机已连接电脑并允许 USB 调试`n" -ForegroundColor White
Write-Host "✅ 操作完成后按任意键继续..." -ForegroundColor Green
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
Write-Host "✅ 确认后按任意键继续..." -ForegroundColor Green
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
Write-Host "📱 请确认设备已开机（以听到充电提示音为准）`n" -ForegroundColor Yellow
Write-Host "✅ 确认后按任意键继续..." -ForegroundColor Green
[void][System.Console]::ReadKey($true)

adb wait-for-device
$SELINUX_STATUS = (adb shell getenforce | Out-String).Trim()
if ($SELINUX_STATUS -eq "Permissive") {
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
Write-Host "   - KernelSU Manager：$KSU_MANAGER"
Write-Host "   - KernelSU Daemon：$KSUD`n"
Write-Host "✅ 确认后按任意键继续..." -ForegroundColor Green
[void][System.Console]::ReadKey($true)

try {
    # 推送 KernelSU Daemon 二进制文件
    Write-Host "   - 推送 KernelSU Daemon 到：/data/local/tmp/ksud"
    adb push $KSUD "/data/local/tmp/ksud"

    # 设置权限
    Write-Host "   - 设置 KernelSU Daemon 权限：chmod 755 /data/local/tmp/ksud"
    adb shell "chmod 755 /data/local/tmp/ksud"

    # 执行 ksud late-load
    Write-Host "   - 执行 ksud late-load..."
    adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "/data/local/tmp/ksud" i32 1 s16 "late-load" s16 "/sdcard/ksud.txt" i32 60
    Start-Sleep -Seconds 3

    # 安装 KernelSU Manager
    if ((adb shell pm path me.weishu.kernelsu | Out-String).Trim() -eq '') {
        $apkFileName = Split-Path -Path $KSU_MANAGER -Leaf
        Write-Host "   - 安装 KernelSU Manager..."
        adb push $KSU_MANAGER "/data/local/tmp/$apkFileName"
        adb shell "pm install -r /data/local/tmp/$apkFileName"

        Write-Host "   - 删除临时文件..."
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

# 5. 将 SELinux 状态设置为 Enforcing
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第五步：将 SELinux 状态设置为 Enforcing" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📱 请打开 KernelSU Manager 进入超级用户页面搜索 Shell 并授予 root 权限`n" -ForegroundColor Yellow
Write-Host "✅ 授权后按任意键继续..." -ForegroundColor Green
[void][System.Console]::ReadKey($true)

$shellRoot = $false
while (!$shellRoot) {
    Write-Host "`n🔍 正在验证 shell 是否已获得 root 权限..." -ForegroundColor Yellow
    if ((adb shell su -c 'id -u' | Out-String).Trim() -ne '0') {
        Write-Host "❌ shell 仍未获得 root 权限，请确保已正确授权！" -ForegroundColor Red
        Write-Host "✅ 请重新授权后按任意键继续..." -ForegroundColor Green
        [void][System.Console]::ReadKey($true)
    } else {
        $shellRoot = $true
        Write-Host "✅ shell 已成功获得 root 权限！" -ForegroundColor Green
    }
}

Write-Host "🚀 将 SELinux 状态设置为 Enforcing..." -ForegroundColor Yellow
adb shell su -c 'setenforce 1'
if ((adb shell getenforce | Out-String).Trim() -eq "Enforcing") {
    Write-Host "✅ SELinux 状态已设置为 Enforcing！" -ForegroundColor Green
} else {
    Write-Host "❌ 无法将 SELinux 状态设置为 Enforcing！" -ForegroundColor Red
}
pause