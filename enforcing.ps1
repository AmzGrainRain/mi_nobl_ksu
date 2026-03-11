Write-Host "🔧 正在重启 ADB 服务以确保更改生效..." -ForegroundColor Blue
adb shell 'kill -9 $(pidof adbd)'
adb wait-for-device
Write-Host "🔧 正在将 SELinux 设置为 Enforcing 模式..." -ForegroundColor Blue
adb shell su -c setenforce 1
Write-Host "✅ 已成功将 SELinux 设置为 Enforcing 模式！" -ForegroundColor Green
Write-Host "   - 返回信息：$(adb shell getenforce | Out-String)".Trim() -ForegroundColor Green
Write-Host "✅ 操作完成后按任意键继续..." -NoNewline -ForegroundColor Green
[void][System.Console]::ReadKey($true)
