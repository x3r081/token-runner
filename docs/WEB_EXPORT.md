# Web export

How Token Runner is built for the browser, why each setting is what it is, and how to reproduce the build locally.

The published build lives at **https://x3r081.github.io/token-runner/** and is produced by `.github/workflows/pages.yml` on every push to `main` or `cursor/game-quality-overhaul-2ae1`.

Everything below is configured in two files — `export_presets.cfg` (`[preset.2]` "Web") and `project.godot`. No gameplay code and no part of the procedural asset pipeline was changed to make the web build work.

---

## 1. The nothreads variant is mandatory

`variant/thread_support=false`

Godot's threaded web export uses `SharedArrayBuffer`. Browsers only expose `SharedArrayBuffer` to a page that is **cross-origin isolated**, which requires the server to send two response headers on the document:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

**GitHub Pages cannot send those headers.** It serves static files with a fixed header set and offers no configuration — no `_headers` file, no `.htaccess`, no per-response control. So on Pages a threaded Godot build loads its `.wasm`, fails to construct a `SharedArrayBuffer`, and dies on the loading screen. The failure is not obvious from the page; it shows up as a console error and a progress bar that never finishes.

Building nothreads sidesteps the problem entirely: the engine runs single-threaded on the main thread and needs no special headers.

**How to tell which variant you built:** the threaded export emits `index.worker.js` next to `index.js`. The nothreads export does not. The CI job hard-fails if `index.worker.js` appears, because that file is the difference between a game that runs and a blank screen.

Cost of going single-threaded: resource loading and audio mixing share the main thread, so a hitch during a big region build is possible. Nothing in the game currently relies on threads.

## 2. Renderer override, and what it costs

```ini
# project.godot
rendering/renderer/rendering_method="forward_plus"
rendering/renderer/rendering_method.web="gl_compatibility"
```

The Forward+ renderer targets Vulkan/D3D12/Metal. In a browser the only graphics API is WebGL2, which Godot drives through its **Compatibility** renderer. The `.web` feature-tag suffix scopes the override to web only, so **desktop builds are byte-identical to before** — no shared setting was weakened to make the browser happy.

### Measured visual difference: effectively none

This was tested rather than assumed. A temporary probe scene loaded `scenes/world/world.tscn` under both renderers in the same window and dumped the framebuffer.

| Check | Forward+ | Compatibility |
|---|---|---|
| SubViewport `use_hdr_2d` | `true` | `true` |
| `GlowEnvironment` present (`world.gd`) | yes | yes |
| `glow_enabled` | `true` | `true` |
| Framebuffer format | float | float |

Comparing the two correctly-encoded frames pixel by pixel:

- World sample at (400, 700): **(116, 91, 86)** vs **(117, 92, 86)** — one least-significant bit apart.
- Mean absolute difference across the whole frame: **4.6 / 255**.
- Only **1.78%** of pixels differ by more than 24.

Bloom is visibly present in both: the lamp halo, the teal monitor bleed, and the glowing "Localhost" title all survive. **Nothing about the game's look is lost on the web.**

### One gotcha, and it is a screenshot artifact only

Under Compatibility, a framebuffer readback comes back **already sRGB-encoded**. `tools/quality_capture.gd` applies a `linear_to_srgb()` correction, which is correct for Forward+ but would **double-brighten** a Compatibility capture. If you ever run the QA capture tooling against a Compatibility frame, skip that correction. This affects captured PNGs, not what the player sees.

## 3. Audio compression: Quite OK Audio

All 41 files in `assets/audio/` are imported with `compress/mode=2` (Quite OK Audio) rather than the default `0` (uncompressed 16-bit PCM). This is recorded per-file in `assets/audio/*.wav.import`.

| | Size |
|---|---|
| Imported sample payload, PCM | 50.0 MB |
| Imported sample payload, QOA | **10.1 MB** (5.0x smaller) |
| `index.pck`, PCM baseline | 54,012,684 B (51.5 MB) |
| `index.pck`, QOA + exclude filter | **12,168,432 B (11.6 MB)** |

QOA is lossy but designed for game audio; on this material (procedurally generated chiptune-ish ambience, music and SFX) the artifacts are inaudible in context. Shaving 40 MB off a build that a player downloads over the open internet before the game starts is worth far more than the last fraction of a dB.

**No sample rate was changed.** `scripts/tools/music_generator.gd` still writes 44100 Hz and its on-disk output is unchanged — the compression happens at import time.

