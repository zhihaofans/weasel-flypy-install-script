<#
.SYNOPSIS
    一键安装 Rime 小狼毫输入法 + 雾凇拼音方案，并切换到小鹤双拼。

.DESCRIPTION
    专为「新 Windows 10/11 电脑」设计，零前置依赖：
      - 只用系统自带组件（PowerShell 5.1 / Invoke-WebRequest / Expand-Archive / tar.exe）
      - 不需要安装 Scoop、Git、7-Zip 或任何其他工具
      - 联网下载全部来自 GitHub release 正式版，带 SHA256 校验

    执行流程：
      1. 检查系统与权限
      2. 下载小狼毫安装器（weasel 0.17.4）
      3. 静默安装（自动提权）
      4. 下载雾凇拼音方案（rime-ice 2026.06.30）
      5. 部署到 %APPDATA%\Rime，并写入小鹤双拼为首选方案
      6. 触发小狼毫重新部署

    用法（任选其一）：
      # 方式 A：右键本文件 -> 使用 PowerShell 运行
      # 方式 B：命令行
      powershell -ExecutionPolicy Bypass -File .\install-rime.ps1

.PARAMETER RimeDir
    配置目录，默认 %APPDATA%\Rime。一般无需指定。

.PARAMETER PageSize
    候选词个数，默认 9。

.PARAMETER SkipInstall
    跳过小狼毫安装（仅重装方案），适合已装好输入法、只想更新方案的场景。

.PARAMETER KeepDownload
    保留下载的临时文件（便于排查）；默认下载完自动清理。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-rime.ps1
.EXAMPLE
    # 只更新方案，不重装输入法
    powershell -ExecutionPolicy Bypass -File .\install-rime.ps1 -SkipInstall
#>
[CmdletBinding()]
param(
    [string]$RimeDir,
    [int]$PageSize = 9,
    [switch]$SkipInstall,
    [switch]$KeepDownload
)

# ===========================================================================
# 配置区：版本锁定（改这里即可升级）
# ===========================================================================
# 【与国内镜像版同步更新说明】
#   本文件与 install-rime-cn.ps1 除「下载源」外完全一致。
#   上游发新版时，只需改这里的 *Version 与 *Sha256（两个文件都要改）：
#     - *Version  : 改成新的 release tag
#     - *Sha256   : 从 release 页或 GitHub API 的 digest 字段取
# ---------------------------------------------------------------------------
# 每个包可配多个下载源，脚本按顺序尝试，任一成功即用；全部失败才报错。
# 主源在前的为优先源。镜像与官方源的文件字节一致，故共用同一 SHA256。
$WeaselVersion = '0.17.4'
$WeaselSha256  = 'cf509534a8f5f8af9c98ed7cbb8f135439f145a8cbe7e50ede42bb5b5ab45c29'
$WeaselUrls    = @(
    "https://github.com/rime/weasel/releases/download/$WeaselVersion/weasel-$WeaselVersion.0-installer.exe"
)

$IceVersion    = '2026.06.30'
$IceSha256     = '675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac'
$IceUrls       = @(
    "https://github.com/iDvel/rime-ice/releases/download/$IceVersion/full.zip"
)

# 首选方案：小鹤双拼
$PrimarySchema = 'double_pinyin_flypy'
$FallbackSchema = 'rime_ice'

