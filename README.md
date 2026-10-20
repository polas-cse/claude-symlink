# claude-sync

Keeps Claude Code / Claude Desktop configuration identical on every PC.

## What is synced

| Repo path | Live path | How |
| --- | --- | --- |
| `claude/settings.json` | `~/.claude/settings.json` | copied by `pull`/`push` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | copied by `pull`/`push` |
| `claude-desktop/claude_desktop_config.json` | `%APPDATA%\Claude\claude_desktop_config.json` | copied by `pull`/`push` |
| `claude/commands/` | `~/.claude/commands/` | directory junction (live) |
| `claude/agents/` | `~/.claude/agents/` | directory junction (live) |
| `claude/skills/` | `~/.claude/skills/` | directory junction (live) |

Folders are junctions, so edits there are instantly in the repo. The three
single files are copies, because file symlinks on Windows require admin rights
or Developer Mode.

## What is NOT synced, on purpose

`sessions/`, `projects/`, `cache/`, `shell-snapshots/`, `file-history/`,
`backups/`, `.credentials.json`, and any `*.local.json`. These are machine
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

Create an **empty private** repo on GitHub named `claude-sync`, then:

```powershell
cd ~\claude-sync
git remote add origin git@github.com:<your-user>/claude-sync.git
git push -u origin main
```

Keep it private: `claude_desktop_config.json` can contain MCP server tokens.
Today's copy has none, but that can change — if you ever put a key in it, put
the key in an env var and reference it instead.

## Setting up a new PC

```powershell
git clone git@github.com:<your-user>/claude-sync.git $HOME\claude-sync
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
