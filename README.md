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

## Daily use

```powershell
cd ~\claude-sync
.\bin\claude-sync.ps1 push     # after changing config on this PC
.\bin\claude-sync.ps1 pull     # before working on another PC
.\bin\claude-sync.ps1 status   # see what differs
```

Restart the Claude app after a `pull` so it re-reads the files.

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

## Setting up a new PC

```powershell
git clone https://github.com/polas-cse/claude-symlink.git $HOME\claude-sync
cd ~\claude-sync
.\bin\claude-sync.ps1 link
.\bin\claude-sync.ps1 pull
```

`link` preserves whatever that PC already had: existing `commands/`, `agents/`
or `skills/` contents are copied into the repo first, and any replaced file or
folder is renamed to `*.bak-<timestamp>` rather than deleted.

If PowerShell refuses to run the script, allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Notes

- Two PCs editing the same file is a normal git conflict — resolve it in the
  repo, then `pull` again.
- `claude-sync` does not sync Claude Code plugins installed from a marketplace;
  re-add those per machine, or commit `~/.claude/plugins/config.json` yourself
  if you want that too.
