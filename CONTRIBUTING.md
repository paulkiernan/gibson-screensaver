# Contributing to Hack the Gibson

Thanks for looking. This is a spare-time project, and it is arranged so a change can be
built and run on **one** platform without owning all five: the renderer is shared, and
the hosts on top of it are thin. If anything below turns out to be wrong, that is a bug
in this file, and a pull request against it is welcome.

## Fastest path to pixels

```sh
git clone https://github.com/paulkiernan/gibson-screensaver
cd gibson-screensaver
cargo run --release -p gibson-app
```

A window opens on the flythrough; Esc or Q quits - the whole first-run story on macOS,
Linux and Windows. `--fullscreen` and `--help` (the whole flag list) are the other two
worth knowing, and `RUST_LOG=info` logs to stderr. Settings live in
`<config-dir>/gibson-screensaver/gibson.toml`, written with defaults on first run and
clamped on load.

`--release` matters more here than most projects: the renderer is fill-rate-bound, and a
dev build leaves the workspace's own crates unoptimized (dependencies are already at
`opt-level = 2` in the root `Cargo.toml`, which is what makes the wgpu stack tolerable to
build in debug).

Before you push, run `make check`. CI also gates formatting, Clippy on the native
workspace and on the wasm crate, and the commit messages, each a target of its own:
`make fmt-check`, `make lint`, `make lint-wasm`, `make commits`.

## Prerequisites