### The `.import` files must stay in git

`.gitignore` ignores `*.import` but carries an explicit exception:

```gitignore
*.import
!assets/audio/*.wav.import
```

Those `.import` files are **the only place `compress/mode=2` is recorded**. If they are missing from a checkout, Godot re-imports all 41 WAVs at the default uncompressed mode and the pck silently goes from 12 MB back to 54 MB. The build still succeeds — it is just four times heavier. Do not let those files fall out of the repo.

### Excluding non-shipping files

```ini
exclude_filter="docs/*,tests/*,tools/*"
```

Keeps roughly 3 MB of documentation screenshots plus the test scenes out of the shipped pck. This alone took the pck from 14.09 MB to 12.17 MB once combined with QOA.

## 4. Other Web preset settings

| Setting | Value | Why |
|---|---|---|
| `export_path` | `build/web/index.html` | Matches what CI uploads to Pages. |
| `html/canvas_resize_policy` | `2` (Adaptive) | The canvas tracks the browser window instead of sitting at a fixed size. |
| `html/head_include` | `<style>html, body { background-color: #05060E; }</style>` | The shell template's default page background is black; this makes the page match the game's VOID colour so there is no flash of black around the canvas. |
| `application/boot_splash/bg_color` | VOID `#05060E` | Baked into the loading overlay by the template (`#status { background-color: #05060e }`). |
| `variant/extensions_support` | `false` | No GDExtensions in this project. |
| `progressive_web_app/enabled` | `false` | No offline/installable requirement. |

The browser tab title comes free from `application/config/name` → "Token Runner: Ship Before Reset".

## 5. Exporting locally

Requires Godot 4.7.2 **and** the matching export templates (Editor → Manage Export Templates, or drop the `.tpz` contents into `~/.local/share/godot/export_templates/4.7.2.stable/`).

```bash
cd token-runner
godot --headless --path . --script scripts/tools/run_generate.gd   # procedural assets
godot --headless --path . --import                                  # import (run twice on a fresh checkout)
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

### You cannot open index.html directly

`file://` URLs fail — the browser blocks the `fetch()` of the `.wasm` and `.pck` under its cross-origin rules. Serve it over HTTP:

```bash
python3 -m http.server 8000 --directory build/web
# then open http://localhost:8000/
```

Confirm `index.wasm` comes back as `Content-Type: application/wasm`; Godot's loader refuses to stream-compile it otherwise.

### Expected output

| File | Size |
|---|---|
| `index.wasm` | 39,514,754 B |
| `index.pck` | 12,168,432 B |
| `index.js` | 279,815 B |
| `index.png` (boot splash) | 21,443 B |
| `index.audio.worklet.js` | 7,298 B |
| `index.html` | 5,519 B |
| `index.apple-touch-icon.png` | 3,850 B |
| `index.audio.position.worklet.js` | 2,973 B |
| `index.icon.png` | 907 B |

About 52 MB total, ~20 MB over the wire once the server gzips it (the wasm compresses to ~10.1 MB, the pck to ~10.2 MB).

If `index.wasm` is missing after an export that printed no obvious error, **the export templates are not installed** — that is the one failure mode that looks like success. CI checks for exactly this.

## 6. What CI adds on top

`.github/workflows/pages.yml`:

- Downloads Godot 4.7.2 headless and the 4.7.2 export templates from the official GitHub release, installing the templates' contents (not the `templates/` folder itself) into `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Runs generate → import (twice, first pass allowed to fail) → export.
- **Verifies the export produced a real build**: `index.html`/`index.js`/`index.wasm`/`index.pck` all non-empty, `index.wasm` over 1 MB and starting with the `\0asm` magic bytes, and no `index.worker.js`. Any of these fails the job with a `::error::` annotation rather than deploying a broken page.
- Writes `.nojekyll` into `build/web`. Without it Pages runs the output through Jekyll, which strips files and directories whose names begin with an underscore.
- Uploads with `actions/upload-pages-artifact@v3` and deploys in a separate job with `actions/deploy-pages@v4`.

The existing `.github/workflows/ci.yml` (test suite plus the Linux export) is untouched and still runs on its own triggers.

**Remember the one-time manual step:** Settings → Pages → Build and deployment → Source = "GitHub Actions". Until that is set, the deploy job fails no matter how good the build is.
