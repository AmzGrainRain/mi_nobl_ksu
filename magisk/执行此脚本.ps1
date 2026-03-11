[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ADB_PATH = (Resolve-Path -Path ..\adb).Path
$env:PATH += ";$ADB_PATH"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          开始推送文件并执行Root配置" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. 等待设备连接
Write-Host "🔍 正在等待设备ADB连接..." -ForegroundColor Yellow
adb wait-for-device

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 错误：设备 ADB 连接超时！请检查设备是否已连接并开启 USB 调试。" -ForegroundColor Red
    pause
    exit 1
}
Write-Host "✅ 设备已成功连接！`n" -ForegroundColor Green

# 2. 检查设备权限状态
Write-Host "🔑 正在检查设备当前权限状态..." -ForegroundColor Yellow
$IS_ROOT_RESULT = adb root | Out-String
$IS_ROOT_RESULT = $IS_ROOT_RESULT.Trim()
if ($IS_ROOT_RESULT -eq "adbd is already running as root") {
    Write-Host "✅ 权限状态检查完成" -ForegroundColor Green
} else {
    Write-Host "❌ 未能获取 adb root 权限！" -ForegroundColor Red
    pause
    exit 1
}

# 3. 推送文件列表
$filesToPush = @(
    @{LocalPath = ".\busybox"; RemotePath = "/data/local/tmp/"},
    @{LocalPath = ".\magisk.apk"; RemotePath = "/data/local/tmp/"},
    @{LocalPath = ".\live_setup.sh"; RemotePath = "/data/local/tmp/"}
)

Write-Host "📤 开始推送文件到设备（共 $($filesToPush.Count) 个文件）：" -ForegroundColor Yellow
foreach ($file in $filesToPush) {
    $fileName = Split-Path $file.LocalPath -Leaf
    Write-Host "   推送 $fileName ..." -ForegroundColor White -NoNewline
    
    adb push $file.LocalPath $file.RemotePath
    if ($LASTEXITCODE -eq 0) {
        Write-Host " ✅" -ForegroundColor Green
    } else {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "⚠️  警告：文件 $fileName 推送失败，请检查文件是否存在！" -ForegroundColor Yellow
    }
}
Write-Host "`n📤 所有文件推送操作已完成`n" -ForegroundColor Green
Push-Location ..\adb

# 4. 等待文件同步
Write-Host "⏳ 确保文件完全同步到设备..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# 5. 修改文件执行权限
Write-Host "🔧 正在赋予文件执行权限..." -ForegroundColor Yellow
adb shell chmod +x -Rv "/data/local/tmp/busybox" "/data/local/tmp/live_setup.sh"
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 文件权限修改完成`n" -ForegroundColor Green
} else {
    Write-Host "❌ 错误：文件权限修改失败！" -ForegroundColor Red
    pause
    exit 1
}

# 6. 执行核心脚本
Write-Host "🚀 开始执行 live_setup.sh 脚本（核心Root配置）..." -ForegroundColor Yellow
Write-Host "----------------------------------------`n" -ForegroundColor White
adb shell "cd /data/local/tmp && ./live_setup.sh"
Write-Host "`n----------------------------------------" -ForegroundColor White

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ live_setup.sh 脚本执行完成！" -ForegroundColor Green
} else {
    Write-Host "❌ 错误：live_setup.sh 脚本执行失败！请检查脚本内容或设备权限。" -ForegroundColor Red
}

# 结束提示
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "          操作流程执行完毕" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "📌 请检查以上输出信息，确认所有步骤是否成功完成。" -ForegroundColor Yellow
Start-Sleep -Seconds 30
pause
