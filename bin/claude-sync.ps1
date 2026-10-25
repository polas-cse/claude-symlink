<#
  claude-sync - keep Claude Code / Claude Desktop config identical on every PC.

  Usage:
    .\bin\claude-sync.ps1 link     # one-time per PC: junction the folders
    .\bin\claude-sync.ps1 watch    # keep syncing within 30s of any change
    .\bin\claude-sync.ps1 auto     # one unattended two-way sync
    .\bin\claude-sync.ps1 pull     # repo files -> live config
    .\bin\claude-sync.ps1 push     # live config -> repo, then commit and push
    .\bin\claude-sync.ps1 status   # show what differs

  See README.md for the background job that calls 'watch' automatically.

  Folders (commands/agents/skills) are directory junctions, so they are always
  live. The two single files are copied, because file symlinks on Windows need
  admin rights or Developer Mode.
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('link', 'pull', 'push', 'status', 'auto', 'watch')]
  [string]$Command,

  [string]$Message
)

$ErrorActionPreference = 'Stop'

$Repo        = Split-Path -Parent $PSScriptRoot
$ClaudeHome  = Join-Path $HOME '.claude'

# repo path -> live path, for files that are copied.
# %APPDATA%\Claude\claude_desktop_config.json is deliberately NOT here: on this
# install it holds only local UI state and the device name, no MCP servers.
$Files = @(
  @{ Repo = 'claude\settings.json'; Live = (Join-Path $ClaudeHome 'settings.json') }
  @{ Repo = 'claude\CLAUDE.md';     Live = (Join-Path $ClaudeHome 'CLAUDE.md') }
)

# folders that become junctions into the repo
$Dirs = @('commands', 'agents', 'skills')

# Hash of the content with line endings normalized, so a file the Claude app
# rewrote as CRLF is not treated as different from the LF copy in the repo.
# Comparing raw bytes made every fresh clone look out of sync forever.
function Get-ContentHash($Path) {
  $text  = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  $sha   = [System.Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
  finally { $sha.Dispose() }
}

function Backup-Path($Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = "$Path.bak-$stamp"
  Move-Item -LiteralPath $Path -Destination $backup
  Write-Host "  backed up existing -> $backup" -ForegroundColor DarkGray
}

function Invoke-Link {
  New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null
  foreach ($name in $Dirs) {
    $live     = Join-Path $ClaudeHome $name
    $target   = Join-Path $Repo "claude\$name"
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    $existing = Get-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
      if ($existing.LinkType -eq 'Junction' -and $existing.Target -contains $target) {
        Write-Host "  $name already linked" -ForegroundColor DarkGray
        continue
      }
      # keep whatever was already there, inside the repo, then relink
      if (-not $existing.LinkType) {
        Get-ChildItem -LiteralPath $live -Force | ForEach-Object {
          Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
        }
      }
      Backup-Path $live
    }
    cmd /c mklink /J "`"$live`"" "`"$target`"" | Out-Null
    Write-Host "  linked $name" -ForegroundColor Green
  }
}

function Invoke-Pull {
  Push-Location $Repo
  try { git pull --ff-only } finally { Pop-Location }

  foreach ($f in $Files) {
    $src = Join-Path $Repo $f.Repo
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dstDir = Split-Path -Parent $f.Live
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    if ((Test-Path -LiteralPath $f.Live) -and
        (Get-ContentHash $f.Live) -ne (Get-ContentHash $src)) {
      Backup-Path $f.Live
    }
    Copy-Item -LiteralPath $src -Destination $f.Live -Force
    Write-Host "  pulled $($f.Repo)" -ForegroundColor Green
  }
  Write-Host 'Restart the Claude app so it re-reads the config.' -ForegroundColor Cyan
}

