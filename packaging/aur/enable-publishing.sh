#!/usr/bin/env bash
#
# Finish the AUR setup and publish both packages.
#
# This exists because the last step of getting onto the AUR is not something a
# workflow can do for itself: it needs an AUR account, and an account needs a
# human at a registration form. When that form was closed (September 2026, a
# wave of automated signups) everything else was already done, so this script is
# the "pick it up here" half.
#
# It does three things, and it is safe to run again if any of them fails
# half-way:
#
#   1. makes sure there is a key, and tells you to put the public half on the
#      AUR account if the private half cannot authenticate yet;
#   2. puts the private half in the GitHub repository's secrets, which is what
#      switches the push on in .github/workflows/aur.yml;
#   3. runs that workflow for real and reports whether both packages landed.
#
# It does NOT poll the registration page. Arch asks people not to, and it would
# not tell you anything sooner than aur-general or the Arch news feed.
#
#   https://lists.archlinux.org/mailman3/lists/aur-general.lists.archlinux.org/
#   https://archlinux.org/feeds/news/
#
# Usage:  enable-publishing.sh [--key PATH] [--check]
#
#   --key PATH   private key to use, default ~/.ssh/aur_ed25519
#   --check      only report where things stand; change nothing
#
# Needs: ssh, gh (logged in, with access to this repository).

set -euo pipefail

key=${AUR_SSH_KEY:-$HOME/.ssh/aur_ed25519}
check_only=false
packages=(gibson-screensaver gibson-screensaver-bin)

while [ $# -gt 0 ]; do
  case $1 in
    --key) key=${2:?--key needs a path}; shift 2 ;;
    --check) check_only=true; shift ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { echo "aur-setup: $*"; }
die() { echo "aur-setup: $*" >&2; exit 1; }

command -v ssh >/dev/null || die "ssh is not installed"
command -v gh >/dev/null || die "gh is not installed - see https://cli.github.com"

# ---------------------------------------------------------------- the key

if [ ! -f "$key" ]; then
  if $check_only; then
    die "no key at $key (run without --check to generate one)"
  fi
  say "no key at $key - generating one"
  ssh-keygen -t ed25519 -N "" -q \
    -C 'aur-publish@gibson-screensaver (github actions)' -f "$key"
fi
chmod 600 "$key"

# ------------------------------------------------------------ the account

# `ssh aur@aur.archlinux.org help` is the whole test: the AUR answers with its
# command list when the key belongs to an account, and refuses the key when it
# does not. Nothing is published by asking.
say "checking whether $key can authenticate to the AUR"
if ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
       -o StrictHostKeyChecking=accept-new \
       aur@aur.archlinux.org help >/dev/null 2>&1; then
  say "the key is registered on an AUR account"
elif $check_only; then
  # --check reports where everything stands, so it carries on rather than
  # stopping at the first thing that is not done yet.
  say "the AUR does not accept this key yet - no account, or the public half is not on it"
else
  cat <<EOF

aur-setup: the AUR will not accept this key yet.

Register an account at https://aur.archlinux.org/register (if registration is
still closed, that page answers with HTTP 503 and there is nothing to do but
wait for the announcement), then add this public key under
My Account -> SSH Public Key:

$(cat "$key.pub")

Then run this script again.
EOF
  exit 1
fi

# ------------------------------------------------------------- the secret

if $check_only; then
  if gh secret list 2>/dev/null | grep -q '^AUR_SSH_PRIVATE_KEY'; then
    say "AUR_SSH_PRIVATE_KEY is set - publishing is enabled"
  else
    say "AUR_SSH_PRIVATE_KEY is NOT set - the workflow will validate and skip the push"
  fi
  for p in "${packages[@]}"; do
    if [ "$(curl -sS "https://aur.archlinux.org/rpc/v5/info?arg[]=$p" |
            sed -n 's/.*"resultcount":\([0-9]*\).*/\1/p')" = 1 ]; then
      say "$p is on the AUR"
    else
      say "$p is not on the AUR yet"
    fi
  done
  exit 0
fi

say "storing the private key as the AUR_SSH_PRIVATE_KEY secret"
gh secret set AUR_SSH_PRIVATE_KEY < "$key"

# ------------------------------------------------------------ the publish

# dry_run=false is the point: the workflow defaults to a dry run so that
# exercising it cannot publish by accident.
say "running the AUR workflow for both packages"
gh workflow run aur.yml -f package=both -f dry_run=false

say "waiting for the run to start"
run_id=""
for _ in $(seq 1 30); do
  run_id=$(gh run list --workflow aur.yml --limit 1 --json databaseId \
    -q '.[0].databaseId' 2>/dev/null || true)
  [ -n "$run_id" ] && break
  sleep 2
done
[ -n "$run_id" ] || die "the run did not appear - check 'gh run list --workflow aur.yml'"

say "watching run $run_id (this builds both packages from scratch; ~10 minutes)"
gh run watch "$run_id" --exit-status || die "the run failed - 'gh run view $run_id --log-failed' has the reason"

# ------------------------------------------------------------- the result

say "checking the AUR for both packages"
failed=0
for p in "${packages[@]}"; do
  version=$(curl -sS "https://aur.archlinux.org/rpc/v5/info?arg[]=$p" |
    sed -n 's/.*"Version":"\([^"]*\)".*/\1/p')
  if [ -n "$version" ]; then
    say "$p $version is live: https://aur.archlinux.org/packages/$p"
  else
    say "$p did not appear - see the run log"
    failed=1
  fi
done
[ "$failed" = 0 ] || exit 1

cat <<'EOF'

aur-setup: done. Anyone can now install either package:

    git clone https://aur.archlinux.org/gibson-screensaver.git && cd gibson-screensaver && makepkg -si
    # or the prebuilt one, which needs no Rust toolchain:
    git clone https://aur.archlinux.org/gibson-screensaver-bin.git && cd gibson-screensaver-bin && makepkg -si

From here on releases publish themselves: the packaging commit that pins a new
version is what triggers the workflow.
EOF
