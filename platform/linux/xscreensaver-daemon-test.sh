#!/usr/bin/env bash
#
# Drive the real xscreensaver daemon against the hack, inside a nested X server.
#
# smoke-test.sh stands in for xscreensaver: it creates a window itself and hands
# the id over the two ways the daemon and its settings dialog do. That covers the
# contract but not the daemon, so this script closes the last gap by running the
# actual `xscreensaver` binary, with its own configuration, and letting it fork
# the hack the way it does on a user's machine:
#
#   * a nested X server (Xephyr) so nothing touches the desktop this runs on,
#     and so the test is identical whether the outer session is X11 or Wayland;
#   * an isolated $HOME, because the daemon's configuration lives in
#     ~/.xscreensaver and rewriting a real one would be rude - this is also why
#     the package refuses to edit it (see packaging/aur/gibson-screensaver.install);
#   * the binary installed as `gibson-screensaver` on a private PATH, because the
#     daemon resolves the `programs:` line on PATH and the basename is what ties
#     the executable to its descriptor.
#
# What it proves that smoke-test.sh cannot: that the `programs:` line is spelled
# in a way xscreensaver-gfx accepts, that the window the daemon hands over is one
# the hack can actually adopt, and that a Vulkan surface works on that window.
#
# Usage:  xscreensaver-daemon-test.sh [path/to/gibson-app]   (default target/release/gibson-app)
#
# Needs:  xscreensaver, Xephyr (xorg-server-xephyr), xdpyinfo, and a Vulkan
#         driver. ImageMagick's `import`/`magick` are optional: when present the
#         script also captures the nested screen and asserts the pixels are not
#         a blank frame.
#
# Environment knobs: DAEMON_TEST_DISPLAY (default :77),
#         DAEMON_TEST_SECONDS (how long the saver is left running, default 14).
#
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
binary=${1:-$repo_root/target/release/gibson-app}
display=${DAEMON_TEST_DISPLAY:-:77}
run_seconds=${DAEMON_TEST_SECONDS:-14}

tmp=$(mktemp -d)
xephyr_pid=""
xss_pid=""

cleanup() {
  [ -n "$xss_pid" ] && kill "$xss_pid" 2>/dev/null || true
  [ -n "$xephyr_pid" ] && kill "$xephyr_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "::error::$*" >&2
  echo "daemon-test: FAIL: $*" >&2
  [ -f "$tmp/xscreensaver.log" ] && {
    echo "----- xscreensaver + hack log -----" >&2
    cat "$tmp/xscreensaver.log" >&2
  }
  exit 1
}

note() { echo "daemon-test: $*"; }

# ---------------------------------------------------------------- preflight

[ -x "$binary" ] || fail "no executable at $binary (build it with: cargo build --release -p gibson-app)"
command -v xscreensaver >/dev/null 2>&1 || fail "xscreensaver is not installed"
command -v Xephyr >/dev/null 2>&1 || fail "Xephyr is not installed (Arch: xorg-server-xephyr)"
command -v xdpyinfo >/dev/null 2>&1 || fail "xdpyinfo is not installed (Arch: xorg-xdpyinfo)"

# The basename must be gibson-screensaver: the daemon resolves `programs:` on
# PATH, and xscreensaver-settings finds the descriptor by basename.
install -Dm755 "$binary" "$tmp/bin/gibson-screensaver"
mkdir -p "$tmp/home"

# `mode: one` + `selected: 0` pins the one hack in `programs:` so activating the
# saver cannot pick something else. pointerHysteresis is deliberately enormous:
# a nested server forwards pointer motion from the outer desktop, and the daemon
# treats motion as user activity and unblanks - which killed the hack a second
# after it started, before it had finished creating its Vulkan surface.
cat >"$tmp/home/.xscreensaver" <<'EOF'
mode:			one
selected:		0
programs:		 gibson-screensaver \n\

