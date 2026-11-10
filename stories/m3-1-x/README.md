# M3 — 1.x

M3 delivers the 1.x additions that hosting REQ-36 lists: the outbox relay and the SMTP channel, dashboard insights and polish, Tier 2 (and, by the planner's assumption, Tier 3) Redis-compatible servers with their CI matrix and the Garnet fixture, the CLI, the MCP server, Native AOT verification, the soak tests and the community store listing.

Done means every M3 story is done and ST-090 has run 1.x end to end, including the Tier 2 servers, and recorded the result.

## Stories

Generated from each story's `Status:` line; run `stories.py index` after changing one.

<!-- refiner-stories:begin stories -->
| # | Story | Depends on | Wave | Status |
|---|---|---|---|---|
| 78 | [ST-078 Relay jobs through an outbox in the application's database](078-outbox.md) | ST-041, ST-073, ST-077 | 43 | not started |
| 79 | [ST-079 Send alerts by email over SMTP](079-smtp-channel.md) | ST-050, ST-077 | 43 | not started |
| 80 | [ST-080 Show readable exception chains, branding and localised UI strings](080-dashboard-polish.md) | ST-069, ST-077 | 43 | not started |
| 81 | [ST-081 Compute insights rollups and show the insights page](081-dashboard-insights.md) | ST-071, ST-077 | 43 | not started |
| 82 | [ST-082 Support Tier 2 and Tier 3 Redis-compatible servers](082-redis-tier-2-and-3.md) | ST-062, ST-077 | 43 | not started |
| 83 | [ST-083 Test the Redis store in process with a Garnet fixture](083-garnet-fixture.md) | ST-082, ST-027 | 44 | not started |
| 84 | [ST-084 Run the Redis CI matrix and publish the compatibility page](084-redis-ci-matrix.md) | ST-082 | 44 | not started |
| 85 | [ST-085 Verify Native AOT with a JsonSerializerContext](085-native-aot.md) | ST-077 | 43 | not started |
| 86 | [ST-086 Ship the Bellhop CLI tool](086-cli.md) | ST-067, ST-055, ST-056, ST-077 | 43 | not started |
| 87 | [ST-087 Expose the dashboard API to MCP clients](087-mcp-server.md) | ST-066, ST-065, ST-077 | 43 | not started |
| 88 | [ST-088 Run the zero-tuning and multi-node soak tests](088-soak-tests.md) | ST-077 | 43 | not started |
| 89 | [ST-089 List community stores only after they pass the conformance suite](089-community-stores.md) | ST-077 | 43 | not started |
| 90 | [ST-090 Accept M3: run 1.x end to end, including Tier 2 servers](090-m3-acceptance.md) | ST-078, ST-079, ST-080, ST-081, ST-083, ST-084, ST-085, ST-086, ST-087, ST-088, ST-089 | 45 | not started |
<!-- refiner-stories:end stories -->
