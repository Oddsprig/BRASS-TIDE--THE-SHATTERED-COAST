# Release history

| Version | Exact tagged game-source commit | Date | Portable release |
|---|---|---|---|
| 0.001 | e4c07d3ab72de3604010c6042e51d3e04a3dccaa | 2026-10-20 | ../Brass Tide v0.001 |
| 0.002 | 6c0e81b69684b7c1eebaa6430d2eebd190bf7b72 | 2026-10-20 | ../Brass Tide v0.002 |
| 0.003 | 511981eb0ab3d70cf19fa2dd6e3584ae2c224f48 | 2026-10-20 | ../Brass Tide v0.003 |
| 0.004 | 17225a90c8170c82f19f5847ab2ec6da11e8a8dd | 2026-10-20 | ../Brass Tide v0.004 |
| 0.005 | fc35c3438c80ea628da5ca2eeee727c19331c8d5 | 2026-10-20 | ../Brass Tide v0.005 |
| 0.006 | 17306228e150b6d3aeb1a7b98861a1c3ce94545b | 2026-10-20 | ../Brass Tide v0.006 |
| 0.007 | v0.007^{commit}; exact hash in RELEASE.json | 2026-10-20 | ../Brass Tide v0.007 |

v0.001 main/tag publication was independently verified. v0.002 Windows x64 export and its standalone menu/campaign/save/battle, PCK/icon/PE checks passed. Its publication receipt records the exact remote state. Post-export records may live on main with game files unchanged from the exact tagged source. All older releases are preserved.


Publication attempt after network grant: Windows blocked Git's credential-helper shell (NtCreateDirectoryObject0xC0000022); no credentials were extracted and no workaround bypassed the restriction. Independent GitHub API read still shows main f7f13d9e3ffeebbddcddc52f6762772e20d1abc6 and v0.002 returns404. Thus v0.002 is fully delivered locally but not uploaded. The prepared sibling Publish Brass Tide to GitHub.cmd can run under the owner's normal Windows account, as for v0.001, then verifies both refs. No source upload is claimed until those refs match.

Sequential local delivery verified: v0.003, v0.004, v0.005 and v0.006 Windows/source ZIPs pass CRC and SHA256 checks. v0.006 exact-tag clean21suite run and standalone menu/campaign/save/battle checks pass. Each release builds on its predecessor. Desktop launcher now targets v0.006; current owner save was copied only after clean archives. GitHub publication is recorded separately and is not inferred from local success.