timeout:		0:00:10
cycle:			0:00:00
lock:			False
splash:			False
verbose:		True
fade:			False
unfade:			False
dpmsEnabled:		False
pointerHysteresis:	10000
EOF

# ------------------------------------------------------------------ the run

Xephyr "$display" -screen 1024x768x24 -nolisten tcp >"$tmp/xephyr.log" 2>&1 &
xephyr_pid=$!
for _ in $(seq 1 100); do
  xdpyinfo -display "$display" >/dev/null 2>&1 && break
  kill -0 "$xephyr_pid" 2>/dev/null || break
  sleep 0.1
done
xdpyinfo -display "$display" >/dev/null 2>&1 || {
  cat "$tmp/xephyr.log" >&2
  fail "Xephyr never came up on $display"
}
note "Xephyr up on $display"

# The hack inherits the daemon's environment, which is the only way RUST_LOG
# reaches it - the daemon runs the `programs:` line through the shell.
env HOME="$tmp/home" DISPLAY="$display" PATH="$tmp/bin:$PATH" RUST_LOG=info \
  xscreensaver -no-splash >"$tmp/xscreensaver.log" 2>&1 &
xss_pid=$!
sleep 3
kill -0 "$xss_pid" 2>/dev/null || fail "the xscreensaver daemon exited immediately"

note "activating the saver through xscreensaver-command"
env HOME="$tmp/home" DISPLAY="$display" xscreensaver-command -activate \
  >>"$tmp/xscreensaver.log" 2>&1 || true
sleep "$run_seconds"

if command -v import >/dev/null 2>&1; then
  import -display "$display" -window root "$tmp/screen.png" 2>/dev/null || true
fi

env HOME="$tmp/home" DISPLAY="$display" xscreensaver-command -deactivate \
  >>"$tmp/xscreensaver.log" 2>&1 || true
sleep 2

# ------------------------------------------------------------------ verdict

grep -q 'forked "gibson-screensaver"' "$tmp/xscreensaver.log" \
  || fail "the daemon never forked gibson-screensaver - check the programs: line"
grep -q "xscreensaver host running on window" "$tmp/xscreensaver.log" \
  || fail "the daemon forked the hack but it never adopted the window it was given"
grep -q "gibson-render: frames=" "$tmp/xscreensaver.log" \
  || fail "the hack adopted the window but never reached the render loop"

window=$(sed -n 's/.*xscreensaver host running on window \([^ ]*\).*/\1/p' \
  "$tmp/xscreensaver.log" | tail -n 1)
adapter=$(sed -n 's/.*adapter AdapterInfo { name: "\([^"]*\)".*/\1/p' \
  "$tmp/xscreensaver.log" | tail -n 1)
note "adopted the daemon's window $window on adapter ${adapter:-unknown}"

# The daemon SIGTERMs the hack when it unblanks, so there is usually no exit
# summary to read a presented-frame count out of; the screenshot is what proves
# pixels reached the screen. Not fatal when ImageMagick is absent.
if [ -f "$tmp/screen.png" ] && command -v magick >/dev/null 2>&1; then
  # Captured with $( ) rather than `read`: ImageMagick's info: output has no
  # trailing newline, so `read` reports EOF-without-delimiter and returns
  # nonzero, which `set -e` turns into a silent abort right here.
  stats=$(magick "$tmp/screen.png" -format "%[fx:standard_deviation] %k" info:)
  stddev=${stats%% *}
  colors=${stats##* }
  note "nested screen: stddev $stddev, $colors distinct colours"
  # A saver that adopted the window and drew nothing leaves a single flat
  # colour. This is the failure the macOS saver actually shipped once.
  [ "$colors" -gt 1000 ] \
    || fail "the nested screen has only $colors distinct colours - the hack drew a blank frame"
  note "the nested screen is a real rendered frame, not a blank one"
else
  note "ImageMagick not available - skipped the pixel check"
fi

note "PASS"
