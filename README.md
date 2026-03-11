# 免解锁 Bootloader Root 方案

**适用设备**: 小米 Xiaomi 15 (dada / 24129PN74C)  
**系统版本**: Android 16 (BP2A.250605.031.A3) / HyperOS 3.0 (OS3.0.300.7.WOCCNXM) / kernel 6.6.77  
**Root 方案**: KernelSU v3.1.0 (LKM 运行时加载) + ZygiskSU v1.3.2 + LSPosed IT v1.9.2  
**原理**: 利用 `miui.mqsas.IMQSNative` 服务的 root 执行漏洞，在运行时加载内核模块

## 前提条件

1. **ADB 已连接** — USB 调试已打开
2. **Python 3** — Unix-Like 端需要 Python 3 运行内核模块补丁脚本
3. **KernelSU Manager** — 已安装到设备 (`ksu_manager.apk`)
4. **ZygiskSU** — 已安装为 KSU 模块 (提供 Zygisk 环境)
5. **LSPosed** — 已安装为 KSU 模块 (`LSPosed-v1.9.2-it-7573-release_1773031523.zip`)

## 文件说明

| 文件 | 用途 |
|------|------|
| `ksu_oneclick.bat` | **一键脚本** — Windows 端运行，自动完成 KernelSU 加载全流程 |
| `patch_ksu_module.py` | Python 补丁工具 — 读取运行时 kallsyms，修补 .ko 中的 SHN_UNDEF 符号 |
| `android15-6.6_kernelsu.ko` | KernelSU 内核模块原件 (需补丁后才能加载) |
| `kernelsu_patched.ko` | 补丁后的内核模块 (上次运行 oneclick 的产物，可直接使用) |
| `ksud-aarch64-linux-android` | KernelSU 用户态守护进程 |
| `ksu_manager.apk` | KernelSU Manager App |
| `ksu_step1.sh` | 设备端脚本 — 拉取 `/proc/kallsyms` |
| `ksu_step2.sh` | 设备端脚本 — insmod + 部署 ksud + 触发 Manager + 删除 magisk 兼容链接 |
| `fix_lspd.sh` | **LSPosed 修复脚本** — 重注入 ZygiskSU + 启动 lspd + 安全重启 framework |
| `do_chmod.sh` | 辅助脚本 — 修复 mqsas 输出文件权限 (`chmod 644 /data/local/tmp/*.txt`) |
| `LSPosed-v1.9.2-it-7573-release_1773031523.zip` | LSPosed IT 模块安装包 |

## 使用方法

### 第一步: KernelSU 加载 (每次开机后运行)

```
ksu_oneclick.bat
```

自动完成以下 5 步:
1. 通过 mqsas root 拉取 `/proc/kallsyms` (每次开机 KASLR 地址不同)
2. PC 端 Python 补丁 `.ko` 文件 (修复 SHN_UNDEF 符号地址)
3. 推送补丁后的 `.ko` 到设备
4. 通过 mqsas root 执行 `insmod` 加载内核模块
5. 部署 ksud、执行启动阶段 (`post-fs-data → services → boot-completed`)、触发 Manager 识别

### 第二步: LSPosed 修复 (如显示"未加载")

将 `fix_lspd.sh` 推送到设备后通过 mqsas 执行:

```bat
adb push fix_lspd.sh /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/fix_lspd.sh"
adb shell "service call miui.mqsas.IMQSNative 21 i32 1 s16 '/system/bin/sh' i32 1 s16 '/data/local/tmp/fix_lspd.sh' s16 '/data/local/tmp/lspd_fix_out.txt' i32 180"
```

查看执行结果:
```bat
adb shell "service call miui.mqsas.IMQSNative 21 i32 1 s16 'sh' i32 1 s16 '/data/local/tmp/do_chmod.sh' s16 '/dev/null' i32 5"
timeout /t 3
adb pull /data/local/tmp/lspd_fix_out.txt
type lspd_fix_out.txt
```

该脚本完成以下工作:
1. 杀掉旧 lspd 进程
2. 从 zygote64 进程获取 `BOOTCLASSPATH` 环境变量
3. **重新注入 ZygiskSU** — 直接调用 `zygiskd daemon` + `zygiskd service-stage`
4. 使用 `setsid` + `nsenter -t 1 -m` 守护化启动 lspd (进入 init mount namespace)
5. 杀 zygote64 触发 framework 重启
6. **竞态条件防护** — 记录旧 system_server PID，等其死亡后才查找新 PID
7. 等待 bridge binder 建立 (最多 60 秒)
8. 如 bridge 失败，自动执行 **方案 B**: 杀 system_server 让已注入的 zygote 重新 fork

