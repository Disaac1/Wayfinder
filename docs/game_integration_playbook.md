# Wayfinder Game Integration Specification & Playbook

This document serves as the canonical technical guide and playbook for integrating new games into Wayfinder. It is structured so that any developer or autonomous LLM agent can implement end-to-end support for a new game cleanly, reliably, and without encountering common pitfalls.

---

## 1. Overview & Architecture

Wayfinder integrates games through a coordinated stack across its backend and Godot frontend client:

```
┌─────────────────────────────────────────────────────────────┐
│                       WAYFINDER BACKEND                     │
│  - backend/archipelago_core/custom_worlds/<slug>.apworld    │
│  - backend/data/games/<slug>/                               │
│      ├── launch.json                                        │
│      ├── guided_setup.json                                  │
│      └── icon.png                                           │
│  - backend/data/tools/<tool>.json                           │
│  - backend/data/roms.json                                   │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTP API Sync
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                    WAYFINDER GODOT CLIENT                   │
│  - client/Archipelago/custom_worlds/<slug>.apworld          │
│  - client/scripts/core/game_launcher.gd                     │
│  - client/scripts/core/rom_download_service.gd              │
│  - client/scripts/core/tracker_manager.gd                   │
│  - PopTracker & Emulator Auto-Provisioning                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Wayfinder Support Tiers

When adding a game, determine its target support tier:

| Tier | Category | User Experience | Mechanics |
| :--- | :--- | :--- | :--- |
| **Tier 1** | Full Direct Native Support | 1-Click Launch | Auto-checks assets, extracts seed patch, automatically syncs `host.yaml` (ROM/emulator paths), spawns Archipelago client or game executable with auto-connect CLI args (`-- --connect <server>`). PopTracker automatically installs pack and launches with autotracking. |
| **Tier 2** | Auto-Patch & Emulator | 1-Click Launch | Auto-verifies ROM, extracts `.ap*` seed patch into patched ROM/disc, launches emulator with ROM, copies server connection string to clipboard for in-game/connector connect. |
| **Tier 3** | PC Mod Auto-Provisioning | 1-Click Launch | Mod loader (SMAPI, BepInEx, Lovely) auto-configured; connection JSON/YAML written directly to mod directory before launch. |
| **Tier 4** | Custom `.apworld` Support | Options & Room Setup | Dynamic options schema parsed from `.apworld` via `parse_options.py`; room generation and web UI options supported without local automated game launching. |

---

## 3. Step-by-Step Implementation Process

Follow these 7 steps in order to integrate any game.

### Step 1: APWorld Provisioning (Backend & Client)
1. Acquire the `.apworld` release.
2. Place `.apworld` into `backend/archipelago_core/custom_worlds/<world_name>.apworld`.
3. Place `.apworld` into `client/Archipelago/custom_worlds/<world_name>.apworld`.
4. Verify importability via `parse_options.py`:
   ```bash
   python backend/src/parse_options.py backend/archipelago_core "<Game Name>" backend/archipelago_core/custom_worlds
   ```
   > [!IMPORTANT]
   > Ensure any optional Python dependencies (e.g. `dolphin_memory_engine`, `pyevermizer`, `zilliandomizer`, `setuptools<70` for `pkg_resources`) required by the apworld are installed in the host Python environment.

### Step 2: Launcher Metadata (`launch.json`)
Create `backend/data/games/<slug>/launch.json`:
```json
{
  "game_name": "Game Display Name",
  "short_tag": "TAG",
  "support_tier": 1,
  "launch_mode": "ap_client",
  "patch_extension": ".apext",
  "patch_extension_aliases": [".apext"],
  "client_tool": "archipelago_client",
  "client_component": "Component or Client Name",
  "emulator_tool": "dolphin",
  "required_rom": "Game Title (USA).iso",
  "rom_aliases": [
    "Game Title (USA).iso",
    "Game Title (USA).rvz",
    "InternalTitleID.iso",
    "InternalTitleID.rvz"
  ],
  "rom_hashes": {
    "md5": "optional_hex_md5"
  },
  "host_yaml": {
    "section": "gamename_options",
    "rom_file_key": "iso_file"
  },
  "auto_connect": true,
  "tracker": {
    "supported": true,
    "pack_name": "Game Title",
    "package_uid": "game_poptracker",
    "pack_version": "1.0.0",
    "pack_download_url": "https://github.com/.../pack.zip",
    "pack_sha256": "<sha256_of_zip>",
    "source_url": "https://github.com/...",
    "auto_tracking": true
  },
  "install_instructions": "Tier 1 Full Support description..."
}
```

### Step 3: Guided Setup Wizard (`guided_setup.json`)
Create `backend/data/games/<slug>/guided_setup.json` with 3-5 intuitive setup steps matching the game's YAML option schema.
- **`default_config`**: Object with option defaults.
- **`required_schema_keys`**: List of primary option keys required for generation.
- **`steps`**: Array of step objects containing UI `controls`:
  - `card_grid`: Visual selection grid with options.
  - `segmented_range` / `slider`: Numeric settings (health, counts, speeds).
  - `switch`: Boolean toggles (DeathLink, features).

### Step 4: Game Icon
Place a high-resolution square PNG at:
`backend/data/games/<slug>/icon.png` (min 128x128, max 512x512).

### Step 5: Emulator / Tool Provisioning (If applicable)
If the game uses an emulator or standalone tool not yet registered:
Create `backend/data/tools/<tool_name>.json`:
```json
{
  "name": "Dolphin Emulator",
  "executable": "Dolphin.exe",
  "sub_folders": [
    "Dolphin",
    "Dolphin-x64",
    "dolphin-master"
  ],
  "download_url": "https://.../build.7z",
  "fallback_download_url": "https://github.com/..."
}
```

### Step 6: ROM & Compression Catalog (`backend/data/roms.json`)
Add download link and decryption/extraction metadata for the vanilla base ROM:
```json
  "Game Title (USA).rvz": {
    "url": "https://drive.google.com/...",
    "key": "encryption_passphrase_if_encrypted",
    "encrypted": true
  },
  "Game Title (USA).iso": {
    "url": "https://drive.google.com/...",
    "key": "encryption_passphrase_if_encrypted",
    "encrypted": true
  }