function Invoke-Push {
  foreach ($f in $Files) {
    if (-not (Test-Path -LiteralPath $f.Live)) { continue }
    Copy-Item -LiteralPath $f.Live -Destination (Join-Path $Repo $f.Repo) -Force
    Write-Host "  staged $($f.Repo)" -ForegroundColor Green
  }

  Push-Location $Repo
  try {
    git add -A
    if ((git status --porcelain).Length -eq 0) {
      Write-Host 'Nothing to push.' -ForegroundColor DarkGray
      return
    }
    if (-not $Message) { $Message = "config sync from $env:COMPUTERNAME on $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    git commit -m $Message
    git push
  } finally { Pop-Location }
}

function Invoke-Status {
  foreach ($f in $Files) {
    $src = Join-Path $Repo $f.Repo
    if (-not (Test-Path -LiteralPath $f.Live)) { Write-Host "  MISSING live: $($f.Repo)" -ForegroundColor Yellow; continue }
    if (-not (Test-Path -LiteralPath $src))    { Write-Host "  MISSING repo: $($f.Repo)" -ForegroundColor Yellow; continue }
    $same = (Get-ContentHash $f.Live) -eq (Get-ContentHash $src)
    if ($same) { Write-Host "  in sync: $($f.Repo)" -ForegroundColor Green }
    else       { Write-Host "  DIFFERS: $($f.Repo)" -ForegroundColor Yellow }
  }
  foreach ($name in $Dirs) {
    $item = Get-Item -LiteralPath (Join-Path $ClaudeHome $name) -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') { Write-Host "  linked:  $name" -ForegroundColor Green }
    else { Write-Host "  NOT linked: $name" -ForegroundColor Yellow }
  }
  Push-Location $Repo
  try { git status --short --branch } finally { Pop-Location }
}

$LogFile = Join-Path $Repo 'sync.log'

function Write-Log($Text) {
  Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Text"
  Write-Host "  $Text" -ForegroundColor DarkGray
}

# Runs unattended. Takes whichever copy of each file is newer, then syncs git.
function Invoke-Auto {
  Push-Location $Repo
  try {
    # 1. take whatever this PC changed since the last run into the repo
    foreach ($f in $Files) {
      $src = Join-Path $Repo $f.Repo
      if (-not (Test-Path -LiteralPath $f.Live)) { continue }
      if (-not (Test-Path -LiteralPath $src)) {
        Copy-Item -LiteralPath $f.Live -Destination $src -Force
        Write-Log "repo had no $($f.Repo); took the live copy"
        continue
      }
      if ((Get-ContentHash $f.Live) -eq (Get-ContentHash $src)) { continue }
      if ((Get-Item -LiteralPath $f.Live).LastWriteTimeUtc -gt (Get-Item -LiteralPath $src).LastWriteTimeUtc) {
        Copy-Item -LiteralPath $f.Live -Destination $src -Force
        Write-Log "local edit -> repo: $($f.Repo)"
      }
    }

    # 2. commit local edits so the merge has a clean tree
    git add -A | Out-Null
    if ((git status --porcelain).Length -gt 0) {
      git commit -q -m "auto: config change on $env:COMPUTERNAME"
      Write-Log 'committed local changes'
    }

    # 3. exchange with the remote
    git fetch -q origin
    if ($LASTEXITCODE -ne 0) { Write-Log 'fetch failed (offline?) - will retry next run'; return }
    $behind = [int](git rev-list --count HEAD..origin/main)
    $ahead  = [int](git rev-list --count origin/main..HEAD)
    if ($behind -gt 0) {
      git merge -q --no-edit origin/main
      if ($LASTEXITCODE -ne 0) {
        Write-Log "CONFLICT - sync stopped; resolve it in $Repo, then run 'auto' again"
        return
      }
      Write-Log "merged $behind commit(s) from other PCs"
    }
    if ($ahead -gt 0 -or $behind -gt 0) {
      git push -q origin main
      if ($LASTEXITCODE -eq 0) { Write-Log 'pushed to origin' }
      else { Write-Log 'push failed (credentials or offline) - will retry next run' }
    }

    # 4. write repo state back out to the live paths
    foreach ($f in $Files) {
      $src = Join-Path $Repo $f.Repo
      if (-not (Test-Path -LiteralPath $src)) { continue }
      if ((Test-Path -LiteralPath $f.Live) -and
          (Get-ContentHash $f.Live) -eq (Get-ContentHash $src)) { continue }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f.Live) | Out-Null
      Copy-Item -LiteralPath $src -Destination $f.Live -Force
      Write-Log "repo -> live: $($f.Repo) (restart the Claude app to pick it up)"
    }
  } finally { Pop-Location }
}

# Watches for changes instead of waiting for the next scheduled run, so a change
# reaches the remote within half a minute rather than up to ten. Polling the five
# synced paths is cheap; it only touches the network when something actually
# changed, plus one full exchange every FullSyncSeconds so other machines'
# changes still arrive.
function Invoke-Watch {
  $pollSeconds     = 15
  $fullSyncSeconds = 600
  $lastFull        = [datetime]::MinValue

  Write-Log "watching for changes every $pollSeconds s (full sync every $($fullSyncSeconds / 60) min)"

  while ($true) {
    $localChanged = $false

    foreach ($f in $Files) {
      $src = Join-Path $Repo $f.Repo
      if (-not (Test-Path -LiteralPath $f.Live)) { continue }
      if (-not (Test-Path -LiteralPath $src)) { $localChanged = $true; break }
      if ((Get-ContentHash $f.Live) -ne (Get-ContentHash $src)) { $localChanged = $true; break }
    }

    # The junctioned folders are the repo's own files, so git sees those edits.
    if (-not $localChanged) {
      Push-Location $Repo
      try { if ((git status --porcelain).Length -gt 0) { $localChanged = $true } } finally { Pop-Location }
    }

    $dueForFull = ((Get-Date) - $lastFull).TotalSeconds -ge $fullSyncSeconds

    if ($localChanged -or $dueForFull) {
      # Let a burst of edits settle before committing them.
      if ($localChanged) { Start-Sleep -Seconds 5 }
      Invoke-Auto
      $lastFull = Get-Date
    }

    Start-Sleep -Seconds $pollSeconds
  }
}

switch ($Command) {
  'link'   { Invoke-Link }
  'watch'  { Invoke-Watch }
  'pull'   { Invoke-Pull }
  'push'   { Invoke-Push }
  'status' { Invoke-Status }
  'auto'   { Invoke-Auto }
}
