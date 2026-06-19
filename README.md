# ValorantWebReplayer

End-to-end tactical replay viewer for Valorant `.vrf` files. Drop a `.vrf` in,
get a browser-based scrubbable minimap viewer out. **Windows-only.**

> Not affiliated with, endorsed by, or sponsored by Riot Games. Valorant and
> the Valorant logo are trademarks of Riot Games, Inc.

https://github.com/user-attachments/assets/78509fcc-61fa-4a1a-b6e5-8f59f1191c63


*(if the embedded video doesn't render, [open `docs/demo.mov`](docs/demo.mov)
directly)*

## What this does

- **In:** any `.vrf` from your local Valorant install
  (`%LOCALAPPDATA%\VALORANT\Saved\Demos\`).
- **Out:** an interactive viewer in your browser showing player positions,
  rounds, abilities, and spike timing on the actual map's minimap.
- **No Riot Client lockfile** is read. **No `pvp.net` endpoints** are hit.
  **No API keys** are required anywhere in this bundle.
- The only network calls happen in the **browser**, to `valorant-api.com`
  (public CDN, no auth) to pull the current map's minimap + agent metadata
  + rank badges.

### What you give up vs. Riot's authoritative match data

Without `match-details` from Riot's servers, the viewer runs in **anonymous
mode** — everything the `.vrf` itself contains, nothing more:

| Feature                       | This viewer | Needs `match-details` (not used here) |
| ----------------------------- | ----------- | ------------------------------------- |
| Player positions on minimap   | ✅          |                                       |
| Round timeline + scrub        | ✅          |                                       |
| Abilities (smokes, walls, …)  | ✅          |                                       |
| Spike plant/defuse timing     | ✅          |                                       |
| `ProfileName` + rank tier     | ✅          |                                       |
| Real player names (RiotID)    | ❌          | ✅                                    |
| Agent icons per player        | ❌          | ✅                                    |
| KDA + score                   | ❌          | ✅                                    |
| Killer / victim attribution   | ❌          | ✅                                    |
| True aim direction at kills   | ❌          | ✅                                    |

In Customs/scrims `ProfileName` is usually the real Riot ID. In Competitive
it's anonymized (`Imported Crosshair …`, `Player N`).

## Install

### One-shot prerequisites installer

From an elevated PowerShell (right-click → "Run as administrator"):

```powershell
.\install-prereqs.ps1
```

That uses `winget` to install Node.js 20 LTS — the only runtime dependency.
The parser binary is self-contained (.NET 10 baked in), the static file
server is plain Node, and the viewer runs in your existing browser.

### Get the parser binary

The parser is [`michel-giehl/ValorantReplayParserPlayground`](https://github.com/michel-giehl/ValorantReplayParserPlayground)
plus a ~120-line patch that exposes channel-open events so we can pull
ability locations out of actor spawns (abilities in Valorant ARE actors —
`Patch_Phoenix_MolotovFire_C`, `Smoke_Production_Astra_C`, etc.).

Patched source: [`talhakoek/ValorantReplayParserPlayground @ revamped-channel-hooks`](https://github.com/talhakoek/ValorantReplayParserPlayground/tree/revamped-channel-hooks)
· [diff vs upstream](https://github.com/talhakoek/ValorantReplayParserPlayground/compare/master...revamped-channel-hooks)

Two ways to get the binary:

1. **Download the latest release** from this repo and drop the included
   `ValorantReplayParser.exe` into `.\bin\`.
2. **Or build it yourself** from the patched branch:
   ```powershell
   git clone -b revamped-channel-hooks https://github.com/talhakoek/ValorantReplayParserPlayground.git
   cd ValorantReplayParserPlayground
   dotnet publish src/ValorantReplayParser/ValorantReplayParser.csproj `
     -c Release -r win-x64 --self-contained true `
     /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true `
     -o ..\publish
   Copy-Item ..\publish\ValorantReplayParser.exe ..\ValorantWebReplayer\bin\
   ```

## Usage

```powershell
# basic — viewer falls back to the first map record if you don't say which
.\process.ps1 -Vrf "C:\path\to\replay.vrf"

# explicit map name (passed to the viewer as ?map=Split)
.\process.ps1 -Vrf "C:\path\to\replay.vrf" -Map Split

# custom port + don't auto-open browser
.\process.ps1 -Vrf "C:\path\to\replay.vrf" -Port 8123 -NoOpen

# keep the 1+ GB decode-full.txt around for debugging
.\process.ps1 -Vrf "C:\path\to\replay.vrf" -KeepDecode
```

Output lands in `.\output\<vrf-basename>\` and the viewer serves it on
`http://127.0.0.1:8123/`. Hit `Ctrl+C` to stop the server.

### Sharing a parsed replay

Everything in `.\output\<vrf-basename>\` is fully self-contained — no Riot
auth, no `pvp.net` references. Zip the folder and another user can unzip it
and run:

```powershell
node ..\..\scripts\serve.mjs 8123 .
```

…from inside the unzipped folder, then open `http://127.0.0.1:8123/`.

## Pipeline stages

```
.\process.ps1 -Vrf x.vrf
   │
   ▼
[1] bin\ValorantReplayParser.exe x.vrf --verbose --full
      → output\<x>\decode-full.txt   (~1 GB raw event dump, deleted after stage 2)
      → output\<x>\channels.jsonl    (compact per-channel events)
   │
   ▼
[2] node scripts\extract-stream.mjs decode-full.txt output\<x> [mapName]
      → positions.json   (player movement samples + BombPlayerState)
      → events.json      (round starts derived from ClientGamePhaseEnded)
      → meta.json        ({ mapUrl, mapName })
   │
   ▼
[3] node scripts\build-abilities.mjs channels.jsonl positions.json abilities.json
      → abilities.json   (typed ability spawns w/ team via spatial clustering)
   │
   ▼
[4] Stage viewer\index.html + spike.png into output\<x>\
[5] node scripts\serve.mjs 8123 output\<x>\
      → browser opens http://127.0.0.1:8123/
```

## Map detection

The viewer fetches `https://valorant-api.com/v1/maps` at load and resolves
the map record by:

1. `?map=<DisplayName>` URL parameter (e.g. `?map=Bind`)
2. `meta.mapUrl` from `meta.json` (UE path like `/Game/Maps/Bonsai/Bonsai`) —
   reserved for a future parser update that extracts it from the .vrf header
3. `meta.mapName` from `meta.json` (set via the `-Map` flag)
4. Falls back to the first map record (almost certainly wrong)

Pass `-Map Bind` (or whatever) to `process.ps1` if you know it.

## Layout

```
process.ps1                       single-command orchestrator
install-prereqs.ps1               winget installer for Node.js
bin\ValorantReplayParser.exe      self-contained .NET 10 parser (from Releases)
scripts\extract-stream.mjs        decode-full.txt → positions + events + meta
scripts\build-abilities.mjs       channels.jsonl + positions → abilities
scripts\serve.mjs                 tiny static file server (replaces python -m http.server)
viewer\index.html                 browser viewer
viewer\spike.png                  spike icon (decorative)
docs\demo.mov                     screen recording of the viewer
output\                           per-replay outputs go here (gitignored)
```

## License + credits

MIT. See [`LICENSE`](LICENSE) and [`CREDITS.md`](CREDITS.md) for
attribution to upstream projects (`michel-giehl/ValorantReplayParser`,
`OozSharp`, `valorant-api.com`).
