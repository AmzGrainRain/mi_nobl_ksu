# 免解锁 Bootloader Root 方案

原项目地址 [https://github.com/xunchahaha/mi_nobl_root](https://github.com/xunchahaha/mi_nobl_root)

此项目针对原项目中的 ksu 安装脚本进行了部分优化并添加了 magisk 的安装脚本，使用 powershell 脚本执行全部流程，且修补 ksu 不需要使用 python 环境。

## 详细信息

请参阅 [https://github.com/xunchahaha/mi_nobl_root](https://github.com/xunchahaha/mi_nobl_root)

## 使用步骤

手机处于开机状态时，进入 `root` 文件夹，双击执行 `run.ps1` 脚本，仔细根据提示获取 adb root 权限。

成功获得 adb root 权限后，进入 `ksu` 文件夹，双击执行 `run.ps1` 脚本，根据提示安装 ksu。

成功获得 adb root 权限后也可以进入 `magisk` 文件夹，双击执行 `run.ps1` 脚本，根据提示安装 magisk。

**magisk 与 ksu 建议二选一，不要同时安装。**

**如果非要安装两个，请先安装 magisk 后再安装 ksu。**
