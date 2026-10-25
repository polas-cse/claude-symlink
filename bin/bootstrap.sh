#!/usr/bin/env bash
# One-shot setup for a Linux or macOS machine: clone, symlink, sync, schedule.
#
#   ./bin/bootstrap.sh                  # use /opt/claude-sync
#   REPO=~/claude-sync ./bin/bootstrap.sh
#
# Safe to re-run. Anything it replaces is kept as *.bak-<timestamp>.

set -euo pipefail

URL="${URL:-https://github.com/polas-cse/claude-symlink.git}"
REPO="${REPO:-/opt/claude-sync}"

step() { printf '\n==> %s\n' "$1"; }

step 'Checking git'
command -v git >/dev/null || {
  echo 'git is not installed. apt install git / dnf install git / brew install git' >&2
  exit 1
}
git --version

step "Repo at $REPO"
if [ -d "$REPO/.git" ]; then
  echo '  already cloned'
else
  if [ -e "$REPO" ]; then
    echo "  $REPO exists but is not a git clone. Move it aside, or set REPO=<other path>." >&2
    exit 1
  fi
  parent="$(dirname "$REPO")"
  # /opt and other system paths need one sudo to create; $HOME does not.
  if [ -w "$parent" ]; then
    git clone "$URL" "$REPO"
  else
    echo "  $parent is not writable, using sudo to create $REPO for you"
    sudo mkdir -p "$REPO"
    sudo chown "$(id -u):$(id -g)" "$REPO"
    git clone "$URL" "$REPO"
  fi
fi

step 'Linking ~/.claude into the repo'
"$REPO/bin/claude-sync.sh" link

step 'Syncing config'
"$REPO/bin/claude-sync.sh" auto

step 'Scheduling the sync'
"$REPO/bin/claude-sync.sh" install

step 'Result'
"$REPO/bin/claude-sync.sh" status

printf '\nDone. Restart the Claude app so it reads the synced config.\n'
