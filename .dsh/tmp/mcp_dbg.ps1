param(
    [Parameter(Mandatory=$true)][string]$Token,
    [string]$Sql,
    [string]$File,
    [int]$TimeoutSec = 240,
    [int]$MaxPrint = 4000
)

$ErrorActionPreference = 'Stop'
$tmp = Join-Path $PWD '.dsh\tmp'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# OJO: sin read_only=true -> sesion con escritura en el proyecto DEBUG
$url = 'https://mcp.supabase.com/mcp?project_ref=qhprswhhfasrikhawjoz&features=docs%2Caccount%2Cdatabase%2Cdebugging%2Cdevelopment%2Cfunctions%2Cbranching'
$auth = "Authorization: Bearer $Token"

if (-not $File) {
    $file = Join-Path $tmp 'q.sql'
    [System.IO.File]::WriteAllText($file, $Sql, (New-Object System.Text.UTF8Encoding($false)))
} else {
    $file = $File
}

# 1) initialize
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"dsh","version":"1.0"}}}'
[System.IO.File]::WriteAllText((Join-Path $tmp 'init.json'), $init, (New-Object System.Text.UTF8Encoding($false)))
curl.exe -sS -D "$tmp\h.txt" -o NUL -X POST $url -H $auth -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" --data-binary "@$tmp\init.json" --max-time 60 | Out-Null
$sid = [regex]::Match((Get-Content "$tmp\h.txt" -Raw), 'mcp-session-id:\s*(\S+)').Groups[1].Value
if (-not $sid) { Write-Output 'ERROR: no se pudo abrir sesion MCP (revisa el token)'; exit 1 }

# 2) notifications/initialized
$nil = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
[System.IO.File]::WriteAllText((Join-Path $tmp 'nil.json'), $nil, (New-Object System.Text.UTF8Encoding($false)))
curl.exe -sS -o NUL -X POST $url -H $auth -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "mcp-session-id: $sid" --data-binary "@$tmp\nil.json" --max-time 60 | Out-Null

# 3) tools/call execute_sql
$sqlText = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
$body = @{ jsonrpc='2.0'; id=2; method='tools/call'; params=@{ name='execute_sql'; arguments=@{ query=$sqlText } } } | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText((Join-Path $tmp 'body.json'), $body, (New-Object System.Text.UTF8Encoding($false)))

$out = curl.exe -sS -X POST $url -H $auth -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "mcp-session-id: $sid" --data-binary "@$tmp\body.json" --max-time $TimeoutSec

$clean = ($out -replace '\\n', ' ' -replace '\\"', '"')
if ($clean.Length -gt $MaxPrint) { $clean = $clean.Substring(0, $MaxPrint) + '...[TRUNCADO]' }
Write-Output $clean