#!/usr/bin/env node
// Read the parser's verbose dump (decode-full.txt), produce three viewer files:
//   positions.json — player movement samples + per-channel BombPlayerState
//   events.json    — roundStarted + spike + death events (best-effort)
//   meta.json      — { mapUrl, mapName, generatedAt }
//
// Usage: node extract-stream.mjs <decode-full.txt> <output-dir> [mapName]
//
// `mapName` is OPTIONAL and only used as a fallback for the viewer's map
// lookup. The viewer accepts `?map=<name>` in the URL to override.

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';

const SRC = process.argv[2];
const DST_DIR = process.argv[3];
const MAP_HINT = process.argv[4] || '';

if (!SRC || !DST_DIR) {
  console.error('Usage: node extract-stream.mjs <decode-full.txt> <output-dir> [mapName]');
  process.exit(1);
}
if (!fs.existsSync(SRC)) {
  console.error(`source not found: ${SRC}`);
  process.exit(1);
}
fs.mkdirSync(DST_DIR, { recursive: true });

const samples = [];
const playerStateByCh = {};
const teamByCh = {};
let mapUrl = '';
const phaseEvents = [];
const bombStates = [];
const guidsSeen = new Set();
let movementLines = 0, movementMoves = 0;

// Death heuristic: BombPlayerState entries stop replicating once a player dies
// for the round. The parser doesn't emit a clean "death" line, so we infer
// from BombGameState clock + last-sample-per-actor gaps below.

const rl = readline.createInterface({
  input: fs.createReadStream(SRC, { encoding: 'utf8' }),
  crlfDelay: Infinity,
});

rl.on('line', (line) => {
  const m = line.match(/^Chindex=(\d+)\tType=([^\t]+)\tFields=(\[.*\])$/);
  if (!m) {
    // also catch map url emitted by the parser as a top-level line if added
    const mu = line.match(/^MapUrl=(.+)$/);
    if (mu) mapUrl = mu[1].trim();
    return;
  }
  const ch = +m[1], type = m[2];
  let fields;
  try { fields = JSON.parse(m[3]); } catch { return; }

  if (type === 'ReplaysClientReceiveRemoteCharacterUpdatesSingleArrayNoAutonomous') {
    movementLines++;
    const updates = (fields.find(f => f.Name === 'RemoteCharacterUpdates') || {}).Value || [];
    for (const u of updates) {
      const guid = u.ShooterCharacterNetGuidValue;
      if (!guid) continue;
      const cds = u.ComponentDataStream;
      if (!cds || !cds.Moves) continue;
      guidsSeen.add(guid);
      for (const mv of cds.Moves) {
        if (!mv.Position) continue;
        movementMoves++;
        samples.push([
          mv.Timestamp | 0,
          guid,
          +mv.Position.X.toFixed(1),
          +mv.Position.Y.toFixed(1),
          mv.RotationInput ? +mv.RotationInput.Z.toFixed(2) : 0,
        ]);
      }
    }
  } else if (type === 'BombPlayerState') {
    const obj = playerStateByCh[ch] = playerStateByCh[ch] || {};
    for (const f of fields) obj[f.Name] = f.Value;
  } else if (type === 'BombTeamComponent') {
    const tf = fields.find(f => f.Name === 'Team');
    if (tf) teamByCh[ch] = tf.Value;
  } else if (type === 'ClientGamePhaseEnded') {
    const of = fields.find(f => f.Name === 'OldPhase');
    if (of) phaseEvents.push({ phase: of.Value, sampleIdx: samples.length });
  } else if (type === 'BombGameState') {
    const tf = fields.find(f => f.Name === 'ReplicatedWorldTimeSecondsDouble');
    if (tf) bombStates.push({ t: +tf.Value.toFixed(3), sampleIdx: samples.length });
  }
});