# ===========================================================================
# 基础工具
# ===========================================================================
$ErrorActionPreference = 'Stop'
# 追加 TLS 1.2（不覆盖已有协议），确保能访问 GitHub
try {
    $cur = [Net.ServicePointManager]::SecurityProtocol
    if (-not ($cur -band [Net.SecurityProtocolType]::Tls12)) {
        [Net.ServicePointManager]::SecurityProtocol = $cur -bor [Net.SecurityProtocolType]::Tls12
    }
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Write-Title($m) {
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
    Write-Host "  $m" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkCyan
}
function Write-Step($m) { Write-Host "`n>> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Write-Info($m) { Write-Host "   $m" -ForegroundColor Gray }
function Write-Warn2($m){ Write-Host "   [!] $m" -ForegroundColor Yellow }
function Write-Fail($m) { Write-Host "   [X] $m" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 自提权：小狼毫安装需要管理员权限
function Invoke-Elevated {
    param([string[]]$Arguments)
    # 用当前 PowerShell 主机的可执行文件，保证在 Win10 自带 5.1 上也能提权
    $exe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path $exe)) { $exe = 'powershell.exe' }
    Write-Host '正在请求管理员权限...' -ForegroundColor Yellow
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList $Arguments -Wait
}

function Get-Sha256($path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

function Save-File($urls, $dest) {
    # 依次尝试多个源，任一成功即返回；全部失败才抛错
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # 用 IWR 下载大文件时进度条极慢
    try {
        $lastErr = $null
        for ($i = 0; $i -lt $urls.Count; $i++) {
            $url = $urls[$i]
            $tag = if ($urls.Count -gt 1) { " [$($i + 1)/$($urls.Count)]" } else { '' }
            Write-Info "下载$tag`: $url"
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 1800
                return
            }
            catch {
                $lastErr = $_
                if ($i -lt $urls.Count - 1) {
                    Write-Warn2 "此源失败，尝试下一个：$($_.Exception.Message)"
                }
            }
        }
        throw "所有下载源均失败。最后一个错误：$($lastErr.Exception.Message)"
    }
    finally {
        $ProgressPreference = $old
    }
}

function Expand-Zip($zip, $dest) {
    # 优先用系统自带 tar.exe（Win10 1803+，比 Expand-Archive 快很多）
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        & $tar -xf $zip -C $dest
        if ($LASTEXITCODE -eq 0) { return }
        Write-Warn2 'tar 解压失败，回退 Expand-Archive。'
    }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
}

# ===========================================================================
# 0. 环境检查
# ===========================================================================
Write-Title 'Rime 小狼毫 + 雾凇拼音 一键安装'

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Write-Fail '本脚本仅支持 Windows。'; exit 1
}
$osDesc = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { "Windows $([Environment]::OSVersion.Version)" }
Write-Info "系统: $osDesc  ($env:PROCESSOR_ARCHITECTURE)"
Write-Info "PowerShell: $($PSVersionTable.PSVersion)"

$isAdmin = Test-Admin
Write-Info "管理员权限: $(if ($isAdmin) { '是' } else { '否' })"

