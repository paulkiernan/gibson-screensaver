# Hack the Gibson — Linux xscreensaver host

`gibson-app` doubles as an xscreensaver "external window" hack: xscreensaver
creates a window, hands its XID to the process, and the process renders the
flythrough into that window at ~60 Hz until xscreensaver destroys it.

How the XID arrives differs between the two things that launch a hack, and
both paths matter:

- **The daemon** (`xscreensaver` itself) runs the `programs:` line from
  `~/.xscreensaver` verbatim through the shell and passes the window only in
  the `XSCREENSAVER_WINDOW` environment variable. It never appends a
  `--window-id` argument.
- **The settings dialog** (`xscreensaver-settings`) appends
  `--window-id 0x<id>` to the command line it launches for the embedded
  preview, and also sets `XSCREENSAVER_WINDOW` (it does the former so that a
  third-party saver which ignores the window would pop up its own full-screen
  window instead of failing).

`gibson-app` handles both: it selects the X11 host when `--window-id <xid>`
is given or when `XSCREENSAVER_WINDOW` is set. That is why the descriptor
carries no `<command>` element — anything listed there is added verbatim to
the `programs:` line and would break one path or the other. See the comment
at the top of [`gibson-screensaver.xml`](gibson-screensaver.xml).

## Why the name is `gibson-screensaver`, not `gibson`

Upstream xscreensaver has shipped its own, unrelated `gibson` hack since
version 5.44 (written by Jamie Zawinski in 2020, and also about the 1995
film). Installing anything of ours under that name collides twice over:

