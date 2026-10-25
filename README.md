# Wayfinder

Wayfinder is an Archipelago multiplayer lobby with a Godot client and a
TypeScript/Python backend.

## Fresh checkout

Prerequisites:

- Git
- Node.js 22+
- Python 3.12+
- A Python installation that can create/install packages with `pip`

From the repository root:

```bash
npm --prefix backend ci
npm --prefix backend run setup
npm --prefix backend run build
npm --prefix backend start
```

`npm --prefix backend run setup` is safe to rerun. It:

- Shallow-clones the Archipelago core into `backend/archipelago_core/`
- Installs the core's Python requirements
- Creates runtime directories
- Creates `backend/.env` from `.env.example` when it does not exist

The Archipelago core, downloaded game tools, ROMs, local databases, logs,
certificates, and release packages are intentionally not stored in Git. The
backend also attempts to clone the core automatically when it starts, but the
setup command is recommended because it installs the Python dependencies
explicitly and reports failures before the server is launched.

The Godot editor/runtime is also an external prerequisite for running the
client from source. Install Godot 4.x separately or use a packaged Wayfinder
release. Game tools and ROMs require their respective licenses and must be
provided separately; they are not silently downloaded by the repository.

On Windows, the same commands work in PowerShell; use `npm.cmd` if your
PowerShell execution policy blocks `npm.ps1`.

## Docker

```bash
docker compose up --build
```

The image downloads Archipelago during the image build. Runtime state is
persisted through the volumes declared in `docker-compose.yml`. Provide
production secrets through environment variables or an untracked `.env` file.

## CI

Pull requests and pushes to `main` build the backend and check Python syntax.
