#!/usr/bin/env pwsh
<#
.SYNOPSIS
修补 KernelSU 内核模块的未定义符号，模拟 ksuinit 的 load_module() 逻辑。

.DESCRIPTION
从 kallsyms.txt 读取内核符号地址，修补 .ko 文件中 SHN_UNDEF 的符号为 SHN_ABS + 真实地址，
输出修补后的 .ko 文件。

.PARAMETER KoFile
要修补的 KernelSU 内核模块文件（.ko）

.PARAMETER KallsymsFile
包含内核符号地址的 kallsyms.txt 文件

.PARAMETER OutputFile
修补后输出的 .ko 文件路径

.EXAMPLE
.\patch_ksu_module.ps1 android15-6.6_kernelsu.ko kallsyms.txt kernelsu_patched.ko
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$KoFile,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$KallsymsFile,

    [Parameter(Mandatory=$true, Position=2)]
    [string]$OutputFile
)

# 常量定义
Set-Variable -Name SHN_UNDEF -Option Constant -Value 0
Set-Variable -Name SHN_ABS   -Option Constant -Value 0xFFF1
Set-Variable -Name SHT_SYMTAB -Option Constant -Value 2
Set-Variable -Name SHT_STRTAB -Option Constant -Value 3
Set-Variable -Name SYM64_SIZE -Option Constant -Value 24

# 解析 kallsyms 文件，返回哈希表 {符号名: 地址}
function Parse-Kallsyms {
    param([string]$FilePath)

    $symbols = @{}
    Get-Content -Path $FilePath -Encoding utf8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '') { return }

        $parts = $line -split '\s+'
        if ($parts.Count -lt 3) { return }

        # 解析地址（十六进制）
        try {
            $addr = [Convert]::ToUInt64($parts[0], 16)
        } catch {
            return
        }

        $name = $parts[2]

        # 跳过模块名后缀，例如 [module]
        if ($name -match '^\[.*\]$') { return }

        # 去除 $ 或 .llvm. 后缀
        if ($name.IndexOf('$') -ge 0) {
            $name = $name.Substring(0, $name.IndexOf('$'))
        } elseif ($name.IndexOf('.llvm.') -ge 0) {
            $name = $name.Substring(0, $name.IndexOf('.llvm.'))
        }

        # 只保留第一次出现的符号（如果地址非零，Python 代码也保留了第一个）
        if (-not $symbols.ContainsKey($name)) {
            $symbols[$name] = $addr
        }
    }
    return $symbols
}

# 从 ELF 字节数组中读取以 null 结尾的字符串
function Read-String {
    param([byte[]]$Data, [int]$Offset)

    $end = $Offset
    while ($end -lt $Data.Length -and $Data[$end] -ne 0) {
        $end++
    }
    if ($end -eq $Offset) { return '' }
    return [System.Text.Encoding]::ASCII.GetString($Data, $Offset, $end - $Offset)
}

