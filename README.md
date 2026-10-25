# claude-sync

Keeps Claude's config the same on every PC: `settings.json`, `CLAUDE.md`,
`commands/`, `agents/`, `skills/`.

---

## Set up a new PC

### Step 1 — Install Git, if it is not there

```powershell
winget install --id Git.Git
```

Close and reopen PowerShell afterwards.

### Step 2 — Sign in to GitHub for git

This repo is private, so git needs your account once per PC. The easiest way is
to let the first clone ask you:

```powershell
git clone https://github.com/polas-cse/claude-symlink.git $HOME\claude-sync
```

A browser window opens, sign in, and the clone finishes.

### Step 3 — Run the setup

```powershell
& $HOME\claude-sync\bin\bootstrap.ps1
```

This links the folders, pulls the config, and starts the background sync.

If PowerShell refuses to run it:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Step 4 — Restart the Claude app

It reads the config at startup. That is all — syncing now runs every 10 minutes
on its own, with no visible window.

---

## Day to day

Nothing. Change your config on any PC and it spreads by itself.

Only if you want it **right now**, instead of waiting ten minutes:

```powershell
& $HOME\claude-sync\bin\claude-sync.ps1 auto
```

Then restart the Claude app.

To see what is going on:

```powershell
& $HOME\claude-sync\bin\claude-sync.ps1 status
Get-Content $HOME\claude-sync\sync.log -Tail 20
```

---

## If something is wrong

**A terminal flashes every few minutes.** The background job is being started
the wrong way. Fix it:

```powershell
& $HOME\claude-sync\bin\install-task.ps1
```

**That says "Access is denied".** Use the Startup folder instead, which needs no
admin rights:

```powershell
& $HOME\claude-sync\bin\install-startup.ps1 -StartNow
```

Use one or the other, never both — two jobs would sync over each other. Check
which you have:

```powershell
Get-ScheduledTask ClaudeConfigSync -ErrorAction SilentlyContinue   # the task
Test-Path "$([Environment]::GetFolderPath('Startup'))\claude-sync.vbs"   # the Startup one
```

Remove whichever you do not want:

```powershell
& $HOME\claude-sync\bin\install-startup.ps1 -Remove
Unregister-ScheduledTask ClaudeConfigSync -Confirm:$false   # may need an admin PowerShell
```

**`sync.log` says CONFLICT.** Two PCs changed the same file. Open
`$HOME\claude-sync`, fix the file by hand, `git add` and `git commit`, then run
`auto` again.

**Nothing is syncing.** Check the log. "push failed" means git lost your GitHub
sign-in on that PC; clone once more by hand to get it back.

---

## Reference

What is synced, and how:

| Repo path | Live path | How |
| --- | --- | --- |
| `claude/settings.json` | `~/.claude/settings.json` | copied by `auto` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | copied by `auto` |
| `claude/commands/` | `~/.claude/commands/` | directory junction, always live |
| `claude/agents/` | `~/.claude/agents/` | directory junction, always live |
| `claude/skills/` | `~/.claude/skills/` | directory junction, always live |

Not synced, on purpose: `sessions/`, `projects/`, `cache/`,
`shell-snapshots/`, `file-history/`, `backups/`, `.credentials.json`,
`sync.log`, and `%APPDATA%\Claude\claude_desktop_config.json`. These are
machine specific or hold credentials. Your conversations are not files at all;
they follow your Claude account.

Scripts in `bin/`:

| File | What it is for |
| --- | --- |
| `bootstrap.ps1` | Step 3 above: does everything for a new PC |
| `claude-sync.ps1` | the sync itself (`auto`, `status`, `link`, `push`, `pull`) |
| `install-task.ps1` | starts the sync as a scheduled task |
| `install-startup.ps1` | starts it from the Startup folder instead, no admin |
| `run-hidden.vbs` | windowless launcher used by the task |
| `run-loop.vbs` | windowless 10-minute loop used by the Startup folder |

Two details worth knowing, because both caused bugs here:

- The background job runs through `wscript.exe`, not `powershell.exe`.
  PowerShell always creates a console window and hides it a moment later, which
  is the terminal that flashes for about a second.
- `.gitattributes` pins line endings to LF and `auto` compares content with
  line endings normalized. Without both, a fresh clone checks out CRLF, the
  same content hashes differently from another PC's LF copy, and the sync
  commits back and forth forever.
