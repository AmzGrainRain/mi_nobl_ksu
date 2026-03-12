# 免解锁 Bootloader Root 方案

KernelSU 目前已经可以在 SELinux 宽容模式下直获取 Root 权限。

您可直接安装 KernelSU Manager，然后在其中一键获取 Root 权限（亦支持每次开机自动获取）。

关于实现细节可以查看 [KernelSU Pull Request #3268](https://github.com/tiann/KernelSU/pull/3268)

由于本项目利用的是 MIUI 的 `miui.mqsas.IMQSNative` 服务漏洞，本身仅适用于小米手机。而且在可预见的未来某一天，官方必定会修复此漏洞。所以不再推荐使用此项目（此项目目前仍然可用，具体请参考下面的使用方法）。

## 如何将 SELinux 设置为宽容模式

在 Fastboot 模式下，你可以通过以下命令将 SELinux 设置为宽容模式：

```sh
fastboot oem set-gpu-preemption 0 androidboot.selinux=permissive
fastboot reboot
```

## 使用方法

- 如果你不确定是否有 powershell7 环境，那么就先安装它，具体方法百度或问 AI
- 首次安装 powershell7 后，记得右键以管理员身份运行 `bypass.ps1` 脚本
- 在手机处于开机状态时，双击运行 `run.ps1` 脚本，根据提示操作
