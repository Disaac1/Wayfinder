# Godot UI-Only Template

A stripped-down, optimized Godot 4 template tailored strictly for UI applications, tools, and desktop utilities (with all 3D and 2D game nodes excluded).

---

## What Makes This Template Different

1. **Pure UI Node Selection (Editor Feature Profile)**
   - Includes [`profiles/ui_only.profile`](file:///c:/Users/disaa/Desktop/Code/Wayfinder/templates/godot_ui_template/profiles/ui_only.profile).
   - In Godot, go to **Editor -> Manage Feature Profiles... -> Import** and select `ui_only.profile`.
   - When active, the 3D editor tab is hidden and the "Create New Node" dialog only displays `Control` UI nodes (`Button`, `LineEdit`, `Tree`, `Containers`, `Window`, `Dialogs`) and basic helpers (`Timer`, `HTTPRequest`, `AnimationPlayer`). All 3D (`Node3D`, `MeshInstance3D`, etc.) and 2D game objects (`Node2D`, `Sprite2D`, `TileMap`, `CollisionShape2D`, physics) are hidden.

2. **Ultra-Low Battery & CPU Consumption**
   - Configured with `application/run/low_processor_mode = true` in `project.godot`.
   - Godot only redraws frames when an event occurs (mouse click, typing, resize, or UI animation), preventing the GPU/CPU from spinning at 1000+ FPS on idle screens.
   - Compatibility renderer (`gl_compatibility`) for instant startup and lightweight memory footprint.
   - Window stretch set to `canvas_items` + `expand` for crisp desktop scaling.

3. **SCons Minimal Build Profile**
   - Includes [`profiles/ui_only.build`](file:///c:/Users/disaa/Desktop/Code/Wayfinder/templates/godot_ui_template/profiles/ui_only.build) for compiling custom lightweight Godot export templates via SCons:
     ```bash
     scons platform=windows target=template_release build_profile=profiles/ui_only.build disable_3d=yes
     ```
   - Drops engine binary size significantly by stripping out 3D physics, 3D rendering pipelines, OpenXR, and 2D physics.

4. **Modular Architecture & Pre-Built Components**
   - **`assets/themes/app_theme.tres`**: Sleek modern dark theme for panels, buttons, text fields, scrollbars, and progress bars.
   - **`scenes/components/modal_dialog.tscn`**: Reusable modal confirmation popup (`open(title, message, callback)`).
   - **`scenes/components/toast_notification.tscn`**: Non-blocking toast notification banner with auto-dismiss.
   - **`scenes/main.tscn`**: Responsive desktop application layout featuring navigation sidebar, dashboard, input controls, data table (`Tree`), and console logger.
