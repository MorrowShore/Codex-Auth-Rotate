# ==============================================================================
# Rotate-Codex-Auth.ps1
#
# Cycles through ChatGPT Codex accounts by swapping auth.json.
#
# SETUP:
#   1. Place this script anywhere permanent, e.g. C:\Tools\CodexSwitch\
#   2. Create a subfolder called "accounts\" next to this script.
#   3. Copy your auth.json for each account into that folder, named:
#        accounts\01_Personal.json
#        accounts\02_CompanyA.json
#        accounts\03_CompanyB.json
#      (Files are cycled in alphabetical order, so the prefix controls order.)
# ==============================================================================

param(
    # Passed automatically when re-launching elevated — do not set manually.
    [string]$ScriptDir = ""
)

# ── RESOLVE SCRIPT DIR ─────────────────────────────────────────────────────────
# $PSScriptRoot is empty when launched via Start-Process, so we pass it as a
# parameter and fall back to $PSScriptRoot for non-elevated first runs.

if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    Write-Host "  [!] Could not determine script directory." -ForegroundColor Red
    Pause; exit 1
}

# ── AUTO-ELEVATE ───────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -ScriptDir `"$ScriptDir`"" -Verb RunAs
    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AuthFile    = "$env:USERPROFILE\.codex\auth.json"
$ConfigFile  = "$env:USERPROFILE\.codex\config.toml"
$AccountsDir = Join-Path $ScriptDir "accounts"
$StateFile   = Join-Path $ScriptDir ".auth_state"

Write-Host ""
Write-Host "  Script dir  : $ScriptDir"   -ForegroundColor DarkGray
Write-Host "  Accounts dir: $AccountsDir" -ForegroundColor DarkGray
Write-Host "  Auth file   : $AuthFile"    -ForegroundColor DarkGray
Write-Host ""

# ── ENSURE config.toml HAS cli_auth_credentials_store = "file" ────────────────

if (-not (Test-Path $ConfigFile)) {
    Write-Host "  [!] config.toml not found — creating it." -ForegroundColor Yellow
    New-Item -ItemType File -Path $ConfigFile -Force | Out-Null
}

$configContent = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
if (-not $configContent) { $configContent = "" }

if ($configContent -notmatch '(?m)^\s*cli_auth_credentials_store\s*=') {
    Write-Host "  [+] Adding cli_auth_credentials_store = `"file`" to config.toml" -ForegroundColor Cyan
    $configContent = $configContent.TrimEnd() + "`ncli_auth_credentials_store = `"file`"`n"
    Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8 -NoNewline
} else {
    if ($configContent -notmatch '(?m)^\s*cli_auth_credentials_store\s*=\s*"file"') {
        Write-Host "  [!] cli_auth_credentials_store is not `"file`" — fixing." -ForegroundColor Yellow
        $configContent = $configContent -replace '(?m)^(\s*cli_auth_credentials_store\s*=\s*).*$', '$1"file"'
        Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8 -NoNewline
    }
}

# ── LOAD ACCOUNT FILES ─────────────────────────────────────────────────────────

if (-not (Test-Path $AccountsDir)) {
    New-Item -ItemType Directory -Path $AccountsDir | Out-Null
    Write-Host "  [!] Created accounts\ folder at: $AccountsDir" -ForegroundColor Yellow
    Write-Host "      Add one .json file per account, e.g. 01_Personal.json" -ForegroundColor Yellow
    Write-Host ""
    Pause; exit 0
}

$accounts = @(Get-ChildItem -Path $AccountsDir -Filter "*.json" | Sort-Object Name)
if ($accounts.Count -eq 0) {
    Write-Host "  [!] No .json files found in: $AccountsDir" -ForegroundColor Red
    Write-Host "      Run .ps1 to add accounts." -ForegroundColor Red
    Write-Host ""
    Pause; exit 1
}

Write-Host "  Found $($accounts.Count) account(s):" -ForegroundColor DarkGray
foreach ($a in $accounts) { Write-Host "    $($a.Name)" -ForegroundColor DarkGray }
Write-Host ""

# ── SAVE CURRENT LIVE AUTH BACK INTO ITS ACCOUNT FILE ─────────────────────────

$currentIndex = -1
if (Test-Path $StateFile) {
    $stored = (Get-Content $StateFile -Raw).Trim()
    if ($stored -match '^\d+$') { $currentIndex = [int]$stored }
}

if ($currentIndex -ge 0 -and $currentIndex -lt $accounts.Count -and (Test-Path $AuthFile)) {
    $liveContent = Get-Content $AuthFile -Raw
    Set-Content -Path $accounts[$currentIndex].FullName -Value $liveContent -Encoding UTF8 -NoNewline
    Write-Host "  [~] Saved refreshed tokens for: $($accounts[$currentIndex].BaseName -replace '^\d+_','')" -ForegroundColor DarkGray
}

# ── DETERMINE NEXT ACCOUNT ─────────────────────────────────────────────────────

$nextIndex   = ($currentIndex + 1) % $accounts.Count
$nextAccount = $accounts[$nextIndex]

# ── BACK UP AND SWAP auth.json ─────────────────────────────────────────────────

if (Test-Path $AuthFile) {
    Copy-Item $AuthFile "$AuthFile.bak" -Force
}

$newContent = Get-Content $nextAccount.FullName -Raw
Set-Content -Path $AuthFile -Value $newContent -Encoding UTF8 -NoNewline

# ── SAVE STATE ─────────────────────────────────────────────────────────────────

Set-Content -Path $StateFile -Value $nextIndex -Encoding UTF8

# ── REPORT ─────────────────────────────────────────────────────────────────────

$friendlyId = $nextAccount.BaseName -replace '^\d+_', ''

try {
    $json    = $newContent | ConvertFrom-Json
    $idToken = $json.tokens.id_token
    if ($idToken) {
        $payload = $idToken.Split('.')[1]
        $pad = 4 - ($payload.Length % 4); if ($pad -ne 4) { $payload += '=' * $pad }
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $email   = ($decoded | ConvertFrom-Json).email
        if ($email) { $friendlyId = "$friendlyId ($email)" }
    }
} catch { <# silently skip if token parsing fails #> }

Write-Host "  OK  Switched to account $($nextIndex + 1) of $($accounts.Count): $friendlyId" -ForegroundColor Green
Write-Host "      File: $($nextAccount.Name)" -ForegroundColor DarkGray
Write-Host ""

Pause