- Arch's `xscreensaver` package already owns its `gibson` executable, the
  matching `gibson.xml` in the xscreensaver config directory, and
  `/usr/share/man/man6/gibson.6.gz`, so installing our descriptor at that path
  is a pacman conflicting-files error (and a manual `cp` silently clobbers
  another package's file).
- xscreensaver prepends its own hacks directory to `$PATH` when resolving the
  `programs:` list, so a second `gibson` on `PATH` would lose to upstream's
  anyway.

The name is not cosmetic: `xscreensaver-settings` finds a hack's descriptor
by taking the basename of the program and looking for
`<hack-configuration-path>/<basename>.xml`. The installed executable and the
descriptor therefore have to agree, and both are `gibson-screensaver`.

## Install

1. Build the binary:

       cargo build --release -p gibson-app
       install -Dm755 target/release/gibson-app ~/.local/bin/gibson-screensaver

   The basename must be `gibson-screensaver`; `~/.local/bin` just has to be on
   `PATH`.

2. Install the hack descriptor so the xscreensaver settings dialog knows the
   options and can find the matching program:

       sudo install -Dm644 platform/linux/gibson-screensaver.xml \
            /usr/share/xscreensaver/config/gibson-screensaver.xml

3. Add a `programs:` line to `~/.xscreensaver` (create it with
   `xscreensaver-demo` first if it does not exist). No arguments:

       programs: gibson-screensaver

   `xscreensaver` resolves `gibson-screensaver` on `PATH`; pass an absolute path
   instead if you installed it elsewhere, e.g.

       programs: /home/you/.local/bin/gibson-screensaver

4. Pick "Hack the Gibson" in `xscreensaver-demo` and set a blanking mode /
   timer as usual. The demo's Settings dialog exposes "Fly speed" and "Pulse
   streaks"; everything else is configured in `~/.config/gibson-screensaver/gibson.toml`
   (created with defaults and comments on first run).

The X11 host renders through wgpu's Vulkan backend into the window
xscreensaver provides, so it runs under a normal X11/XWayland session.

## Wayland

xscreensaver's architecture is X11-only. On a Wayland session use `swayidle`
(compatible with `sway`/`hyprland`/`wayfire`/...) plus the plain fullscreen
window mode instead:

    swayidle -w timeout 600 'gibson-app --fullscreen' resume 'pkill gibson-app'

or run `gibson-app --fullscreen` manually and quit with Esc or Q.

## Status

**Verified on real hardware with a real GPU, and under the real xscreensaver
daemon.** The record, so the claim can be re-checked rather than trusted:

| | |
|---|---|
| Host | Arch Linux, kernel 7.0.9-zen2-1-zen, KDE/Wayland session with XWayland |
| GPU | NVIDIA GeForce GTX 1080, proprietary driver 580.159.04, `DiscreteGpu`, Vulkan backend |

- `smoke-test.sh` on that machine: both launch paths adopted the window and
  presented **201** and **219** frames, 0 skipped, exiting cleanly when the
  window went away.
- `xscreensaver-daemon-test.sh`: the real `xscreensaver` binary forked the hack
  onto its own window, the hack adopted it, and the nested screen captured
  405,037 distinct colours — a drawn frame, not a blank one.
- Offscreen `--snapshot` at 1280x720: 600 frames stepped, 491,868 distinct
  colours.
- `cargo test --workspace --exclude gibson-web`: 119 tests pass, including the
  `gibson-core`/`gibson-render` tests that need a graphics adapter and skip
  themselves when there is none.

CI still runs [`smoke-test.sh`](smoke-test.sh) under Xvfb with a software
rasteriser on every push, which is what catches regressions; it covers both
ways a hack is launched: it creates a real X window and hands its id to the
built binary through `XSCREENSAVER_WINDOW` the way the daemon does, then does
it again with `--window-id <id>` the way the settings dialog's preview does.
Each case must adopt the window, present at least one frame (asserted from the
renderer's own presented-frame counter, not from "it did not crash"), and exit
cleanly when the window is destroyed. The script also checks the descriptor
against the binary: the name matches the installed basename, there is no
`<command>` element, every slider arg has its `%` value placeholder, and every
switch the descriptor can emit is accepted by `--help`.

Still not covered by either: multi-GPU and Optimus-style hybrid setups, real
multi-head Xinerama/RANDR layouts (the runs above were single-screen), and
non-NVIDIA drivers on real hardware. If it fails on your machine, report the
`RUST_LOG=info XSCREENSAVER_WINDOW=<xid> gibson-screensaver` log output.

### Known limitation: the X11 backend forced on a Wayland session

Running `--fullscreen` with the X11 backend *forced* on a Wayland session
(`WAYLAND_DISPLAY` unset while `DISPLAY` points at XWayland) never presents a
frame: the surface comes back `Outdated` from every acquire, and the app exits
with `first frame failed: ... surface acquire failed after reconfigure`. This
needs no workaround in practice and none is applied:

- on a Wayland session winit selects the Wayland backend by itself, and
  `--fullscreen` there runs at full rate;
- on a real X11 session the X11 backend's `--fullscreen` runs at full rate
  (checked against a nested Xephyr server, 51 fps, 0 skipped);
- the xscreensaver host path is unaffected either way, because xscreensaver
  hands over a window instead of asking for a fullscreen one.

The fast, explicit failure is deliberate: a screensaver that draws nothing must
say so rather than show a black screen.

## Testing it yourself

Two `make` targets, both of which build the release binary first:

    make smoke-linux    # the CI runtime test: needs $DISPLAY, a C compiler, a Vulkan driver
    make daemon-linux   # the real daemon, in a nested X server: needs xscreensaver + Xephyr

`smoke-linux` runs [`smoke-test.sh`](smoke-test.sh), which compiles a tiny X
client (`x11-test-window.c`), has it create and map a window, prints the window
id, runs the hack against that window twice (once through the environment, once
through `--window-id`), destroys the window, and checks that the hack exited
cleanly after presenting frames. It prints the window id, the adapter line, and
the presented/skipped counters either way, and exits non-zero with the hack's
whole log on any failure. Any X server will do, including an Xvfb instance —
note that the test window is `override_redirect`, like xscreensaver's own saver
window, so it does not depend on a window manager being present or absent.

`daemon-linux` runs [`xscreensaver-daemon-test.sh`](xscreensaver-daemon-test.sh),
which is the only test that involves xscreensaver itself: it starts a nested X
server, points a throwaway `$HOME` at a `~/.xscreensaver` whose `programs:` line
is just `gibson-screensaver`, lets the daemon fork the hack, and asserts that
the hack adopted the window the daemon gave it and that the nested screen holds
a real rendered frame.
