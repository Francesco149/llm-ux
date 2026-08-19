# QUEUED TASK (for a cheaper agent): drop the D3D11 backend

Decision (2026-08-19): OpenGL 3.3 + raylib now resizes smoothly on Windows via
the subclass shim in `editor/src/main.cpp` (`cf_resize_subclass_proc`). OGL is
shipped on every platform; the standalone D3D11 backend is obsolete.

## Remove
- `templates/raylib/editor/src/main_d3d11.cpp` (2900-line duplicate engine)
- `templates/raylib/editor/src/winclip.c` ONLY IF nothing else uses it —
  check first: `main.cpp` uses `win_*` helpers on both backends. KEEP winclip.c.
- Makefile (`editor/Makefile`): targets `win-d3d11`, `package-d3d11`,
  `zip-d3d11`, `win-run-d3d11`; vars `WIN_D3D11_*`, `D3D11_SRC_OBJS`;
  `zip-all` → only linux+win; clean rule references.
- Workflow (`.github/workflows/nightly.yml`): build-windows job builds only
  `win package zip-win`; release job notes drop the d3d11 zip bullet and
  upload; artifact `cubeforge-d3d11-win64` removed.
- Docs: `ORIENTATION.md` (root + template) — remove "Triple Backend"/D3D11
  claims, state single-backend OGL 3.3 with in-loop resize rendering.
  `docs/WINDOWS_COMPAT_AND_WIN7.md` and template ORIENTATION.md mentions.
- `imgui.ini` may contain d3d11 window layout entries — harmless, ignore.

## Do NOT touch
- `editor/src/main.cpp` resize subclass + `present_no_poll` + own-dt logic.
- `poc_resize/` (evidence: poc_min/poc_imgui/poc_lua — keep as reference).

## Verify after removal
- `nix develop -c make -C editor linux test` green
- `nix develop -c make -C editor win package zip-win` green
- `nix build` (default package) green
- grep -ri d3d11 returns only poc_resize/docs history notes
