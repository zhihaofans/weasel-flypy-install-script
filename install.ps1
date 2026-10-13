# ===========================================================================
#  Online bootstrap launcher for the Rime installer.
# ---------------------------------------------------------------------------
#  Why this file exists:
#    The main script (install-rime-cn.ps1) calls exit in several places, and
#    its self-elevation relies on $PSCommandPath. If you ran it directly via
#    `irm .../install-rime-cn.ps1 | iex`:
#      - exit would close the user's own PowerShell window, hiding any error;
#      - $PSCommandPath is empty under iex, so the script cannot relaunch
#        itself elevated.
#    So this launcher only does three things: download -> save to a temp file
#    -> start it with -File in a child process. The child is a separate
#    PowerShell, so its exit only ends itself and your window stays open.
#
#  IMPORTANT - this file MUST stay pure ASCII and BOM-free:
#    It is executed via `irm ... | iex`. In Windows PowerShell 5.1, iwr/irm
#    decodes a response without a declared charset using the system ANSI code
#    page (GBK on Chinese systems). Any non-ASCII character here - even in a
#    comment - would be mangled, and a UTF-8 BOM would even become an illegal
#    character at the very start of the line and break parsing. Keep ASCII.
#    (The main scripts are run with -File from a real file, so they can - and
#    do - use UTF-8 with BOM for proper Chinese text.)
#
#  Online usage (CN mirror, recommended):
#    irm https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/install.ps1 | iex
#
#  Online usage (GitHub official source):
#    irm https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/install.ps1 -OutFile $env:TEMP\i.ps1
#    & $env:TEMP\i.ps1 -Source github
#
#  You can also download this file and run it locally; arguments are the same.
# ===========================================================================
[CmdletBinding()]
param(
    # Which installer to fetch: cn = CN mirrors first (default); github = official
    [ValidateSet('cn', 'github')]
    [string]$Source = 'cn',

    # Passed through to the main script (optional)
    [string]$RimeDir,
    [int]$PageSize = 9,
    [switch]$SkipInstall,
    [switch]$KeepDownload
)

$ErrorActionPreference = 'Stop'

# Append TLS 1.2 without overwriting existing protocols
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
Write-Host '  Rime Weasel + rime-ice online installer (bootstrap)' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor DarkCyan

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Write-Line 'This script only supports Windows.' 'Red'
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Decide which main script to fetch and the candidate mirrors
# ---------------------------------------------------------------------------
$scriptName = if ($Source -eq 'cn') { 'install-rime-cn.ps1' } else { 'install-rime.ps1' }

# Source order: measured from mainland CN, raw.githubusercontent.com often times
# out entirely (25s+) or gets reset mid-transfer ("the remote host closed an
# existing connection"), so it is NOT tried first. The CDN and the two proxies
# all answered in under 1s, so they come first and the official host is kept as
# a last resort for users outside CN.
# jsDelivr serves a cached copy of @master, so every download below is validated
# (size, markers, BOM) before being accepted; a stale copy is rejected and the
# next source is tried.
$baseUrls = @(
    "https://cdn.jsdelivr.net/gh/zhihaofans/weasel-flypy-install-script@master/$scriptName",
    "https://gh-proxy.com/https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName",
    "https://ghproxy.net/https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName",
    "https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName"
)

# ---------------------------------------------------------------------------
# 2. Download the main script to a temp file (must be a real file for -File)
# ---------------------------------------------------------------------------
$tmp = Join-Path $env:TEMP ("rime-bootstrap-" + [Guid]::NewGuid().ToString('N') + ".ps1")

Write-Line "Script    : $scriptName ($Source)"
Write-Line "Temp file : $tmp"

$ProgressPreference = 'SilentlyContinue'
$ok = $false
$lastErr = $null
for ($i = 0; $i -lt $baseUrls.Count; $i++) {
    $url = $baseUrls[$i]
    Write-Line "Download [$($i + 1)/$($baseUrls.Count)]: $url" 'DarkGray'
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    } catch {
        $lastErr = $_
        Write-Line "This mirror failed, trying next: $($_.Exception.Message)" 'Yellow'
        continue
    }

    # Validate what we got before accepting it. A stale CDN copy or an error
    # page would otherwise be passed straight to -File and fail confusingly.
    $sb = [System.IO.File]::ReadAllBytes($tmp)
    if ($sb.Length -lt 1024) {
        Write-Line "Rejected: only $($sb.Length) bytes (looks like an error page)." 'Yellow'
        $lastErr = [Exception]::new("content too small")
        continue
    }
    # A genuine main script contains the ASCII markers below.
    $head = [System.Text.Encoding]::ASCII.GetString($sb, 0, [Math]::Min(4096, $sb.Length))
    if ($head -notmatch 'Rime' -and $head -notmatch 'SHA256') {
        Write-Line 'Rejected: content does not look like the installer script.' 'Yellow'
        $lastErr = [Exception]::new("unexpected content")
        continue
    }
    # Version guard: the current main scripts are saved as UTF-8 WITH a BOM, so
    # a BOM is a reliable "this is the current revision" signal. An ancient copy
    # (no BOM) would garble Chinese under -File, so reject it and try the next
    # source - this is what makes jsDelivr-first safe despite its @master cache.
    $bomOk = ($sb.Length -ge 3 -and $sb[0] -eq 0xEF -and $sb[1] -eq 0xBB -and $sb[2] -eq 0xBF)
    if (-not $bomOk) {
        Write-Line 'Rejected: stale copy without UTF-8 BOM (would garble Chinese).' 'Yellow'
        $lastErr = [Exception]::new("stale copy (no BOM)")
        continue
    }

    $ok = $true
    break
}
$ProgressPreference = 'Continue'

