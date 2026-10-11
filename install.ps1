# ===========================================================================
#  在线引导脚本（bootstrap）—— 让主安装脚本可以「一行命令在线运行」
# ---------------------------------------------------------------------------
#  为什么需要这个文件？
#    主脚本 install-rime-cn.ps1 里有多处 exit 调用，并且自提权依赖
#    $PSCommandPath。如果直接用 `irm .../install-rime-cn.ps1 | iex`：
#      - exit 会把用户正在用的 PowerShell 窗口直接关掉，出错也看不到提示；
#      - $PSCommandPath 在 iex 下为空，脚本无法以管理员身份重新拉起自己。
#    所以本引导器只做三件事：下载 -> 落盘 -> 用 -File 启动子进程。
#    子进程是独立的 PowerShell，exit 只结束它自己，用户窗口保留。
#
#  在线用法（国内镜像版，推荐）：
#    irm https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/install.ps1 | iex
#
#  在线用法（GitHub 官方源版）：
#    irm https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/install.ps1 -OutFile $env:TEMP\i.ps1
#    & $env:TEMP\i.ps1 -Source github
#
#  也可下载本文件后本地运行，参数同上。
# ===========================================================================
[CmdletBinding()]
param(
    # 选择安装哪个版本：cn = 国内镜像优先（默认）；github = GitHub 官方源
    [ValidateSet('cn', 'github')]
    [string]$Source = 'cn',

    # 透传给主脚本的参数（可选）
    [string]$RimeDir,
    [int]$PageSize = 9,
    [switch]$SkipInstall,
    [switch]$KeepDownload
)

$ErrorActionPreference = 'Stop'

# 追加 TLS 1.2（不覆盖已有协议）
try {
    $cur = [Net.ServicePointManager]::SecurityProtocol
    if (-not ($cur -band [Net.SecurityProtocolType]::Tls12)) {
        [Net.ServicePointManager]::SecurityProtocol = $cur -bor [Net.SecurityProtocolType]::Tls12
    }
} catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Write-Line($m, $c = 'Gray') { Write-Host "   $m" -ForegroundColor $c }

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor DarkCyan
Write-Host '  Rime 小狼毫 + 雾凇拼音 在线安装（引导器）' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor DarkCyan

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Write-Line '本脚本仅支持 Windows。' 'Red'
    exit 1
}

# ---------------------------------------------------------------------------
# 1. 确定要下载的主脚本文件名与多个候选地址
# ---------------------------------------------------------------------------
$scriptName = if ($Source -eq 'cn') { 'install-rime-cn.ps1' } else { 'install-rime.ps1' }

# raw.githubusercontent.com 在国内常被墙，jsDelivr CDN 作为第一优先备用
$baseUrls = @(
    "https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/$scriptName",
    "https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName",
    "https://ghproxy.net/https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName"
)

# ---------------------------------------------------------------------------
# 2. 下载主脚本到临时文件（关键：落盘后才能用 -File 启动）
# ---------------------------------------------------------------------------
$tmp = Join-Path $env:TEMP ("rime-bootstrap-" + [Guid]::NewGuid().ToString('N') + ".ps1")

Write-Line "版本      : $ScriptName ($Source)"
Write-Line "临时文件  : $tmp"

$ProgressPreference = 'SilentlyContinue'
$ok = $false
$lastErr = $null
for ($i = 0; $i -lt $baseUrls.Count; $i++) {
    $url = $baseUrls[$i]
    Write-Line "下载 [$($i + 1)/$($baseUrls.Count)]: $url" 'DarkGray'
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
        $ok = $true
        break
    } catch {
        $lastErr = $_
        Write-Line "此源失败，换下一个：$($_.Exception.Message)" 'Yellow'
    }
}
$ProgressPreference = 'Continue'

if (-not $ok) {
    Write-Host ''
    Write-Host '  [X] 所有下载源均失败，无法获取安装脚本。' -ForegroundColor Red
    Write-Line "最后一个错误：$($lastErr.Exception.Message)" 'Red'
    Write-Host ''
    Write-Line '可手动下载后本地运行：' 'White'
    Write-Line "  https://github.com/zhihaofans/weasel-flypy-install-script/blob/master/$scriptName" 'DarkGray'
    Write-Host ''
    Read-Host '按回车键退出'
    exit 1
}

# 简单完整性判断：PowerShell 脚本应为文本且含特征串，避免下到错误页
$size = (Get-Item $tmp).Length
if ($size -lt 1024) {
    Write-Host "  [X] 下载内容异常（仅 $size 字节），可能被网络拦截。" -ForegroundColor Red
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Read-Host '按回车键退出'
    exit 1
}
Write-Line "已下载 $([math]::Round($size / 1024, 1)) KB" 'Green'

# ---------------------------------------------------------------------------
# 3. 组装参数，用 -File 启动独立子进程
# ---------------------------------------------------------------------------
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmp`"")
if ($RimeDir)      { $argList += @('-RimeDir', "`"$RimeDir`"") }
if ($PSBoundParameters.ContainsKey('PageSize')) { $argList += @('-PageSize', "$PageSize") }
if ($SkipInstall)  { $argList += '-SkipInstall' }
if ($KeepDownload) { $argList += '-KeepDownload' }

$exe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path $exe)) { $exe = 'powershell.exe' }

Write-Host ''
Write-Host '  正在启动安装程序（独立窗口/子进程）...' -ForegroundColor Cyan
Write-Host ''

# -Wait 让引导器等安装结束；主脚本结尾自带「按回车退出」，所以此窗口不会一闪而过
$p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru

# 清理临时脚本（主脚本的下载缓存由它自己按 -KeepDownload 处理）
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

if ($p.ExitCode -ne 0) {
    Write-Host "  [!] 安装进程返回码 $($p.ExitCode)，请查看上方输出。" -ForegroundColor Yellow
    Read-Host '按回车键退出'
} else {
    Write-Host '  [OK] 引导完成。' -ForegroundColor Green
}
