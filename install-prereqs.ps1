# Prerequisites installer for ValorantWebReplayer.
#
# Installs Node.js (20+) via winget. That's the only runtime dependency —
# the parser binary is self-contained (.NET 10 baked in), the static file
# server is plain Node, and the viewer runs in your existing browser.
#
# Safe to re-run: skips anything already installed.
#
# Usage (from an elevated PowerShell, right-click → "Run as administrator"):
#   .\install-prereqs.ps1

$ErrorActionPreference = "Stop"

function Has-Cmd($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-NodeVersion {
  if (-not (Has-Cmd node)) { return $null }
  try {
    $v = (node --version) -replace '^v', ''
    return [version]($v -split '\.' | Select-Object -First 3 | Join-String -Separator '.')
  } catch { return $null }
}

Write-Host ""
Write-Host "ValorantWebReplayer — prerequisites installer" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# --- winget ----------------------------------------------------------------
if (-not (Has-Cmd winget)) {
  Write-Host "winget not found." -ForegroundColor Yellow
  Write-Host "winget ships with Windows 10 1809+ and Windows 11. Update App Installer from"
  Write-Host "the Microsoft Store, or install Node.js manually from https://nodejs.org/."
  exit 1
}

# --- Node.js ---------------------------------------------------------------
$nodeVer = Get-NodeVersion
if ($nodeVer -and $nodeVer.Major -ge 20) {
  Write-Host ("[skip] Node.js {0} already installed (>= 20 required)" -f $nodeVer) -ForegroundColor Green
} else {
  if ($nodeVer) {
    Write-Host ("[upgrade] Node.js {0} installed but < 20. Installing latest LTS..." -f $nodeVer) -ForegroundColor Yellow
  } else {
    Write-Host "[install] Node.js (latest LTS)..." -ForegroundColor Yellow
  }
  winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    Write-Host "winget install for Node.js failed (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
  }
}

# Re-probe with a fresh PATH (winget edits the user PATH but doesn't push it
# to this session — open a new terminal to use it, or trust this re-probe).
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host ""
Write-Host "All prerequisites installed." -ForegroundColor Green
Write-Host ""
Write-Host "Next step:"
Write-Host "  .\process.ps1 -Vrf ""C:\path\to\replay.vrf"" -Map Split"
Write-Host ""
Write-Host "(Open a new PowerShell window if 'node' isn't on PATH yet.)" -ForegroundColor Gray
