<#
  One-shot setup for a PC. Clones the repo if it is not here yet, junctions the
  folders, syncs the config, and registers the hidden background task.

  Safe to re-run: every step checks before acting, and anything it replaces is
  kept as *.bak-<timestamp>.

    .\bin\bootstrap.ps1
    .\bin\bootstrap.ps1 -Repo D:\claude-sync -IntervalMinutes 5
#>
param(
  [string]$Repo = (Join-Path $HOME 'claude-sync'),
  [string]$Url  = 'https://github.com/polas-cse/claude-symlink.git',
  [int]$IntervalMinutes = 10,

  # Use the Startup folder instead of a scheduled task. Set automatically if
  # the task registration is denied, which happens when a ClaudeConfigSync task
  # already exists in the root Task Scheduler folder.
  [switch]$Startup
)

$ErrorActionPreference = 'Stop'

function Step($Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

Step 'Checking git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'git is not on PATH. Install Git for Windows first: winget install --id Git.Git'
}
Write-Host "  $(git --version)"

Step "Repo at $Repo"
if (Test-Path -LiteralPath (Join-Path $Repo '.git')) {
  Write-Host '  already cloned'
} elseif (Test-Path -LiteralPath $Repo) {
  throw "$Repo exists but is not a git clone. Move it aside, or pass -Repo <other path>."
} else {
  git clone $Url $Repo
  if ($LASTEXITCODE -ne 0) { throw "clone failed. Sign in to GitHub for this PC first, then re-run." }
}

# From here on, use the scripts that came with the clone.
$bin = Join-Path $Repo 'bin'

Step 'Linking folders into ~/.claude'
& (Join-Path $bin 'claude-sync.ps1') link

Step 'Syncing config'
& (Join-Path $bin 'claude-sync.ps1') auto

Step 'Starting the background sync'
if ($Startup) {
  & (Join-Path $bin 'install-startup.ps1') -StartNow
} else {
  try {
    & (Join-Path $bin 'install-task.ps1') -IntervalMinutes $IntervalMinutes
  } catch {
    Write-Host "  scheduled task refused: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '  falling back to the Startup folder, which needs no admin rights' -ForegroundColor Yellow
    & (Join-Path $bin 'install-startup.ps1') -StartNow
  }
}

Step 'Result'
& (Join-Path $bin 'claude-sync.ps1') status

Write-Host "`nDone. Restart the Claude app so it reads the synced config." -ForegroundColor Green
