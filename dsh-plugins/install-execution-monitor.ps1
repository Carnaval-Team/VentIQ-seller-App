# Installs (or removes) the Execution Monitor bundle in the DSH "desktop" profile.
#
#   pwsh -File install-execution-monitor.ps1            # install
#   pwsh -File install-execution-monitor.ps1 -Uninstall # remove
#
# It snapshots the profile manifest and patch before touching them, installs the
# local package with the DSH-bundled pnpm (falling back to a directory link when
# pnpm cannot run), selects the bundle, and verifies resolution + composition.

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$profileDir = 'C:\Users\cesar\.dsh\profiles\desktop'
$bundleDir = Join-Path $PSScriptRoot 'execution-monitor'
$toolsDir = Join-Path $PSScriptRoot 'tools'
$backupDir = Join-Path $PSScriptRoot '.install-backup'
$name = '@local/dsh-execution-monitor'
$node = 'C:\Users\cesar\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
$pnpm = 'C:\Users\cesar\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\pnpm\bin\pnpm.mjs'
$dsh = 'C:\Users\cesar\AppData\Local\Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'

function Invoke-ProfileBundle([string]$action) {
  & $node (Join-Path $toolsDir 'profile-bundle.mjs') $profileDir $name $action
  if ($LASTEXITCODE -ne 0) { throw "profile-bundle.mjs failed with $LASTEXITCODE" }
}

# 1. Snapshot the profile files this script can change.
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($file in @('package.json', 'pnpm-lock.yaml', 'cordis.patch.yml')) {
  $source = Join-Path $profileDir $file
  if (Test-Path $source) { Copy-Item $source (Join-Path $backupDir "$stamp.$file") -Force }
}
Write-Output "backup: $backupDir\$stamp.*"

if ($Uninstall) {
  Invoke-ProfileBundle 'remove'
  & $node $pnpm 'remove' $name '--dir' $profileDir '--reporter=append-only'
  Write-Output "uninstalled: $name (exit $LASTEXITCODE)"
  exit 0
}

# 2. Install the local package into the profile.
$installed = $false
if ((Test-Path $pnpm) -and (Test-Path $node)) {
  & $node $pnpm 'add' $bundleDir '--dir' $profileDir '--reporter=append-only'
  $installed = $LASTEXITCODE -eq 0
  if (-not $installed) { Write-Output "pnpm add failed (exit $LASTEXITCODE); falling back to a directory link" }
} else {
  Write-Output 'bundled pnpm not found; falling back to a directory link'
}

if (-not $installed) {
  $scopeDir = Join-Path $profileDir 'node_modules\@local'
  New-Item -ItemType Directory -Force -Path $scopeDir | Out-Null
  $linkPath = Join-Path $scopeDir 'dsh-execution-monitor'
  if (Test-Path $linkPath) { Remove-Item $linkPath -Recurse -Force }
  New-Item -ItemType Junction -Path $linkPath -Target $bundleDir | Out-Null
  & $node -e "const fs=require('fs');const p=process.argv[1];const m=JSON.parse(fs.readFileSync(p,'utf8'));m.dependencies=Object.assign({},m.dependencies,{'$name':'link:'+process.argv[2].split('\\').join('/')});fs.writeFileSync(p,JSON.stringify(m,null,2)+'\n')" (Join-Path $profileDir 'package.json') $bundleDir
  if ($LASTEXITCODE -ne 0) { throw 'manifest rewrite failed' }
}

# 3. Select the bundle in the profile manifest.
Invoke-ProfileBundle 'add'

# 4. Verify: the package resolves from the profile and the row composes.
$resolved = & $node -e "console.log(require.resolve('$name/package.json',{paths:[process.argv[1]]}))" $profileDir
Write-Output "resolves to: $resolved"

if (Test-Path $dsh) {
  $dump = & $dsh '--profile' 'desktop' '--dump-config' 2>&1
  $row = $dump | Select-String -Pattern 'execution-monitor' -SimpleMatch
  if ($row) { Write-Output "composed rows:"; $row | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) } }
  else { Write-Output 'WARNING: no execution-monitor row in the composed config' }
} else {
  Write-Output 'dsh CLI not found; skipped the composed-config check'
}

Write-Output 'install: done'
