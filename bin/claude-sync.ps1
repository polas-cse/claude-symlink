<#
  claude-sync - keep Claude Code / Claude Desktop config identical on every PC.

  Usage:
    .\bin\claude-sync.ps1 link     # one-time per PC: junction the folders
    .\bin\claude-sync.ps1 pull     # git pull + copy repo files -> live config
    .\bin\claude-sync.ps1 push     # copy live config -> repo + commit + push
    .\bin\claude-sync.ps1 status   # show what differs

  Folders (commands/agents/skills) are directory junctions, so they are always
  live. The three single files are copied, because file symlinks on Windows need
  admin rights or Developer Mode.
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('link', 'pull', 'push', 'status')]
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
  Write-Host "Now run: .\bin\claude-sync.ps1 pull" -ForegroundColor Cyan
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
        (Get-FileHash -LiteralPath $f.Live).Hash -ne (Get-FileHash -LiteralPath $src).Hash) {
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
    $same = (Get-FileHash -LiteralPath $f.Live).Hash -eq (Get-FileHash -LiteralPath $src).Hash
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

switch ($Command) {
  'link'   { Invoke-Link }
  'pull'   { Invoke-Pull }
  'push'   { Invoke-Push }
  'status' { Invoke-Status }
}
