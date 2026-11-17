$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$lib = Join-Path $PSScriptRoot '..\dsh-plugins\grok-desktop\lib'
. (Join-Path $lib 'Theme.ps1')
. (Join-Path $lib 'Panel.ps1')

$selected = $true
$sub = New-PanelText -Text 'C:\x' -Size 10 -Color $(if ($selected) { 'accent' } else { 'muted' }) -Opacity 0.95
Write-Output ('tipo : ' + $(if ($null -eq $sub) { 'NULL' } else { $sub.GetType().FullName }))
Write-Output ('count: ' + @($sub).Count)

$row = New-PanelRow -Title 'titulo' -Sub 'C:\x\y' -Right '12' -Selected $true
Write-Output ('row  : ' + $(if ($null -eq $row) { 'NULL' } else { $row.GetType().FullName }))