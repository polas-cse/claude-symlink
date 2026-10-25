# claude-sync

Keeps Claude's config the same on every machine: `settings.json`, `CLAUDE.md`,
`commands/`, `agents/`, `skills/`.

The repo lives outside your user folder on purpose, so clearing a profile,
reinstalling Claude or deleting a home directory cannot take it with it:

| OS | Where the repo lives |
| --- | --- |
| Windows | `C:\claude-sync` |
| Linux | `/opt/claude-sync` |
| macOS | `/opt/claude-sync` |

---

# Windows

### Step 1 — Install Git, if it is not there

```powershell
winget install --id Git.Git
```

Close and reopen PowerShell afterwards.

### Step 2 — Clone, and sign in to GitHub when asked

```powershell
git clone https://github.com/polas-cse/claude-symlink.git C:\claude-sync
```

A browser opens the first time on each PC; sign in and the clone finishes.
`C:\claude-sync` needs no admin rights — the root of C: allows this.

### Step 3 — Run the setup

```powershell
& C:\claude-sync\bin\bootstrap.ps1
```

If PowerShell refuses to run it:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Step 4 — Restart the Claude app

Done. It now syncs about 20 seconds after any change, with no visible window.

---

# Linux

### Step 1 — Install Git, if it is not there

```bash
sudo apt install git        # Debian, Ubuntu
sudo dnf install git        # Fedora, RHEL
```

### Step 2 — Clone, and sign in to GitHub when asked

```bash
sudo mkdir -p /opt/claude-sync && sudo chown "$(id -u):$(id -g)" /opt/claude-sync
git clone https://github.com/polas-cse/claude-symlink.git /opt/claude-sync
```

This is the only command that needs `sudo`, because `/opt` belongs to root.
Everything after it runs as you.

### Step 3 — Run the setup

```bash
/opt/claude-sync/bin/bootstrap.sh
```

### Step 4 — Restart the Claude app

Done. A watcher starts at boot and syncs about 20 seconds after any change.

---

# macOS

### Step 1 — Install Git, if it is not there

```bash
brew install git
```

Or just run `git --version`, which offers to install Apple's own copy.

### Step 2 — Clone, and sign in to GitHub when asked

```bash
sudo mkdir -p /opt/claude-sync && sudo chown "$(id -u):$(id -g)" /opt/claude-sync
git clone https://github.com/polas-cse/claude-symlink.git /opt/claude-sync
```

### Step 3 — Run the setup

```bash
/opt/claude-sync/bin/bootstrap.sh
```

macOS may ask you to allow cron to manage files; say yes, or the 10-minute sync
cannot write to `~/.claude`.

### Step 4 — Restart the Claude app

Done.

---

# Day to day — every OS

Nothing. Change your config on any machine and it is pushed about 20 seconds
later, so a power cut or a shutdown cannot leave much behind.

A background watcher checks the synced paths every 15 seconds, waits 5 seconds
for your edits to settle, then commits and pushes. On Linux and macOS it uses
`inotifywait` or `fswatch` when they are installed and reacts instantly; it
falls back to the same 15-second check without them. Every 10 minutes it also
does a full exchange, so other machines' changes arrive even when nothing
changed here.

Nothing is ever lost by a shutdown either way: the file stays on that machine's
disk, and the next time it boots, the watcher pushes it.

Only if you want it **right now** instead of waiting those seconds:

```powershell
& C:\claude-sync\bin\claude-sync.ps1 auto
```

```bash
/opt/claude-sync/bin/claude-sync.sh auto
```

Then restart the Claude app.

To see what is going on:

```powershell
& C:\claude-sync\bin\claude-sync.ps1 status
Get-Content C:\claude-sync\sync.log -Tail 20
```

```bash
/opt/claude-sync/bin/claude-sync.sh status
tail -20 /opt/claude-sync/sync.log
```

---

# If something is wrong

**A terminal flashes every few minutes** (Windows). The background job is being
started the wrong way:

```powershell
& C:\claude-sync\bin\install-task.ps1
```

**That says "Access is denied"** (Windows). Use the Startup folder instead,
which never needs admin:

```powershell
& C:\claude-sync\bin\install-startup.ps1 -StartNow
```

Use one or the other, never both — two jobs would sync over each other. Check
which you have:

```powershell
Get-ScheduledTask ClaudeConfigSync -ErrorAction SilentlyContinue
Test-Path "$([Environment]::GetFolderPath('Startup'))\claude-sync.vbs"
```

Remove whichever you do not want:

```powershell
& C:\claude-sync\bin\install-startup.ps1 -Remove
Unregister-ScheduledTask ClaudeConfigSync -Confirm:$false   # may need an admin PowerShell
```

**Nothing syncs on Linux or macOS.** Check the cron entry is there, and the log:

```bash
crontab -l | grep claude-sync
tail -20 /opt/claude-sync/sync.log
```

Reinstall it with `/opt/claude-sync/bin/claude-sync.sh install`, remove it with
`uninstall`.

**`sync.log` says CONFLICT.** Two machines changed the same file. Open the repo,
fix the file by hand, `git add` and `git commit`, then run `auto` again.

**`sync.log` says "push failed".** Git lost your GitHub sign-in on that machine.
Run any `git pull` in the repo by hand to sign in again.

---

# Reference

What is synced:

| Repo path | Live path | Windows | Linux / macOS |
| --- | --- | --- | --- |
| `claude/settings.json` | `~/.claude/settings.json` | copied by `auto` | symlink |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | copied by `auto` | symlink |
| `claude/commands/` | `~/.claude/commands/` | junction | symlink |
| `claude/agents/` | `~/.claude/agents/` | junction | symlink |
| `claude/skills/` | `~/.claude/skills/` | junction | symlink |

On Linux and macOS everything is a real symlink, so changes are live
immediately and only git has to move them between machines. On Windows,
folders can be junctions without admin rights but single files cannot be
symlinked, so those two are copied by `auto` instead.

Not synced, on purpose: `sessions/`, `projects/`, `cache/`,
`shell-snapshots/`, `file-history/`, `backups/`, `.credentials.json`,
`sync.log`, and `%APPDATA%\Claude\claude_desktop_config.json`. These are
machine specific or hold credentials. Your conversations are not files at all;
they follow your Claude account.

Scripts:

| File | Platform | What it is for |
| --- | --- | --- |
| `bin/bootstrap.ps1` | Windows | Step 3: does everything for a new PC |
| `bin/claude-sync.ps1` | Windows | the sync itself (`auto`, `status`, `link`, `push`, `pull`) |
| `bin/install-task.ps1` | Windows | runs the sync as a scheduled task |
| `bin/install-startup.ps1` | Windows | runs it from the Startup folder instead, no admin |
| `bin/run-watch.vbs` | Windows | windowless launcher that keeps the watcher running |
| `bin/bootstrap.sh` | Linux, macOS | Step 3: does everything for a new machine |
| `bin/claude-sync.sh` | Linux, macOS | the sync itself (`auto`, `status`, `link`, `install`) |

Two details worth knowing, because both caused bugs here:

- On Windows the background job runs through `wscript.exe`, not
  `powershell.exe`. PowerShell always creates a console window and hides it a
  moment later, which is the terminal that flashes for about a second.
- `.gitattributes` pins line endings to LF and `auto` compares content with
  line endings normalized. Without both, a Windows clone checks out CRLF, the
  same content hashes differently from a Linux machine's LF copy, and the sync
  commits back and forth forever.
