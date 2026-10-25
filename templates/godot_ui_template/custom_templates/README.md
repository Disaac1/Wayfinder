# Custom Lightweight Export Templates for UI Apps

## Why Godot's Default `.exe` is ~110 MB
By default, Godot's Windows release template (`windows_release_x86_64.exe` in `%APPDATA%/Godot/export_templates/4.7.stable/`) is **~109 MB**.
It includes:
- Vulkan Forward+ & Mobile 3D renderers
- 3D physics engines (GodotPhysics3D / Jolt)
- 2D physics engines
- 2D & 3D Navigation
- OpenXR & VR runtimes
- Audio effects, Raycasts, GridMaps, CSG, etc.

When exporting a pure UI desktop application, none of that 3D/physics code is needed.

---

## Size Comparison

| Export Template Configuration | Approximate `.exe` Size |
|---|---|
| **Default Official Godot Template** | **~109 MB** |
| **Custom UI-Only Template (`ui_only.build`)** | **~18 – 24 MB** (~80% reduction) |
| **Custom UI-Only Template + UPX** | **~8 – 12 MB** (~90% reduction) |

---

## How to Get / Build the Stripped Template

### Option 1: GitHub Actions (Recommended — Zero Local Tooling)
A ready-to-run GitHub Actions workflow has been set up at:
[`.github/workflows/build_export_template.yml`](file:///c:/Users/disaa/Desktop/Code/Wayfinder/.github/workflows/build_export_template.yml)

1. Push your repository to GitHub.
2. In your repo on GitHub, go to **Actions** → **Build Custom UI-Only Export Template** → **Run workflow**.
3. Once completed (takes ~6-8 minutes), download the `godot-ui-only-export-template-windows` artifact.
4. Unzip and place `windows_release_x86_64.exe` directly into this folder (`client/custom_templates/`).

### Option 2: Local SCons Compilation
If you have Visual Studio (with C++ Desktop workload) or MinGW installed:
1. Run [`tools/build_custom_template.bat`](file:///c:/Users/disaa/Desktop/Code/Wayfinder/tools/build_custom_template.bat).
2. It clones Godot source, compiles the release template using [`client/profiles/ui_only.build`](file:///c:/Users/disaa/Desktop/Code/Wayfinder/client/profiles/ui_only.build), and places `windows_release_x86_64.exe` here.

---

## How to Use the Custom Template in Godot

1. Open your project in Godot (`client` or your UI template).
2. Go to **Project** → **Export...**.
3. Select your **Windows Desktop** preset.
4. In the right-hand **Options** tab, scroll down to **Custom Template**:
   - Set **Release** to: `res://custom_templates/windows_release_x86_64.exe`
5. Click **Export Project**.
6. Your exported `.exe` is now tiny (~10–20 MB instead of ~110 MB)!
