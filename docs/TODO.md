# Wayfinder: Master Execution Plan & Game Automation Roadmap

## Phase 1: Foundational Lobby Backend (Node.js/WebSocket/SQLite) - ✅ COMPLETED
- [x] 1.1 Initialize Node.js project. Set up an SQLite database using `better-sqlite3`.
- [x] 1.2 Create schemas for `Rooms`, `Users`, and `Sessions` (to track save states and locks).
- [x] 1.3 Create a WebSocket Room Manager (Create Room, Join Room via 6-digit code).
- [x] 1.4 Implement player state syncing (Name, Selected Game, Ready/Configured Status).

## Phase 2: Client UI Prototype (Godot Engine) - ✅ COMPLETED
- [x] 2.1 Main Menu (Create/Join Lobby).
- [x] 2.2 Lobby UI (List of connected players, game selection, instant start).
- [x] 2.3 WebSocket client logic in Godot connected to Node.js backend.
- [x] 2.4 Dynamic reactive UI updates for player state and active AP server.

## Phase 3: YAML Configuration UI & Data Package - ✅ COMPLETED
- [x] 3.1 Dynamic UI parser in Godot to read base Archipelago JSON/YAML option files.
- [x] 3.2 UI controls (range sliders, choice dropdowns, item/location search browsers).
- [x] 3.3 YamlBuilder serialization to convert UI choices into valid Archipelago `.yaml`.
- [x] 3.4 Transmit compiled `.yaml` from Godot to backend on room generation.

## Phase 4: Seed Generation & Distribution - ✅ COMPLETED
- [x] 4.1 Backend endpoint to accept all player YAMLs when host clicks "Start Game".
- [x] 4.2 Backend Archipelago core generation execution pipeline (`generateSeed`).
- [x] 4.3 Direct player-specific seed patch file API (`GET /api/seeds/:roomCode/player-patch`).

## Phase 5: Automated Server Hosting & Socket Resilience - ✅ COMPLETED
- [x] 5.1 Auto-spawn local Archipelago MultiServer process on room generation.
- [x] 5.2 `hasActiveTcpClients` netstat socket inspection to keep AP server alive while game clients are connected.
- [x] 5.3 Multi-location `host.yaml` syncing (`pokemon_emerald_options`, `bizhawkclient_options`).

## Phase 6: Cloud Saves & Session Handoff - ✅ COMPLETED
- [x] 6.1 Backend REST endpoints (`GET /api/session/:id/checkout`, `POST /api/session/:id/checkin`).
- [x] 6.2 Godot client automated zip save state checkout/checkin with force unlock override.

## Phase 7: Tier 1 Game Engine & Zero-ROM Automation - ✅ COMPLETED
- [x] 7.1 **Pokemon Emerald**: BizHawk + Archipelago BizHawk Client + auto `host.yaml` sync + auto base ROM mirroring + 5s countdown auto-advance.
- [x] 7.2 **Super Mario 64 (`sm64ex`)**: Zero-ROM pre-compiled PC port bundle distribution (`sm64.us.f3dex2e.exe`), live `--sm64ap_name` and `--sm64ap_ip` connection args.
- [x] 7.3 **BizHawk Prerequisites**: Auto-install VC++ 2010 SP1 x64 runtime (`msvcp100.dll`).
- [x] 7.4 **Non-Blocking Extraction**: Smooth frame yielding (`await get_tree().process_frame`) and itemized progress bar UI during ZIP extractions.

## Phase 8: Game Expansion Roadmap & Automation Tiers - 🔄 IN PROGRESS
- [ ] 8.1 **Tier 1 Games**: Pokemon Red/Blue (`SameBoy`), OoT (`OoT Client` `.apz5`), MMBN3 (`.apbn3`), Zelda 1 (`.aptloz`).
- [ ] 8.2 **Tier 2 SNES Games**: A Link to the Past (`.apz3`), Super Metroid (`.apsm`), Super Mario World (`.apsmw`), SMZ3 (`.apsmz3`) with Snes9x auto-provisioner.
- [ ] 8.3 **Tier 3 PC Mod Engine**: Auto-write mod config files (`config.json`/`archipelago.json`) for Stardew Valley (SMAPI), Subnautica (BepInEx), Risk of Rain 2 (BepInEx), Balatro (Lovely), Inscryption (BepInEx), Celeste (Everest).
- [ ] 8.4 **Tier 4 Custom APWorlds**: Backend upload `/api/custom-worlds/upload` & community `.apworld` index integration.