# 若需要安装小狼毫但无管理员权限 -> 自提权重启
if (-not $SkipInstall -and -not $isAdmin) {
    $self = $PSCommandPath
    if (-not $self -or -not (Test-Path $self)) {
        Write-Fail '无法定位脚本自身路径，请用 -File 方式运行本脚本。'
        Write-Info '示例: powershell -ExecutionPolicy Bypass -File .\install-rime.ps1'
        exit 1
    }
    Write-Warn2 '安装小狼毫需要管理员权限，即将以管理员身份重新运行本脚本...'
    # 参数逐个用引号包裹，避免含空格的路径被拆开
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"")
    if ($RimeDir) { $argList += @('-RimeDir', "`"$RimeDir`"") }
    if ($PageSize) { $argList += @('-PageSize', "$PageSize") }
    if ($KeepDownload) { $argList += '-KeepDownload' }
    Invoke-Elevated -Arguments $argList
    exit 0
}

# 配置目录：优先参数 > 注册表 > 默认
if (-not $RimeDir) {
    foreach ($reg in @('HKCU:\Software\Rime\Weasel', 'HKLM:\Software\Rime\Weasel',
                       'HKLM:\Software\WOW6432Node\Rime\Weasel')) {
        try {
            $v = (Get-ItemProperty -Path $reg -Name 'RimeUserDir' -ErrorAction Stop).RimeUserDir
            if ($v) { $RimeDir = $v; break }
        } catch { }
    }
    if (-not $RimeDir) { $RimeDir = Join-Path $env:APPDATA 'Rime' }
}
Write-Info "配置目录: $RimeDir"

# 工作目录
$work = Join-Path $env:TEMP ('rime-setup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Info "临时目录: $work"

# ===========================================================================
# 1. 安装小狼毫
# ===========================================================================
if (-not $SkipInstall) {
    Write-Step "第 1 步 / 3：安装小狼毫 Weasel $WeaselVersion"

    $exe = Join-Path $work 'weasel-installer.exe'
    Save-File $WeaselUrls $exe

    Write-Info '校验 SHA256 ...'
    $got = Get-Sha256 $exe
    if ($got -ne $WeaselSha256) {
        Write-Fail "校验失败！`n     期望: $WeaselSha256`n     实际: $got"
        exit 1
    }
    Write-Ok 'SHA256 校验通过。'

    # NSIS 静默安装（/S）。不传 /D，装到系统默认位置，保证输入法正常注册。
    Write-Info '静默安装中（可能需要 1-2 分钟，请勿关闭窗口）...'
    $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Warn2 "安装器返回码 $($p.ExitCode)，继续尝试部署方案。"
    } else {
        Write-Ok '小狼毫安装完成。'
    }
    Start-Sleep -Seconds 2
}
else {
    Write-Step '第 1 步 / 3：跳过小狼毫安装（-SkipInstall）'
}

# ===========================================================================
# 2. 下载并部署雾凇拼音方案
# ===========================================================================
Write-Step "第 2 步 / 3：部署雾凇拼音 rime-ice $IceVersion"

New-Item -ItemType Directory -Force -Path $RimeDir | Out-Null

# 2.1 备份用户已有的自定义配置与词典
$backupDir = Join-Path $RimeDir ('_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$toBackup = @()
$toBackup += Get-ChildItem -Path $RimeDir -Filter '*.custom.yaml' -File -ErrorAction SilentlyContinue
foreach ($d in @('userdb', 'sync')) {
    $pd = Join-Path $RimeDir $d
    if (Test-Path $pd) { $toBackup += Get-Item $pd }
}
if ($toBackup.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    foreach ($t in $toBackup) {
        try {
            Copy-Item -Path $t.FullName -Destination $backupDir -Recurse -Force -ErrorAction Stop
        }
        catch {
            # userdb 可能被运行中的输入法占用，跳过而不中断
            Write-Warn2 "跳过（可能被占用）: $($t.Name) - $($_.Exception.Message)"
        }
    }
    Write-Ok "已备份 $($toBackup.Count) 项既有配置 -> $backupDir"

    # 只保留最近 3 份备份，避免重复运行时无限累积
    $oldBackups = Get-ChildItem -Path $RimeDir -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending | Select-Object -Skip 3
    if ($oldBackups) {
        foreach ($ob in $oldBackups) {
            Remove-Item -Path $ob.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Info "已清理 $($oldBackups.Count) 份过期备份（保留最近 3 份）。"
    }
} else {
    Write-Info '无既有自定义配置，全新部署。'
}

# 2.2 下载方案包
$zip = Join-Path $work 'rime-ice.zip'
Save-File $IceUrls $zip
Write-Info '校验 SHA256 ...'
$got = Get-Sha256 $zip
if ($got -ne $IceSha256) {
    Write-Fail "校验失败！`n     期望: $IceSha256`n     实际: $got"
    exit 1
}
Write-Ok 'SHA256 校验通过。'

# 2.3 解压（full.zip 为扁平结构，无外层目录）
Write-Info '解压方案包 ...'
$extract = Join-Path $work 'ice'
New-Item -ItemType Directory -Force -Path $extract | Out-Null
Expand-Zip $zip $extract

# 兼容处理：万一有外层目录，探测真正的方案根
$root = $extract
if (-not (Test-Path (Join-Path $extract 'default.yaml'))) {
    $hit = Get-ChildItem -Path $extract -Recurse -Filter 'default.yaml' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\build\\' } | Select-Object -First 1
    if ($hit) { $root = $hit.Directory.FullName }
}
if (-not (Test-Path (Join-Path $root 'default.yaml'))) {
    Write-Fail '解压后未找到 default.yaml，方案包结构异常。'; exit 1
}
Write-Ok "方案根目录: $root"

# 2.4 拷贝到配置目录（跳过 VCS / CI / 缓存目录）
$excludeDirs = @('.git', '.github', 'build', 'others', 'legacy')
foreach ($item in (Get-ChildItem -Path $root -Force)) {
    if ($item.PSIsContainer) {
        if ($excludeDirs -contains $item.Name) { continue }
        $dst = Join-Path $RimeDir $item.Name
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
        Copy-Item -Path $item.FullName -Destination $RimeDir -Recurse -Force
    } else {
        Copy-Item -Path $item.FullName -Destination $RimeDir -Force
    }
}
Write-Ok '方案文件已部署。'

# 2.5 写入 default.custom.yaml（切换小鹤双拼）
$defaultCustom = @"
# 由 install-rime.ps1 自动生成
# 可自由修改；重跑脚本前会自动备份。
patch:
  schema_list:
    - schema: $PrimarySchema    # 小鹤双拼（首选）
    - schema: $FallbackSchema    # 雾凇拼音·全拼（备选）
  menu:
    page_size: $PageSize
  ascii_composer:
    switch_key:
      Shift_L: commit_code
      Shift_R: inline_ascii
      Control_L: noop
      Control_R: noop
      Caps_Lock: clear
      Eisu_toggle: clear
"@
$defaultCustom | Set-Content -Path (Join-Path $RimeDir 'default.custom.yaml') -Encoding UTF8
Write-Ok 'default.custom.yaml 已写入（首选小鹤双拼）。'

# 2.6 小鹤双拼个人补丁（不存在才写，避免覆盖用户改动）
$flypyPath = Join-Path $RimeDir "$PrimarySchema.custom.yaml"
if (Test-Path $flypyPath) {
    Write-Info "$PrimarySchema.custom.yaml 已存在，保留你的配置。"
} else {
    @"
# 由 install-rime.ps1 自动生成，小鹤双拼个人偏好（可增删）
patch:
  menu/page_size: $PageSize
"@ | Set-Content -Path $flypyPath -Encoding UTF8
    Write-Ok "$PrimarySchema.custom.yaml 已写入。"
}

# ===========================================================================
# 3. 触发小狼毫重新部署
# ===========================================================================
Write-Step '第 3 步 / 3：重新部署小狼毫'

# 优先在固定位置找（小狼毫默认装到 %ProgramFiles%\Rime\weasel-*），避免全盘搜索
$deployer = $null
foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if (-not $base) { continue }
    $rimeRoot = Join-Path $base 'Rime'
    if (-not (Test-Path $rimeRoot)) { continue }
    $deployer = Get-ChildItem -Path $rimeRoot -Filter 'WeaselDeployer.exe' -Recurse `
                -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($deployer) { break }
}

if ($deployer) {
    Write-Info "调用: $($deployer.FullName) /deploy"
    Start-Process -FilePath $deployer.FullName -ArgumentList '/deploy' -Wait
    Write-Ok '已触发重新部署。'
} else {
    Write-Warn2 '未找到 WeaselDeployer.exe，请手动：右键任务栏『小狼毫』图标 -> 重新部署。'
}

# ===========================================================================
# 清理 & 收尾
# ===========================================================================
if ($KeepDownload) {
    Write-Info "已保留下载文件: $work"
} else {
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Title '全部完成！'
Write-Host "  输入法   :  Rime 小狼毫" -ForegroundColor Green
Write-Host "  输入方案 :  小鹤双拼（$PrimarySchema）" -ForegroundColor Green
Write-Host "  配置目录 :  $RimeDir" -ForegroundColor Green
Write-Host ''
Write-Host '  切换方案  :  F4  或  Ctrl+`' -ForegroundColor White
Write-Host '  重新部署  :  右键任务栏『小狼毫』图标 -> 重新部署' -ForegroundColor White
Write-Host ''
Write-Warn2 '若任务栏暂无小狼毫图标：注销或重启一次，或运行 WeaselSetup.exe 注册输入法。'
Write-Host ''
Read-Host '按回车键退出'