# 修补模块主函数
function Patch-Module {
    param(
        [string]$KoPath,
        [hashtable]$Kallsyms,
        [string]$OutputPath
    )

    # 读取整个 .ko 文件到字节数组
    $data = [System.IO.File]::ReadAllBytes($KoPath)

    # 检查 ELF 魔数
    if ($data[0] -ne 0x7F -or $data[1] -ne 0x45 -or $data[2] -ne 0x4C -or $data[3] -ne 0x46) {
        Write-Error "错误：文件不是有效的 ELF 格式"
        return $false
    }

    # 检查 64 位
    if ($data[4] -ne 2) {
        Write-Error "错误：不是 64 位 ELF"
        return $false
    }

    # 检查小端序
    if ($data[5] -ne 1) {
        Write-Error "错误：不是小端 ELF（ARM64 应该是小端）"
        return $false
    }

    # 解析 ELF64 头（固定偏移）
    $e_shoff    = [System.BitConverter]::ToUInt64($data, 40)
    $e_shentsize= [System.BitConverter]::ToUInt16($data, 58)
    $e_shnum    = [System.BitConverter]::ToUInt16($data, 60)
    $e_shstrndx = [System.BitConverter]::ToUInt16($data, 62)

    Write-Host "ELF64: $e_shnum 个节头, 节头偏移 0x$($e_shoff.ToString('x'))"

    # 解析所有节头
    $sections = @()
    for ($i = 0; $i -lt $e_shnum; $i++) {
        $offset = $e_shoff + $i * $e_shentsize
        # 节头结构（64 字节）
        $sh_name      = [System.BitConverter]::ToUInt32($data, $offset)
        $sh_type      = [System.BitConverter]::ToUInt32($data, $offset + 4)
        $sh_flags     = [System.BitConverter]::ToUInt64($data, $offset + 8)
        $sh_addr      = [System.BitConverter]::ToUInt64($data, $offset + 16)
        $sh_offset    = [System.BitConverter]::ToUInt64($data, $offset + 24)
        $sh_size      = [System.BitConverter]::ToUInt64($data, $offset + 32)
        $sh_link      = [System.BitConverter]::ToUInt32($data, $offset + 40)
        $sh_info      = [System.BitConverter]::ToUInt32($data, $offset + 44)
        $sh_addralign = [System.BitConverter]::ToUInt64($data, $offset + 48)
        $sh_entsize   = [System.BitConverter]::ToUInt64($data, $offset + 56)

        $sections += [PSCustomObject]@{
            Index        = $i
            sh_name      = $sh_name
            sh_type      = $sh_type
            sh_flags     = $sh_flags
            sh_addr      = $sh_addr
            sh_offset    = $sh_offset
            sh_size      = $sh_size
            sh_link      = $sh_link
            sh_info      = $sh_info
            sh_addralign = $sh_addralign
            sh_entsize   = $sh_entsize
        }
    }

    # 获取节名字符串表基址
    $shstrtab = $sections[$e_shstrndx]
    $shstr_off = $shstrtab.sh_offset

    # 查找 .symtab 和 .strtab 节
    $symtab_idx = $null
    $strtab_idx = $null
    foreach ($sec in $sections) {
        $name = Read-String -Data $data -Offset ($shstr_off + $sec.sh_name)
        if ($name -eq '.symtab' -and $sec.sh_type -eq $SHT_SYMTAB) {
            $symtab_idx = $sec.Index
        }
        elseif ($name -eq '.strtab' -and $sec.sh_type -eq $SHT_STRTAB) {
            $strtab_idx = $sec.Index
        }
    }

    if ($null -eq $symtab_idx) {
        Write-Error "错误：找不到 .symtab 节"
        return $false
    }
    if ($null -eq $strtab_idx) {
        Write-Error "错误：找不到 .strtab 节"
        return $false
    }

    $symtab = $sections[$symtab_idx]
    $strtab = $sections[$strtab_idx]

    $num_syms = $symtab.sh_size / $SYM64_SIZE
    Write-Host ".symtab: $num_syms 个符号"
    Write-Host ".strtab 偏移: 0x$($strtab.sh_offset.ToString('x'))"
    Write-Host "kallsyms 共 $($Kallsyms.Count) 个符号"
    Write-Host ""

    $patched_count = 0
    $missing = @()

    for ($i = 1; $i -lt $num_syms; $i++) {  # 跳过索引 0 的空符号
        $sym_off = $symtab.sh_offset + $i * $SYM64_SIZE

        # 读取符号表项（24 字节）
        $st_name  = [System.BitConverter]::ToUInt32($data, $sym_off)
        $st_info  = $data[$sym_off + 4]
        $st_other = $data[$sym_off + 5]
        $st_shndx = [System.BitConverter]::ToUInt16($data, $sym_off + 6)
        $st_value = [System.BitConverter]::ToUInt64($data, $sym_off + 8)
        $st_size  = [System.BitConverter]::ToUInt64($data, $sym_off + 16)

        if ($st_shndx -ne $SHN_UNDEF) {
            continue
        }

        # 读取符号名
        $sym_name = Read-String -Data $data -Offset ($strtab.sh_offset + $st_name)
        if ([string]::IsNullOrEmpty($sym_name)) {
            continue
        }

        if ($Kallsyms.ContainsKey($sym_name)) {
            $real_addr = $Kallsyms[$sym_name]

            # 修补 st_shndx 为 SHN_ABS，st_value 为真实地址
            # 将新值转换为字节数组（小端序）
            $shndx_bytes = [System.BitConverter]::GetBytes([uint16]$SHN_ABS)
            $addr_bytes  = [System.BitConverter]::GetBytes([uint64]$real_addr)

            # 复制到原数组
            [System.Array]::Copy($shndx_bytes, 0, $data, $sym_off + 6, 2)
            [System.Array]::Copy($addr_bytes,  0, $data, $sym_off + 8, 8)

            $patched_count++
            Write-Host "  ✓ $sym_name -> 0x$($real_addr.ToString('x16'))"
        } else {
            $missing += $sym_name
            Write-Host "  ✗ 未找到: $sym_name"
        }
    }

    Write-Host "`n修补了 $patched_count 个符号"
    if ($missing.Count -gt 0) {
        Write-Host "未找到 $($missing.Count) 个符号: $($missing -join ', ')"
    }

    # 写出修补后的文件
    [System.IO.File]::WriteAllBytes($OutputPath, $data)
    Write-Host "`n修补后的模块已保存到: $OutputPath"

    return $true
}

# 主程序入口
function Main {
    if (-not (Test-Path $KoFile)) {
        Write-Error "错误：找不到 $KoFile"
        exit 1
    }
    if (-not (Test-Path $KallsymsFile)) {
        Write-Error "错误：找不到 $KallsymsFile"
        exit 1
    }

    Write-Host "读取内核符号: $KallsymsFile"
    $kallsyms = Parse-Kallsyms -FilePath $KallsymsFile
    Write-Host "加载了 $($kallsyms.Count) 个内核符号`n"

    Write-Host "修补模块: $KoFile"
    $success = Patch-Module -KoPath $KoFile -Kallsyms $kallsyms -OutputPath $OutputFile

    if (-not $success) {
        exit 1
    } else {
        exit 0
    }
}

# 执行主函数
Main