if (-not $ok) {
    Write-Host ''
    Write-Host '  [X] All download mirrors failed; cannot fetch the installer.' -ForegroundColor Red
    if ($lastErr) { Write-Line "Last error: $($lastErr.Exception.Message)" 'Red' }
    Write-Host ''
    Write-Line 'You can download it manually and run it locally:' 'White'
    Write-Line "  https://github.com/zhihaofans/weasel-flypy-install-script/blob/master/$scriptName" 'DarkGray'
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 1
}

$size = (Get-Item $tmp).Length

# ---------------------------------------------------------------------------
# 2.1 Make sure the main script carries a UTF-8 BOM.
#   Windows PowerShell 5.1 decodes a .ps1 WITHOUT a BOM using the system ANSI
#   code page (GBK on Chinese systems), which garbles all Chinese text and can
#   even break string boundaries and cause syntax errors. CDNs/proxies may drop
#   the BOM, so re-add it here as a safety net.
# ---------------------------------------------------------------------------
$bytes = $sb
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
if (-not $hasBom) {
    # Only add the BOM if the content really is valid UTF-8, to avoid
    # corrupting a non-UTF-8 file.
    $isUtf8 = $true
    try {
        $null = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    } catch {
        $isUtf8 = $false
    }
    if ($isUtf8) {
        # Allocate the target byte[] first and copy, avoiding the implicit
        # Object[] -> byte[] conversion issue with [byte[]](...) + $bytes.
        $out = New-Object byte[] ($bytes.Length + 3)
        $out[0] = 0xEF; $out[1] = 0xBB; $out[2] = 0xBF
        [Array]::Copy($bytes, 0, $out, 3, $bytes.Length)
        [System.IO.File]::WriteAllBytes($tmp, $out)
        Write-Line 'Added UTF-8 BOM (prevents garbled Chinese text).' 'DarkGray'
    } else {
        Write-Line 'Warning: downloaded content is not UTF-8; Chinese may display wrong.' 'Yellow'
    }
} else {
    Write-Line 'UTF-8 BOM present; encoding is fine.' 'DarkGray'
}

# Final check: with the BOM in place, PowerShell will read this file as UTF-8.
# Decode it here the same way and confirm the Chinese strings resolve, so we
# catch a corrupted download before handing it to the child process.
# The Chinese markers are built from bytes on purpose - this file must stay
# pure ASCII (see the note at the top), so no literal Chinese is allowed here.
try {
    $mk1 = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0xB0,0x8F,0xE7,0x8B,0xBC,0xE6,0xAF,0xAB)) # "xiao lang hao"
    $mk2 = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE9,0x9B,0xBE,0xE5,0x87,0x87,0xE6,0x8B,0xBC,0xE9,0x9F,0xB3)) # "wu song pin yin"
    $finalBytes = [System.IO.File]::ReadAllBytes($tmp)
    $finalText  = [System.Text.Encoding]::UTF8.GetString($finalBytes)
    if ($finalBytes.Length -ge 3) { $finalText = $finalText.TrimStart([char]0xFEFF) }
    if ($finalText.Contains($mk1) -or $finalText.Contains($mk2)) {
        Write-Line 'Chinese text verified (main script will display correctly).' 'Green'
    } else {
        Write-Line 'Note: could not find expected Chinese markers; continuing anyway.' 'Yellow'
    }
} catch {
    Write-Line "Note: content check skipped ($($_.Exception.Message))." 'DarkGray'
}

Write-Line "Downloaded $([math]::Round($size / 1024, 1)) KB" 'Green'

# ---------------------------------------------------------------------------
# 3. Build arguments and start the child process with -File
# ---------------------------------------------------------------------------
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmp`"")
if ($RimeDir)      { $argList += @('-RimeDir', "`"$RimeDir`"") }
if ($PSBoundParameters.ContainsKey('PageSize')) { $argList += @('-PageSize', "$PageSize") }
if ($SkipInstall)  { $argList += '-SkipInstall' }
if ($KeepDownload) { $argList += '-KeepDownload' }

$exe = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path $exe)) { $exe = 'powershell.exe' }

Write-Host ''
Write-Host '  Starting the installer in a separate process...' -ForegroundColor Cyan
Write-Host ''

# -Wait makes the launcher wait for the install to finish. The main script ends
# with "Press Enter to exit", so this window will not flash and vanish.
#
# Note: we deliberately do NOT redirect the child's output to a file. Doing so
# would hide everything from the console, and the main script's own progress
# messages are exactly what the user needs to see live on failure.
$p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru

# Clean up the temp script (the main script handles its own downloads itself)
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

if ($p.ExitCode -ne 0) {
    Write-Host "  [!] Installer process returned $($p.ExitCode); see output above." -ForegroundColor Yellow
    Write-Host ''
    Write-Line 'How to re-run with full output visible:' 'White'
    Write-Host '   1. Right-click PowerShell -> "Run as administrator"' -ForegroundColor Gray
    Write-Host '   2. Run the same one-line command again' -ForegroundColor Gray
    Write-Host '   Running as admin skips the elevation step, so the real error shows.' -ForegroundColor Gray
    Write-Host ''
    Write-Line 'Alternative: run the main script directly so you can read the log:' 'White'
    Write-Line "  irm https://raw.githubusercontent.com/zhihaofans/weasel-flypy-install-script/master/$scriptName -OutFile `$env:TEMP\rime.ps1" 'DarkGray'
    Write-Line '  powershell -ExecutionPolicy Bypass -File $env:TEMP\rime.ps1 -KeepDownload' 'DarkGray'
    Write-Host ''
    Read-Host 'Press Enter to exit'
} else {
    Write-Host '  [OK] Bootstrap done.' -ForegroundColor Green
}
