#!/usr/bin/env bash
# claude-sync - keep Claude's config identical on every machine (Linux / macOS).
#
#   ./bin/claude-sync.sh link      # one-time: symlink ~/.claude into this repo
#   ./bin/claude-sync.sh auto      # sync with the remote (what cron runs)
#   ./bin/claude-sync.sh status    # show what is linked and what differs
#   ./bin/claude-sync.sh install   # one-time: run auto every 10 minutes via cron
#   ./bin/claude-sync.sh uninstall # remove the cron entry
#
# Unlike Windows, symlinks here need no special rights, so every synced path is
# a real symlink and nothing is ever copied.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="$HOME/.claude"
LOG="$REPO/sync.log"

# Everything is linked, files and folders alike.
LINKS=(settings.json CLAUDE.md commands agents skills)

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG"
  printf '  %s\n' "$1"
}

backup() {
  local path="$1"
  [ -e "$path" ] || return 0
  local dest="$path.bak-$(date '+%Y%m%d-%H%M%S')"
  mv "$path" "$dest"
  printf '  backed up existing -> %s\n' "$dest"
}

cmd_link() {
  mkdir -p "$CLAUDE_HOME"
  local name live target
  for name in "${LINKS[@]}"; do
    live="$CLAUDE_HOME/$name"
    target="$REPO/claude/$name"

    # Keep whatever this machine already had, inside the repo, before linking.
    if [ -e "$live" ] && [ ! -L "$live" ]; then
      if [ -d "$live" ]; then
        mkdir -p "$target"
        cp -a "$live/." "$target/" 2>/dev/null || true
      else
        cp -a "$live" "$target"
      fi
      backup "$live"
    elif [ -L "$live" ]; then
      if [ "$(readlink "$live")" = "$target" ]; then
        printf '  %s already linked\n' "$name"
        continue
      fi
      rm "$live"
    fi

    [ -e "$target" ] || { case "$name" in
      commands|agents|skills) mkdir -p "$target"; touch "$target/.gitkeep" ;;
      *) touch "$target" ;;
    esac; }

    ln -s "$target" "$live"
    printf '  linked %s\n' "$name"
  done
}

cmd_auto() {
  cd "$REPO"

  git add -A
  if [ -n "$(git status --porcelain)" ]; then
    git commit -q -m "auto: config change on $(hostname -s)"
    log "committed local changes"
  fi

  if ! git fetch -q origin; then
    log "fetch failed (offline?) - will retry next run"
    return 0
  fi

  local behind ahead
  behind="$(git rev-list --count HEAD..origin/main)"
  ahead="$(git rev-list --count origin/main..HEAD)"

  if [ "$behind" -gt 0 ]; then
    if ! git merge -q --no-edit origin/main; then
      log "CONFLICT - sync stopped; resolve it in $REPO, then run auto again"
      return 0
    fi
    log "merged $behind commit(s) from other machines"
  fi

  if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
    if git push -q origin main; then
      log "pushed to origin"
    else
      log "push failed (credentials or offline) - will retry next run"
    fi
  fi
}

cmd_status() {
  local name live target
  for name in "${LINKS[@]}"; do
    live="$CLAUDE_HOME/$name"
    target="$REPO/claude/$name"
    if [ -L "$live" ] && [ "$(readlink "$live")" = "$target" ]; then
      printf '  linked:     %s\n' "$name"
    elif [ -e "$live" ]; then
      printf '  NOT linked: %s (a real file or folder is in the way)\n' "$name"
    else
      printf '  MISSING:    %s\n' "$name"
    fi
  done
  cd "$REPO"
  git status --short --branch
}

CRON_MARK="# claude-sync"

cmd_install() {
  local line="*/10 * * * * $REPO/bin/claude-sync.sh auto >/dev/null 2>&1 $CRON_MARK"
  local current
  current="$(crontab -l 2>/dev/null | grep -v "$CRON_MARK" || true)"
  printf '%s\n%s\n' "$current" "$line" | sed '/^$/d' | crontab -
  printf 'Installed cron entry: every 10 minutes.\n'
  printf 'Log: %s\n' "$LOG"
}

cmd_uninstall() {
  crontab -l 2>/dev/null | grep -v "$CRON_MARK" | crontab - || true
  printf 'Removed the cron entry.\n'
}

case "${1:-}" in
  link)      cmd_link ;;
  auto)      cmd_auto ;;
  status)    cmd_status ;;
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  *)
    printf 'usage: %s {link|auto|status|install|uninstall}\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
