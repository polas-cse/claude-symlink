# claude-sync

Keeps Claude Code / Claude Desktop configuration identical on every PC.

## What is synced

| Repo path | Live path | How |
| --- | --- | --- |
| `claude/settings.json` | `~/.claude/settings.json` | copied by `pull`/`push` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | copied by `pull`/`push` |
| `claude/commands/` | `~/.claude/commands/` | directory junction (live) |
| `claude/agents/` | `~/.claude/agents/` | directory junction (live) |
| `claude/skills/` | `~/.claude/skills/` | directory junction (live) |

Folders are junctions, so edits there are instantly in the repo. The three
single files are copies, because file symlinks on Windows require admin rights
or Developer Mode.

## What is NOT synced, on purpose

`sessions/`, `projects/`, `cache/`, `shell-snapshots/`, `file-history/`,
`backups/`, `.credentials.json`, `claude-desktop/`, and any `*.local.json`. These are machine
specific, large, or hold credentials. Conversations themselves already follow
your Claude account; they are not files.

## Automatic sync

`bin/claude-sync.ps1 auto` is the unattended version: it takes whichever copy of
each file is newer, commits, fetches, merges other PCs' commits, pushes, and
writes the result back to the live paths. It never prompts, logs to `sync.log`,
and on a merge conflict it stops and says so instead of guessing.

There are two ways to start it. Both are invisible — no console window ever
appears, because they go through `wscript.exe` rather than `powershell.exe`.
PowerShell always creates a console and hides it only afterwards, which is the
terminal that flashes for about a second.

### Startup folder (recommended, never needs admin)

```powershell
cd ~\claude-sync
.\bin\install-startup.ps1 -StartNow
```

This drops a small stub in your Startup folder that launches
`bin/run-loop.vbs`, which syncs every 10 minutes for as long as you are logged
in. Remove it with `.\bin\install-startup.ps1 -Remove`.

Pick this one if `install-task.ps1` gives you **"Register-ScheduledTask :
Access is denied"**. A task in the root Task Scheduler folder cannot be
replaced without elevation, so once such a task exists, re-registering it from
a normal prompt fails. The Startup folder has no such restriction.

### Scheduled task (survives across logons, may need elevation)

```powershell
cd ~\claude-sync
.\bin\install-task.ps1
```

If this fails with "Access is denied", either run it from an elevated
PowerShell, or delete the existing `ClaudeConfigSync` task in Task Scheduler
first and run it again. Do not use both methods at once — they would sync twice
over each other.

Check it, or remove it:

```powershell
Get-ScheduledTask ClaudeConfigSync | Get-ScheduledTaskInfo
.\bin\install-task.ps1 -Remove
```

A different interval: `.\bin\install-task.ps1 -IntervalMinutes 5`.

The Claude app reads these files at startup, so a change pulled from another PC
shows up after you restart the app.

### Why not real symlinks

File symlinks on Windows need admin rights or Developer Mode, and this account
has neither — `New-Item -ItemType SymbolicLink` fails with "Administrator
privilege required". The folders (`commands/`, `agents/`, `skills/`) are
directory junctions, which need no admin, so those are genuinely live. The two
single files are copied by `auto` instead.

If you turn on **Settings → System → For developers → Developer Mode**, symlinks
start working for your user and the two files can be linked instead of copied:

```powershell
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\settings.json" -Target "$HOME\claude-sync\claude\settings.json" -Force
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\CLAUDE.md" -Target "$HOME\claude-sync\claude\CLAUDE.md" -Force
```

Even then the scheduled task is still needed — a symlink makes a file live on
one PC, but only git moves it between PCs.

## Daily use

With the task registered you do nothing. These are for when you want it now:

```powershell
cd ~\claude-sync
.\bin\claude-sync.ps1 auto     # sync both ways right now
.\bin\claude-sync.ps1 status   # see what differs
.\bin\claude-sync.ps1 push     # force live -> repo
.\bin\claude-sync.ps1 pull     # force repo -> live
```

Restart the Claude app afterwards so it re-reads the files.

## Setting up the remote (do this once)

Create an **empty private** repo on GitHub named `claude-symlink`, then:

```powershell
cd ~\claude-sync
git remote add origin https://github.com/polas-cse/claude-symlink.git
git push -u origin main
```

Keep it private anyway: `settings.json` can grow env vars and hook commands you
would not want public.

`%APPDATA%\Claude\claude_desktop_config.json` is **not** synced. It was checked
and holds no `mcpServers` block — only local UI state (pane layout, starred
sessions) and this machine's device name, and one field in it changes on every
session. Copying it between PCs would overwrite each machine's own window state
for no gain. If you later add MCP servers to Claude Desktop, add that file back
to `$Files` in `bin/claude-sync.ps1` and keep any tokens in env vars.

## Setting up a new PC — one command

Sign in to GitHub for git on that PC first (the clone is from a private repo),
then paste this into PowerShell. It clones, junctions the folders, syncs the
config and registers the hidden background task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "git clone https://github.com/polas-cse/claude-symlink.git $HOME\claude-sync; & $HOME\claude-sync\bin\bootstrap.ps1"
```

Already cloned? Just run the second half:

```powershell
& $HOME\claude-sync\bin\bootstrap.ps1
```

`bootstrap.ps1` is safe to re-run: each step checks before acting, and anything
it replaces is kept as `*.bak-<timestamp>`. It takes `-Repo <path>` for a
different location, `-IntervalMinutes <n>` for a different sync interval, and
`-Startup` to use the Startup folder instead of a scheduled task.

`link` preserves whatever that PC already had: existing `commands/`, `agents/`
or `skills/` contents are copied into the repo first, and any replaced file or
folder is renamed to `*.bak-<timestamp>` rather than deleted.

If PowerShell refuses to run the script, allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Notes

- Two PCs editing the same file is a normal git conflict — resolve it in the
  repo, then `auto` again.
- `.gitattributes` pins line endings to LF, and `auto` compares content with
  line endings normalized. Both are needed: without them a fresh clone checks
  out CRLF, the same content hashes differently from another PC's LF copy, and
  the sync commits back and forth forever.
- `claude-sync` does not sync Claude Code plugins installed from a marketplace;
  re-add those per machine, or commit `~/.claude/plugins/config.json` yourself
  if you want that too.
