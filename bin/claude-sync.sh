#!/usr/bin/env bash
# claude-sync - keep Claude's config identical on every machine (Linux / macOS).
#
#   ./bin/claude-sync.sh link      # one-time: symlink ~/.claude into this repo
#   ./bin/claude-sync.sh watch     # keep syncing within 30s of any change
#   ./bin/claude-sync.sh auto      # one sync with the remote
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

# Notices a change within half a minute instead of waiting for the next cron
# run. Uses inotifywait or fswatch when they are installed, and falls back to
# polling, so it works on a bare system too.
cmd_watch() {
  local poll=30 full=600 last_full=0 now changed

  log "watching for changes (full sync every $((full / 60)) min)"

  while true; do
    changed=0

    # Wait for a filesystem event, but never longer than one poll interval.
    if command -v inotifywait >/dev/null 2>&1; then
      inotifywait -qq -t "$poll" -r -e close_write,create,delete,move \
        "$CLAUDE_HOME" "$REPO/claude" 2>/dev/null && changed=1
    elif command -v fswatch >/dev/null 2>&1; then
      fswatch -1 --latency 2 --timeout="$poll" "$CLAUDE_HOME" "$REPO/claude" \
        >/dev/null 2>&1 && changed=1
    else
      sleep "$poll"
      cd "$REPO"
      [ -n "$(git status --porcelain)" ] && changed=1
    fi

    now="$(date +%s)"
    if [ "$changed" -eq 1 ] || [ $((now - last_full)) -ge "$full" ]; then
      # Let a burst of edits settle before committing them.
      [ "$changed" -eq 1 ] && sleep 5
      cmd_auto
      last_full="$(date +%s)"
    fi
  done
}

CRON_MARK="# claude-sync"

cmd_install() {
  # @reboot keeps the watcher running for instant syncs; the timed entry is a
  # backstop in case the watcher dies, and restarts it if it is gone.
  local watch="@reboot $REPO/bin/claude-sync.sh watch >/dev/null 2>&1 $CRON_MARK"
  local guard="*/10 * * * * pgrep -f 'claude-sync.sh watch' >/dev/null || $REPO/bin/claude-sync.sh watch >/dev/null 2>&1 $CRON_MARK"
  local current
  current="$(crontab -l 2>/dev/null | grep -v "$CRON_MARK" || true)"
  printf '%s\n%s\n%s\n' "$current" "$watch" "$guard" | sed '/^$/d' | crontab -
  printf 'Installed cron entries: watcher at boot, checked every 10 minutes.\n'
  printf 'Log: %s\n' "$LOG"

  if ! pgrep -f 'claude-sync.sh watch' >/dev/null 2>&1; then
    nohup "$REPO/bin/claude-sync.sh" watch >/dev/null 2>&1 &
    printf 'Started the watcher now too.\n'
  fi

  if ! command -v inotifywait >/dev/null 2>&1 && ! command -v fswatch >/dev/null 2>&1; then
    printf '\nTip: for instant detection install one of these; without them the\n'
    printf 'watcher falls back to checking every 30 seconds.\n'
    printf '  Linux: sudo apt install inotify-tools\n'
    printf '  macOS: brew install fswatch\n'
  fi
}

cmd_uninstall() {
  crontab -l 2>/dev/null | grep -v "$CRON_MARK" | crontab - || true
  pkill -f 'claude-sync.sh watch' 2>/dev/null || true
  printf 'Removed the cron entry.\n'
}

case "${1:-}" in
  link)      cmd_link ;;
  auto)      cmd_auto ;;
  status)    cmd_status ;;
  install)   cmd_install ;;
  watch)     cmd_watch ;;
  uninstall) cmd_uninstall ;;
  *)
    printf 'usage: %s {link|watch|auto|status|install|uninstall}\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
