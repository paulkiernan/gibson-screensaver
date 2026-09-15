# Hack the Gibson - Linux xscreensaver host

`gibson-app` doubles as an xscreensaver "external window" hack: xscreensaver
creates a window, hands its XID to the process, and the process renders the
flythrough into that window at ~60 Hz until xscreensaver destroys it.

Two things launch a hack and they hand the window over differently, so both
paths have to work:

- **The daemon** runs the `programs:` line from `~/.xscreensaver` verbatim
  through the shell and passes the window only in `XSCREENSAVER_WINDOW`; it
  never appends a `--window-id` argument.
- **The settings dialog** (`xscreensaver-settings`) appends `--window-id 0x<id>`
  for the embedded preview and sets `XSCREENSAVER_WINDOW` as well, so a
  third-party saver that ignores the window pops up its own full-screen window
  instead of failing.

`gibson-app` handles both: it selects the X11 host when `--window-id <xid>` is
given or when `XSCREENSAVER_WINDOW` is set. That is why the descriptor carries
no `<command>` element - anything listed there is added verbatim to the
`programs:` line and would break one path or the other. See the comment at the
top of [`gibson-screensaver.xml`](gibson-screensaver.xml).

## Why the name is `gibson-screensaver`, not `gibson`

Upstream xscreensaver has shipped its own, unrelated `gibson` hack since
version 5.44 (written by Jamie Zawinski in 2020, and also about the 1995 film),
so installing ours under that name collides twice over. Arch's `xscreensaver`
package already owns its `gibson` executable, the matching `gibson.xml` and
`/usr/share/man/man6/gibson.6.gz`, so our descriptor at that path is a pacman
conflicting-files error - and a manual `cp` silently clobbers another package's
file. xscreensaver also prepends its own hacks directory to `$PATH` when
resolving the `programs:` list, so a second `gibson` on `PATH` would lose to
upstream's anyway.

The name is not cosmetic: `xscreensaver-settings` finds a hack's descriptor by
taking the basename of the program and looking for
`<hack-configuration-path>/<basename>.xml`. The executable and the descriptor
have to agree, and both are `gibson-screensaver`.

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

I've run this host on real hardware - Arch Linux with a GeForce GTX 1080 on
NVIDIA's 580.159.04 driver, in a KDE/Wayland session with XWayland - and under
the real `xscreensaver` daemon rather than a stub: the daemon forks the hack
onto a window of its own, and the hack adopts it and draws. CI runs the same
smoke test under Xvfb on every push, which is what catches regressions. Not
covered: multi-GPU and Optimus-style hybrid setups, real multi-head
Xinerama/RANDR layouts, and non-NVIDIA drivers on real hardware. If it fails on
your machine, report the `RUST_LOG=info XSCREENSAVER_WINDOW=<xid>
gibson-screensaver` log output.

### Known limitation: the X11 backend forced on a Wayland session

Running `--fullscreen` with the X11 backend *forced* on a Wayland session
(`WAYLAND_DISPLAY` unset while `DISPLAY` points at XWayland) never presents a
frame: the surface comes back `Outdated` from every acquire, and the app exits
with `first frame failed: ... surface acquire failed after reconfigure`. That
fast, explicit failure is the point - a screensaver that draws nothing should
say so rather than show a black screen - and it needs no workaround in
practice. On a Wayland session winit selects the Wayland backend by itself and
`--fullscreen` runs at full rate; on a real X11 session the X11 backend's
`--fullscreen` runs at full rate too (checked against a nested Xephyr server,
51 fps, 0 skipped); and the xscreensaver path is unaffected either way, because
xscreensaver hands over a window rather than asking for a fullscreen one.

## Testing it yourself

Two `make` targets, both of which build the release binary first:

    make smoke-linux    # the CI runtime test: needs $DISPLAY, a C compiler, a Vulkan driver
    make daemon-linux   # the real daemon, in a nested X server: needs xscreensaver + Xephyr

`smoke-linux` runs [`smoke-test.sh`](smoke-test.sh): it compiles a tiny X client
(`x11-test-window.c`), has it create and map a window, runs the hack against
that window twice - once through the environment, once through `--window-id` -
then destroys the window and checks the hack exited cleanly after presenting at
least one frame. It prints the window id, the adapter line and the
presented/skipped counters either way, and exits non-zero with the hack's whole
log on any failure. The script also cross-checks the descriptor against the
binary: the name matches the installed basename, there is no `<command>`
element, every slider arg has its `%` placeholder, and every switch the
descriptor can emit is accepted by `--help`. Any X server will do, including an
Xvfb instance - the test window is `override_redirect`, like xscreensaver's own
saver window, so it does not need a window manager either way.

`daemon-linux` runs [`xscreensaver-daemon-test.sh`](xscreensaver-daemon-test.sh),
the only test that involves xscreensaver itself: it starts a nested X server,
points a throwaway `$HOME` at a `~/.xscreensaver` whose `programs:` line is
just `gibson-screensaver`, lets the daemon fork the hack, and asserts that the
hack adopted the window the daemon gave it and that the nested screen holds a
real rendered frame.