## 工作原理

```
┌─ PC 端 ──────────────────────────────────────────────────────────┐
│  ksu_oneclick.bat                                                │
│    ├─ adb push 脚本和文件                                         │
│    ├─ mqsas root → ksu_step1.sh → 拉取 kallsyms                  │
│    ├─ patch_ksu_module.py → 补丁 .ko KASLR 符号                   │
│    ├─ adb push 补丁后的 .ko                                       │
│    └─ mqsas root → ksu_step2.sh → insmod + ksud + Manager        │
│                                                                   │
│  fix_lspd.sh (LSPosed 未加载时执行)                                │
│    ├─ zygiskd daemon → 重注入 ZygiskSU 到当前 zygote              │
│    ├─ setsid lspd → 守护化启动 LSPosed 守护进程                   │
│    ├─ kill zygote64 → 触发带 ZygiskSU 注入的新 zygote             │
│    └─ 等待 bridge binder → 确认 LSPosed 框架加载成功              │
└──────────────────────────────────────────────────────────────────┘

┌─ 设备端 ─────────────────────────────────────┐
│  miui.mqsas.IMQSNative service call 21       │
│    → 以 root (uid=0) 执行任意 shell 脚本      │
│    → SELinux context: hypsys_ssi_default       │
│                                               │
│  KernelSU (LKM)                               │
│    → insmod kernelsu_patched.ko               │
│    → ksud post-fs-data / services / boot      │
│                                               │
│  ZygiskSU (Zygisk Next v1.3.2)               │
│    → zygiskd daemon 注入 zygote64             │
│    → libzygisk.so 加载到 zygote 进程           │
│    → 注意: 不使用 native_bridge 属性方式       │
│                                               │
│  LSPosed                                      │
│    → lspd (app_process) 守护进程               │
│    → framework.dex 注入 system_server          │
│    → Bridge binder 连接模块与服务              │
└───────────────────────────────────────────────┘
```

## 关键技术点

- **mqsas root 调用格式**: `service call miui.mqsas.IMQSNative 21 i32 1 s16 '解释器' i32 1 s16 '脚本路径' s16 '输出文件' i32 超时秒数`
  - 执行方式为**异步** — 需等待完成后拉取输出文件查看结果
  - 输出文件权限为 root:system 600，需用 `do_chmod.sh` 修复后才能 adb pull
- **KASLR**: 每次开机内核符号地址随机化，必须实时拉取 kallsyms 重新补丁
- **SELinux**: 需已设为 permissive (`u:r:hypsys_ssi_default:s0` 上下文)
- **Mount Namespace**: lspd 需要 `nsenter -t 1 -m` 进入 init 的 namespace 才能访问 APEX
- **Magisk 误检测**: ksu_step2.sh 会删除 ksud 自动创建的 `$KSU_DIR/bin/magisk` 兼容符号链接，否则 Manager 的 `hasMagisk()` 会误报冲突导致所有模块不可用
- **lspd 存活**: 必须使用 `setsid` 守护化，否则 mqsas 脚本退出时 lspd 被 SIGHUP 杀死
- **ZygiskSU 注入机制**: v1.3.2 通过 `zygiskd daemon` 直接注入，**不使用** `ro.dalvik.vm.native_bridge` 属性，`service check` 对 bridge 始终返回 "not found"（正常行为）
- **竞态条件**: 杀 zygote 后必须等旧 system_server 死亡，再查找新 PID，否则会与正在死亡的旧进程建立 bridge
- **ZygiskSU 注入丢失**: 杀 zygote 后新 zygote 没有 ZygiskSU 注入 → 必须在杀之前先调用 `zygiskd daemon` 重新注入
- **monitor 文件路径**: `/data/adb/lspd/monitor`（不是 `/data/adb/lspd/config/monitor`）

## 注意事项

- ⚠️ 每次**重启手机**后需要重新运行 `ksu_oneclick.bat`，然后按需运行 `fix_lspd.sh`
- ⚠️ 本方案仅在 SELinux permissive 下测试
- ⚠️ mqsas 漏洞可能在后续系统更新中被修复
- ⚠️ 勿在生产环境使用，仅用于安全研究用途