```
> [!NOTE]
> Always alias both the compressed and uncompressed format names (e.g. `.rvz` and `.iso`) so user search and automated download match regardless of source key.

### Step 7: Automated Test Suite & Verification
Create a regression test script under `client/scripts/tests/launch_test_<slug>_tier1.gd`:
1. Preset resolution & Tier 1 identification.
2. ROM aliases verification.
3. PopTracker configuration & package validation.
4. `host.yaml` synchronization test.
5. Guided setup wizard schema validation.
6. APWorld file presence in client bundle.
7. Tool hooks / format conversions (e.g. `convert_rvz_to_iso`).

Run headless test verification:
```bash
client\godot_console.exe --headless --path client -s res://scripts/tests/launch_test_<slug>_tier1.gd
```

---

## 4. Key Lessons Learned & Edge Cases

### 1. GameCube & Wii Disc Formats (`.rvz` vs `.iso`)
- **Archipelago Patcher Requirement**: apworld rom patchers (such as `gclib` or `LM_Rom.py`) expect a raw, uncompressed `.iso` with a matching MD5 checksum (`6e3d9ae0ed2fbd2f77fa1ca09a60c494`).
- **Compression**: `.rvz` reduces disc size by ~90% (e.g. 1.4 GB down to 150 MB).
- **Automation Solution**:
  - Accept `.rvz` in `rom_aliases`.
  - When Wayfinder downloads or detects an `.rvz`, it invokes `DolphinTool.exe convert -i <file.rvz> -o <file.iso> -f iso`.
  - The patcher and `host.yaml` are transparently given the uncompressed `.iso`.

### 2. Magic Header Detection vs Extension Heuristics
- **Problem**: Encrypted archives (`.enc`) should not blindly be assumed to be `.zip` files.
- **Solution**: In `rom_download_service.gd`:
  - `_has_zip_header()` checks for magic `50 4B` (`PK`).
  - `_has_rvz_header()` checks for magic `52 56 5A 01` (`RVZ\x01`).
  - Only feed true zip archives to Godot's `ZIPReader`.

### 3. Cache Invalidation
- **Problem**: When a new `.apworld` or `launch.json` is added, the server or client may continue serving stale cached games.
- **Solution**:
  - `backend/src/archipelagoRunner.ts` implements directory-fingerprinting on `custom_worlds/` and auto-invalidates the SQLite `OptionsCache`.
  - `backend/src/launcherRoutes.ts` exposes `invalidateSlugMapCache()`.
  - On the client side, restart the client or trigger cache refresh in lobby to re-pull the updated catalog.

### 4. Interactive Command Prompts in Python Core
- If an apworld imports an optional missing library, `ModuleUpdate.update()` may block on `press enter to install it`.
- In `backend/src/parse_options.py`, set `ModuleUpdate.update_ran = True` before importing worlds to disable interactive blocking prompts.

---

## 5. Checklist for Adding a New Game

- [ ] Place `.apworld` in `backend/archipelago_core/custom_worlds/` and `client/Archipelago/custom_worlds/`.
- [ ] Verify `parse_options.py` succeeds without error.
- [ ] Create `backend/data/games/<slug>/launch.json`.
- [ ] Create `backend/data/games/<slug>/guided_setup.json`.
- [ ] Add `backend/data/games/<slug>/icon.png`.
- [ ] If new emulator/tool needed: add `backend/data/tools/<tool>.json`.
- [ ] Register base ROM download link in `backend/data/roms.json` (and sync to user config).
- [ ] Write and run test suite: `client\godot_console.exe --headless --path client -s res://scripts/tests/launch_test_<slug>_tier1.gd`.
- [ ] Update `GamesList.md` status row.
- [ ] Verify `npm --prefix backend run build` compiles cleanly.
