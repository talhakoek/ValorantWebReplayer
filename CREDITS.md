# Credits

This project is a thin orchestration + viewer layer on top of work done by
others. Most of the heavy lifting belongs to:

## [`michel-giehl/ValorantReplayParser`](https://github.com/michel-giehl/ValorantReplayParser)

The actual `.vrf` parser — built on top of the FortniteReplayReader fork,
extended with Valorant-specific net-field exports for `BombGameState`,
`BombPlayerState`, and `ReplaysClientReceiveRemoteCharacterUpdatesSingleArrayNoAutonomous`
(which is where player movement lives).

MIT licensed. The binary shipped in our GitHub Release is built from upstream
plus a small `Program.cs` wrapper that adds `--full` mode + channel-event
JSONL dumping.

## [`OozSharp`](https://github.com/jamesbloom/OozSharp)

Pure-C# Oodle Kraken decompressor. Valorant's `.vrf` files wrap their
delta-encoded UE replay frames in Oodle, so without this layer the parser
literally cannot read past the header.

MIT licensed, included as a transitive dependency of the parser.

## [`valorant-api.com`](https://valorant-api.com)

Maintained by Officer (Iceeey). Public CDN for Valorant metadata —
agents, abilities, maps, competitive tiers, skins. The viewer pulls map
splashes (`/v1/maps`), agent icons (`/v1/agents`), and rank badges
(`/v1/competitivetiers`) at load time. No auth, no key.

## Microsoft

`.NET 10` runtime, baked into the self-contained parser binary so end users
don't need a separate install.

---

**Not affiliated with, endorsed by, or sponsored by Riot Games or any of its
subsidiaries.** Valorant, the Valorant logo, and all related trademarks
belong to Riot Games, Inc.