rl.on('close', () => {
  // bounds
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const s of samples) {
    if (s[2] < minX) minX = s[2]; if (s[2] > maxX) maxX = s[2];
    if (s[3] < minY) minY = s[3]; if (s[3] > maxY) maxY = s[3];
  }

  const players = {};
  for (const ch in playerStateByCh) players[ch] = { ...playerStateByCh[ch], team: teamByCh[ch] };

  const positions = {
    meta: {
      source: path.basename(SRC),
      generatedAt: new Date().toISOString(),
      movementLines, movementMoves,
      uniqueGuids: [...guidsSeen],
      bounds: { minX, maxX, minY, maxY },
      sampleCount: samples.length,
      phaseEventCount: phaseEvents.length,
      bombStateCount: bombStates.length,
    },
    players,
    phaseEvents,
    bombStates,
    samples,
  };
  fs.writeFileSync(path.join(DST_DIR, 'positions.json'), JSON.stringify(positions));

  // === events.json — round starts from ClientGamePhaseEnded =================
  // Valorant phase cycle per round: 2(buy) → 3(combat) → 4(post) → 5(display).
  // ClientGamePhaseEnded fires with OldPhase=N when phase N just ended. So
  // OldPhase=2 = buy just ended = COMBAT STARTING = canonical round-start.
  // We convert each phase=2-ending sample-idx into a wall-ms via the bombState
  // table (the bomb clock is monotonic across the whole match, so it doubles
  // as a wall clock when anchored at sample 0).
  const events = [];
  if (bombStates.length > 0) {
    // Per-sample wall-ms via bombStates linear interpolation.
    const sampleToWallMs = (sIdx) => {
      let lo = 0, hi = bombStates.length - 1;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (bombStates[mid].sampleIdx < sIdx) lo = mid + 1; else hi = mid;
      }
      const next = bombStates[lo];
      const prev = lo > 0 ? bombStates[lo - 1] : null;
      if (!prev) return next.t * 1000;
      const span = next.sampleIdx - prev.sampleIdx;
      const a = span > 0 ? (sIdx - prev.sampleIdx) / span : 0;
      return (prev.t + (next.t - prev.t) * a) * 1000;
    };
    const wallZero = sampleToWallMs(0);
    // OldPhase=2 fires each time the buy phase ends = combat starts = round
    // begins. The very first one lands at sampleIdx=0 because BombGameState
    // only starts replicating once combat begins, which is exactly where the
    // viewer wants its first round anchor.
    const seenStarts = new Set();
    for (const pe of phaseEvents) {
      if (pe.phase !== 2) continue;
      if (seenStarts.has(pe.sampleIdx)) continue; // dedupe rare doubles
      seenStarts.add(pe.sampleIdx);
      const wallMs = Math.round(sampleToWallMs(pe.sampleIdx) - wallZero);
      events.push({ g: 'roundStarted', t: wallMs });
    }
    // If the OldPhase=2 trick didn't produce anything (rare), fall back to
    // emitting a single round-start at t=0.
    if (events.length === 0) events.push({ g: 'roundStarted', t: 0 });
  }
  fs.writeFileSync(path.join(DST_DIR, 'events.json'), JSON.stringify(events));

  // === meta.json — what the viewer uses to pick the right map ==============
  const meta = {
    mapUrl: mapUrl || '',
    mapName: MAP_HINT,
    generatedAt: new Date().toISOString(),
  };
  fs.writeFileSync(path.join(DST_DIR, 'meta.json'), JSON.stringify(meta));

  const posSize = fs.statSync(path.join(DST_DIR, 'positions.json')).size;
  console.log(`positions.json: ${(posSize / 1024 / 1024).toFixed(1)} MB`);
  console.log(`events.json:    ${events.length} events`);
  console.log(`meta.json:      mapUrl='${meta.mapUrl}' mapName='${meta.mapName}'`);
  console.log(`samples: ${samples.length}  uniqueGuids: ${guidsSeen.size}  rounds: ${events.length}`);
});
