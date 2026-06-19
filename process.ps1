# ValorantWebReplayer pipeline — single-command entry.
#
# Drops the parser, extractor, ability builder, and viewer server into one
# end-to-end run. NO Riot Client lockfile is touched. NO pvp.net endpoints
# are hit. The only network calls happen INSIDE THE BROWSER (viewer pulls map
# splash + agent icons from valorant-api.com — a public CDN with no auth).
#
# Usage:
#   .\process.ps1 -Vrf "C:\path\to\replay.vrf"
#   .\process.ps1 -Vrf "...vrf" -Map Split            # override map name
#   .\process.ps1 -Vrf "...vrf" -Port 8123 -NoOpen    # custom port, don't open browser
#
# Output: written to .\output\<vrf-basename>\

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Vrf,
  [string]$Map = "",
  [int]$Port = 8123,
  [switch]$NoOpen,
  [switch]$KeepDecode
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$VrfBase = [System.IO.Path]::GetFileNameWithoutExtension($Vrf)
$OutDir = Join-Path $Root "output\$VrfBase"
$null = New-Item -ItemType Directory -Force -Path $OutDir
$DecodePath = Join-Path $OutDir "decode-full.txt"
$ChannelsPath = Join-Path $OutDir "channels.jsonl"
$PositionsPath = Join-Path $OutDir "positions.json"
$EventsPath = Join-Path $OutDir "events.json"
$MetaPath = Join-Path $OutDir "meta.json"
$AbilitiesPath = Join-Path $OutDir "abilities.json"

# --- Stage 1: parser dump ---------------------------------------------------
Write-Host "[1/4] parser …" -ForegroundColor Cyan
$ParserExe = Join-Path $Root "bin\ValorantReplayParser.exe"
if (-not (Test-Path $ParserExe)) {
  Write-Host "Parser not found at $ParserExe" -ForegroundColor Red
  Write-Host "Place a self-contained ValorantReplayParser.exe in .\bin\ (see README)." -ForegroundColor Yellow
  exit 1
}

# The parser writes channels.jsonl to a hard-coded path. Wrap its run so we
# capture both the verbose stdout (decode-full.txt) AND the channels.jsonl
# in our per-replay output dir.
$ParserCwd = Split-Path -Parent $ParserExe
Push-Location $ParserCwd
try {
  # Run with --verbose --full so movement data is dumped to stdout.
  # The parser writes informational lines to stderr; redirect them to the
  # console rather than tripping $ErrorActionPreference = "Stop". Wrapping
  # in cmd /c keeps PowerShell from interpreting stderr as an exception.
  cmd /c """$ParserExe"" ""$Vrf"" --verbose --full > ""$DecodePath"" 2>&1"
  if ($LASTEXITCODE -ne 0) { throw "parser exited $LASTEXITCODE" }
  # Move channels.jsonl from wherever the parser dropped it (default: C:\Users\Barrage\replay-work\channels.jsonl)
  $DefaultChan = "C:\Users\Barrage\replay-work\channels.jsonl"
  if (Test-Path $DefaultChan) { Move-Item -Force $DefaultChan $ChannelsPath }
  elseif (Test-Path (Join-Path $ParserCwd "channels.jsonl")) {
    Move-Item -Force (Join-Path $ParserCwd "channels.jsonl") $ChannelsPath
  } else { throw "channels.jsonl not produced by parser" }
}
finally { Pop-Location }

$decodeBytes = (Get-Item $DecodePath).Length
Write-Host ("      decode-full.txt: {0:N1} MB" -f ($decodeBytes / 1MB))

# --- Stage 2: extract positions + events + meta -----------------------------
Write-Host "[2/4] extract-stream …" -ForegroundColor Cyan
node (Join-Path $Root "scripts\extract-stream.mjs") $DecodePath $OutDir $Map
if ($LASTEXITCODE -ne 0) { throw "extract-stream failed" }

if (-not $KeepDecode) {
  Remove-Item $DecodePath -Force
  Write-Host "      decode-full.txt removed (re-run with -KeepDecode to keep it)"
}

# --- Stage 3: build abilities -----------------------------------------------
Write-Host "[3/4] build-abilities …" -ForegroundColor Cyan
node (Join-Path $Root "scripts\build-abilities.mjs") $ChannelsPath $PositionsPath $AbilitiesPath
if ($LASTEXITCODE -ne 0) { throw "build-abilities failed" }

# --- Stage 4: stage viewer + serve ------------------------------------------
Write-Host "[4/4] staging viewer …" -ForegroundColor Cyan
$ViewerSrc = Join-Path $Root "viewer"
foreach ($f in @("index.html", "spike.png")) {
  Copy-Item -Force (Join-Path $ViewerSrc $f) (Join-Path $OutDir $f)
}

$Url = "http://127.0.0.1:$Port/index.html"
if ($Map) { $Url = "$Url`?map=$Map" }

Write-Host ""
Write-Host "Output dir: $OutDir"
Write-Host "Serving at: $Url"
Write-Host "Ctrl+C to stop the server."
Write-Host ""

if (-not $NoOpen) {
  Start-Process $Url
}

node (Join-Path $Root "scripts\serve.mjs") $Port $OutDir