| To do this | You need |
| --- | --- |
| Build anything | A Rust toolchain pinned to one **exact version** (`1.98.1` as this is written) - never `cargo +nightly`. Two pins name it and MUST agree: `rust-toolchain.toml` (rustup) and `.tool-versions` (asdf, `asdf plugin add rust && asdf install`), either of which selects it automatically inside the repository; a distro `cargo` (Arch's `rust`) reads *neither*. See [Bumping Rust](#bumping-rust). |
| Format and lint the way CI does | `rustup component add rustfmt clippy` |
| Build the web bundle | `rustup target add wasm32-unknown-unknown`, then `cargo install wasm-pack --locked`. CI installs the prebuilt wasm-pack 0.15.0. |
| Build a universal macOS screen saver (arm64 + x86_64) | `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, on macOS |
| Build the macOS screen saver at all | Command Line Tools (`xcode-select --install`); **Xcode is not required.** `platform/macos/Makefile` compiles the Rust staticlib, links the Swift host with `swiftc`, `lipo`s the slices, wraps the `.saver` bundle and ad-hoc signs it. |
| Build on Linux | Debian/Ubuntu: `libx11-dev libxkbcommon-dev libxkbcommon-x11-dev libwayland-dev`; Arch: those headers come with `libx11 libxkbcommon libxkbcommon-x11 wayland`. Either way winit's wayland stack needs the headers at build time (x11-dl dlopens libX11 at runtime), plus a Vulkan driver to run anything - wgpu's Linux backend set is Vulkan only, so no driver means `mesa-vulkan-drivers` (Debian) or `vulkan-swrast` (Arch). |
| Run the Linux runtime tests | `make smoke-linux` needs an X server on `$DISPLAY` (an `xvfb-run` wrapper is enough), a C compiler and `python3`; `make daemon-linux` also needs `xscreensaver` and `Xephyr` (Arch: `xorg-server-xephyr`) and uses ImageMagick for its pixel check when present. |
| Keep `target/` from eating your disk | `CARGO_PROFILE_DEV_DEBUG=line-tables-only` - debug info, not the test binaries, is what costs gigabytes, and line tables are all a backtrace needs. `make check` sets it. |

The saver defaults to `ARCHS="arm64 x86_64"`; with only one of the two targets
installed, build your own: `make -C platform/macos ARCHS=arm64`.

## The crate map

| Crate | What lives there |
| --- | --- |
| `gibson-types` | The **frozen** contract every other crate compiles against: world constants (`TOWER_PITCH`, `FLOOR_TILE_UNITS`, `ATLAS_*`, `FOG_*`, `MAX_ON_SCREEN_PIXELS`), `Settings`, `Palette`, the `#[repr(C)]` + `Pod` GPU instance structs, `AtlasImage`, `FloorMap`, `FrameData`. |
| `gibson-scene` | The simulation: the closed Catmull-Rom flight path (39 waypoints from the 2015 C++ original), camera banking ported from the SceneKit fork, city placement with per-tower heights capped by real path clearance, lane pulse streaks, block highlights, the siege spread. `Scene::update` / `Scene::frame` are the per-frame API. |
| `gibson-atlas` | The procedural text atlas: 64 layers of 256x768 RGBA, 32 tower-face panels with two text variants each, drawn with fontdue from the embedded IBM Plex Mono and Michroma fonts in `assets/fonts/`. |
| `gibson-floor` | The procedural 96x96 toroidal circuit board the towers sit on as integrated circuits: packages with pin rings, strictly planar octilinear routing with via-pair layer changes, power rails, bus bundles, ground pour, silkscreen. |
| `gibson-render` | The wgpu 30 frame graph and the WGSL shaders in `src/shaders/`: SDF floor, instanced translucent towers with in-shader per-block animation, additive beams, the bloom chain, depth-reprojected motion blur, the ACES composite, the Lottes-style CRT pass. `crates/gibson-render/tests/render.rs` is the acceptance suite. |
| `gibson-core` | The host-facing `Gibson` facade over `SurfaceTarget::{Window, Raw, Offscreen}`: `frame()` for continuous rendering, `snapshot()` for one offscreen still, and the present/skip counters. |
| `gibson-app` | The winit desktop host, `--snapshot`, the TOML config, and the two screensaver hosts: the Windows `.scr` protocol (`/s`, `/p <hwnd>`, `/c`) and the Linux xscreensaver host (`--window-id <xid>` or `$XSCREENSAVER_WINDOW`). |
| `gibson-web` | The wasm-bindgen entry point: canvas boot, URL query parameters, the `requestAnimationFrame` loop. wasm-only (`#![cfg(target_arch = "wasm32")]`). |
| `gibson-ffi` | The C ABI bridge the Swift screen saver links as a staticlib; header in `platform/macos/include/gibson_ffi.h`. |

## Running things

Each host is one `make` away: `make web` (then serve `web/pkg` over HTTP, since the wasm
module needs response headers), `make saver` and `make install-saver`, and `make snapshot`,
which renders `docs/screenshots/lane.png`. Flags and settings are in the README.

### Deterministic stills

```sh
cargo run --release -p gibson-app -- \
  --snapshot out.png --size 1920x1080 --time 12 --seed 42
```

One frame offscreen, then exit: no window, no pixel cap, byte-identical output for a
fixed `--seed`. Always pass `--seed`, because the default `seed = 0` means "derive one
from the clock", so a still without it cannot be compared against anything, not even
itself a minute later. `--time` and `--palette normal|siege|cycle` pick where along the
loop and in which colour treatment it is taken. A visual change gets two of these, before
and after, at the same seed; `docs/film-reference.md` ends with the checks it is graded
against.

### Tests

```sh
make check   # cargo test --workspace --exclude gibson-web, line-tables-only debuginfo
make test    # the same command without the debuginfo prefix
```

`--exclude gibson-web` is there because that crate is wasm-only: on a native host it
compiles to an empty rlib, so a native run would prove nothing about it - check a web
change with `make web`, which is what CI's `wasm` job does. The debuginfo prefix,
`CARGO_PROFILE_DEV_DEBUG=line-tables-only`, keeps a full run from costing gigabytes of
`target/`.

CI runs a narrower set on Windows and Linux
(`cargo test -p gibson-scene -p gibson-atlas -p gibson-floor -p gibson-app`) because
hosted runners have no GPU, and the full workspace on macOS. The renderer's tests need a
real adapter; without one each prints `skipped: no graphics adapter/device available` and
passes. The image-producing tests sit behind an environment variable so a normal run
stays fast:

```sh
GIBSON_RENDER_PROBE=1 CARGO_PROFILE_DEV_DEBUG=line-tables-only \
  cargo test -p gibson-render --test render probe_ -- --nocapture
```

They write 1080p PNGs into `docs/scratch/` (gitignored): the floor from above, a face
study, a populated frame, the siege waves, panel legibility. `GIBSON_RENDER_PROBE_OUT`
redirects the path and `GIBSON_RENDER_CRT` sets the CRT amount.

## Conventions that will get a pull request sent back

Each of these has cost someone real debugging time. They are not style preferences.

### `gibson-types` is a frozen contract

Every crate compiles against `gibson-types`, and the renderer reads its
`#[repr(C)]`/`Pod` structs out of GPU memory against a matching WGSL declaration in
`crates/gibson-render/src/shaders/`. A change to it is a dedicated amendment step, never
run alongside feature work: the contract change and every crate it forces to change land
in one reviewable commit, marked as a breaking change (`feat(types)!: ...` plus a
`BREAKING CHANGE:` footer), the pattern its module docs set out for the three amendments
so far.

The grid conventions - pitch 30, towers at `x = 15 (mod 30)` / `z = 0 (mod 30)`, lanes
at `x = 0` and `z = 15`, `FLOOR_TILE_UNITS = 240`, exactly eight pitches - are what let
the floor generator place grid-exact keep-out zones under tower footprints, and the 39
flight-path waypoints are film-era artifacts: never nudge them for a geometry change,
cap the geometry instead, as the city samples real path clearance per tower.

### Renderer work stays inside the WebGL2 envelope

The web build falls back to WebGL2 where a browser has no WebGPU, so this binds all
renderer work:

- no storage buffers and no compute shaders;
- one uniform buffer per binding, 16 KiB or less;
- per-instance data through `VertexStepMode::Instance` vertex buffers;
- no MSAA, and no vertex-shader texture reads;
- no `textureLoad` on a depth texture - naga's GLSL backend rejects it outright, which
  is why the depth the motion blur reprojects from rides in an `R32Float` colour
  attachment;
- every derivative call (`fwidth`, implicit-LOD sampling) in uniform control flow;
- no pipeline whose colour targets differ in blend or write mask (`INDEPENDENT_BLEND`
  does not exist in WebGL2);
- resource shapes that fit `Limits::downlevel_webgl2_defaults()`.

That list is repeated, with the reasons, at the top of
`crates/gibson-render/src/lib.rs`. Neither `cargo test` nor the wasm build catches a
violation: it fails at run time, in a browser, on someone else's machine.

The same goes for wall-clock time: on `wasm32-unknown-unknown`,
`std::time::Instant::now()` and `SystemTime::now()` do not return a wrong value - they
`panic!("time not implemented on this platform")`, and one added for a debug log line
once blackened the whole web build. `gibson-core::time_derived_seed` is the pattern to
copy where a clock is genuinely needed.

### A test has to be able to fail

A counter that reports success while nothing happened is worse than no counter at all:
this project has shipped one that counted *skipped* frames as `41000 fps`, and a macOS
saver that was black while "did not crash" was read as "it drew". Assert on what a
consumer observes - pixels, presented frames, exit codes, parsed values - not on the fact
that a function was called or a field was copied.

### Formatting and lints

`rustfmt.toml` is authoritative and almost empty: `edition = "2021"` to match the
workspace and nothing else, because rustfmt's defaults are the Rust Style Guide. No
nightly-only key (`imports_granularity`, `group_imports`, `wrap_comments`, ...) is set
there: on the pinned stable toolchain rustfmt warns about those and ignores them.

```sh
make fmt         # cargo fmt --all
make fmt-check   # cargo fmt --all --check - what CI runs
make lint        # cargo clippy --workspace --exclude gibson-web --all-targets
make lint-wasm   # the same for gibson-web, on wasm32
```

The whole workspace was reformatted once, in a single commit that changes nothing but
whitespace. `.git-blame-ignore-revs` names it, and GitHub honours that file on its own;
locally, run this once and `git blame` will skip it too:

```sh
git config blame.ignoreRevsFile .git-blame-ignore-revs
```

The lint *levels* are neither CI flags nor `#![deny]` attributes: they are the root
`Cargo.toml`'s `[workspace.lints]` table, which every member opts into with
`[lints] workspace = true`. `clippy::all` (correctness, suspicious, style, complexity,
perf) and rustc's `unused` group are `deny` there, so clippy fails on a warning with no
`-D warnings` anywhere, and your machine reports what CI reports. An `#[allow]` is fine
where the lint is wrong, but it has to say why.

`make lint` skips `gibson-web`, which is `#![cfg(target_arch = "wasm32")]` and so
compiles to nothing on a native host; lint its real code with the target installed once:

```sh
rustup target add wasm32-unknown-unknown
make lint-wasm
```

### Bumping Rust

`rust-toolchain.toml` pins the compiler by exact version (`1.98.1` as this is written),
and rustup reads it in the checkout, so CI, the Makefile and your shell all get the same
`rustc` and `clippy`. That is what makes `deny` in `[workspace.lints]` safe: clippy grows
new lints every release, and on a floating `stable` the first one to fire lands on
whichever pull request is open.

1. Install the toolchain and point **both** pins at it: `rust-toolchain.toml` for rustup,
   `.tool-versions` for asdf, and they MUST name the same version.

   ```sh
   # rustup
   rustup toolchain install <version> --component rustfmt,clippy
   # or asdf
   asdf install rust <version> && asdf local rust <version>
   ```
2. Run the whole gate: `make fmt-check`, `make lint`, `make lint-wasm`, `make check`,
   and the snapshot command from "Deterministic stills" with the same `--seed` - a new
   compiler is a change to the program that renders the pixels.
3. Fix, or narrowly allow with a comment, whatever the new Clippy found *in that commit*.
4. Check the new version is not ahead of what the packaging builds with. Only the AUR
   `PKGBUILD` compiles anything, using whichever `cargo` the packager has: Arch's distro
   `cargo` ignores `rust-toolchain.toml`, while rustup or asdf gets the pin (Scoop and
   Homebrew download prebuilt assets). Arch ships **1.95.0** against the pinned **1.98.1**
   as this is written, and the package builds on both, since nothing declares a
   `rust-version` or uses anything newer. One trap: an asdf `rust` plugin with no version
   set for the build directory puts a `rustc` shim on `PATH` that refuses to run (`No
   version is set for command rustc`) and fails the build midway through dependencies -
   set `ASDF_RUST_VERSION=<version>` there, or build in a chroot.

### Commit messages: Conventional Commits, required

```text
type(scope): subject
```

- Imperative mood - `stop the leak`, not `stopped` or `stops`.
- Lower case, no trailing period, subject under about 72 columns.
- Body wrapped at 72 columns, saying *why*: the diff already says what.
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
  `chore`, `revert`.
- Scopes are the crate or host: `types`, `scene`, `atlas`, `floor`, `render`, `core`,
  `app`, `web`, `ffi`, `macos`, `linux`, `windows`, plus `packaging`, `ci` and `docs`.
  Omit the scope when a change is genuinely repo-wide.
- A breaking change puts `!` after the scope - or straight after the type when there is
  no scope, `feat!: ...` - and explains itself in a `BREAKING CHANGE:` footer. An
  amendment to the frozen `gibson-types` contract is precisely that case, since every
  crate compiles against it.

CI checks the shape in the `lint` job: only the commits a pull request adds, starting at
the merge base, so a pull request cannot fail on a message it did not write. It also
checks what a push adds, where the range is `github.event.before..github.sha` (a new or
force-pushed branch falls back to the pushed commit alone), and the pull request title,
since a squash merge takes the title as the commit subject. An unknown type or scope is
rejected with the allowed set in the failure message. The same gate runs locally:

```sh
make commits                  # the commits this branch adds on top of origin/main
make commits BASE=origin/release
```

That is `scripts/check-commit-messages.sh <rev-range>`; with no argument it reads
subjects from stdin, one per line - which is how you check a message before committing
it. `git config commit.template .gitmessage` gets the type and scope lists into your
editor.

### No emoji

In code, docs, commit messages and issue reports. This is a running house rule, and it
applies to the files in this scaffolding too.

Security issues do not go in a public issue - [SECURITY.md](SECURITY.md) says what is in
scope and how to report privately. All participation is covered by
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

Licensed GPL-3.0-or-later; by contributing you agree your work is too. The bundled fonts
are SIL Open Font License (see `assets/fonts/OFL-*.txt`).
