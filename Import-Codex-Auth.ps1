# ==============================================================================
# .ps1
#
# Reads the current %USERPROFILE%\.codex\auth.json and saves a copy into the
# accounts\ folder used by Rotate-Codex-Auth.ps1.
#
# Run this after logging into a new account in Codex, before switching away.
# No admin rights needed — just run it normally.
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AuthFile    = "$env:USERPROFILE\.codex\auth.json"
$AccountsDir = Join-Path $PSScriptRoot "accounts"

Write-Host ""
Write-Host "  Auth source : $AuthFile" -ForegroundColor DarkGray
Write-Host "  Accounts dir: $AccountsDir" -ForegroundColor DarkGray
Write-Host ""

# ── CHECK SOURCE FILE ──────────────────────────────────────────────────────────

if (-not (Test-Path $AuthFile)) {
    Write-Host "  [!] No auth.json found at: $AuthFile" -ForegroundColor Red
    Write-Host "      Log into Codex first, then run this script." -ForegroundColor Red
    Write-Host ""
    Pause; exit 1
}

# ── DECODE EMAIL FROM JWT FOR DISPLAY ─────────────────────────────────────────

$detectedEmail = $null
try {
    $json    = Get-Content $AuthFile -Raw | ConvertFrom-Json
    $idToken = $json.tokens.id_token
    if ($idToken) {
        $payload = $idToken.Split('.')[1]
        $pad = 4 - ($payload.Length % 4); if ($pad -ne 4) { $payload += '=' * $pad }
        $decoded       = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $detectedEmail = ($decoded | ConvertFrom-Json).email
    }
} catch { <# ignore, email display is optional #> }

Write-Host "  Current auth.json" -ForegroundColor Cyan
if ($detectedEmail) {
    Write-Host "  Detected email: $detectedEmail" -ForegroundColor White
} else {
    Write-Host "  (Could not decode email from token)" -ForegroundColor DarkGray
}
Write-Host ""

# ── ENSURE ACCOUNTS FOLDER EXISTS ─────────────────────────────────────────────

if (-not (Test-Path $AccountsDir)) {
    New-Item -ItemType Directory -Path $AccountsDir | Out-Null
    Write-Host "  [+] Created accounts\ folder." -ForegroundColor Cyan
}

# ── LIST EXISTING ACCOUNTS ─────────────────────────────────────────────────────

$existing = @(Get-ChildItem -Path $AccountsDir -Filter "*.json" | Sort-Object Name)
if ($existing.Count -gt 0) {
    Write-Host "  Existing accounts:" -ForegroundColor DarkGray
    foreach ($f in $existing) {
        Write-Host "    $($f.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ── PROMPT FOR NAME ────────────────────────────────────────────────────────────

$suggestion = if ($detectedEmail) { ($detectedEmail -split '@')[0] } else { "" }

Write-Host "  Enter a short name for this account (e.g. Personal, CompanyA)." -ForegroundColor Yellow
if ($suggestion) {
    Write-Host "  Press Enter to use detected name: $suggestion" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host -NoNewline "  Name: "
$input = Read-Host

if ([string]::IsNullOrWhiteSpace($input)) {
    if ($suggestion) {
        $input = $suggestion
    } else {
        Write-Host "  [!] No name entered. Aborting." -ForegroundColor Red
        Pause; exit 1
    }
}

$safeName = ($input.Trim() -replace '[\\/:*?"<>|]', '_')

# ── DETERMINE NEXT PREFIX NUMBER ───────────────────────────────────────────────

$maxPrefix = 0
foreach ($f in $existing) {
    if ($f.Name -match '^(\d+)_') {
        $n = [int]$Matches[1]
        if ($n -gt $maxPrefix) { $maxPrefix = $n }
    }
}
$prefix   = "{0:D2}" -f ($maxPrefix + 1)
$fileName = "${prefix}_${safeName}.json"
$destPath = Join-Path $AccountsDir $fileName

# ── CHECK FOR DUPLICATE ────────────────────────────────────────────────────────

$duplicate = $existing | Where-Object {
    ($_.Name -replace '^\d+_', '' -replace '\.json$', '') -eq $safeName
}
if ($duplicate) {
    Write-Host ""
    Write-Host "  [!] An account named '$safeName' already exists: $($duplicate.Name)" -ForegroundColor Yellow
    Write-Host -NoNewline "  Overwrite it? (y/N): "
    $confirm = Read-Host
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "  Aborted." -ForegroundColor Red
        Pause; exit 0
    }
    $destPath = $duplicate.FullName
    $fileName = $duplicate.Name
}

# ── COPY ───────────────────────────────────────────────────────────────────────

Copy-Item $AuthFile $destPath -Force

Write-Host ""
if (Test-Path $destPath) {
    Write-Host "  OK  Saved as: $fileName" -ForegroundColor Green
    Write-Host "      Full path: $destPath" -ForegroundColor DarkGray
} else {
    Write-Host "  [!] Something went wrong — file not found after copy." -ForegroundColor Red
    Write-Host "      Tried to write to: $destPath" -ForegroundColor Red
}
Write-Host ""

Pause