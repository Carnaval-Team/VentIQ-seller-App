# Screenshot pass 2: scroll states via native #anchors (no injected JS), plus r.html at a
# true 375px viewport through an iframe wrapper (Chrome clamps --window-size to ~500px).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File __agent__/landing-verify/shots2.ps1 -Label after
param(
    [string]$Label = "after",
    [string]$LandingDir = ""
)
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($LandingDir) { $landing = (Resolve-Path $LandingDir).Path } else { $landing = Join-Path $root "ventiq_landing" }
$outDir = Join-Path $root "__agent__\landing-verify\shots-$Label"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$baseHref = "file:///" + ($landing -replace '\\', '/') + "/"
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Shot([string]$url, [string]$file, [int]$w, [int]$h, [int]$dsf = 1) {
    $abs = Join-Path $outDir $file
    & $chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars --blink-settings=preferredColorScheme=1 `
        --force-device-scale-factor=$dsf --virtual-time-budget=8000 --window-size="$w,$h" --screenshot="$abs" $url 2>$null | Out-Null
    if (Test-Path $abs) { Write-Host ("OK   {0}  {1} KB" -f $file, [math]::Round((Get-Item $abs).Length / 1KB)) } else { Write-Host ("FAIL {0}" -f $file) }
}

$idx = $baseHref + "index.html"
$r   = $baseHref + "r.html?code=DEMO2026"

Shot $idx "01-hero-desktop.png" 1440 900 1
Shot ($idx + "#empresa")   "02-empresa.png"   1440 900 1
Shot ($idx + "#servicios") "03-servicios.png" 1440 900 1
Shot ($idx + "#apps")      "04-apps-card1.png" 1440 900 1
Shot ($idx + "#producto")  "05-bento.png"     1440 900 1
Shot ($idx + "#flow")      "06-flow.png"      1440 900 1
Shot ($idx + "#carnaval")  "07-carnaval.png"  1440 900 1
Shot $idx "08-index-tall.png" 1440 7600 1
Shot $idx "09-hero-mobile.png" 504 900 1
Shot $idx "10-index-mobile-tall.png" 504 6400 1
Shot $r   "11-r-desktop.png" 1100 1000 1

# r.html at a true 375 px viewport inside a 375px-wide iframe
$wrap = Join-Path $outDir "r-375-wrap.html"
$html = '<!DOCTYPE html><html><head><meta charset="utf-8"><base href="' + $baseHref + '">' +
        '<style>html,body{margin:0;background:#fff}iframe{width:375px;height:812px;border:0;display:block}</style></head>' +
        '<body><iframe src="r.html?code=DEMO2026"></iframe></body></html>'
[System.IO.File]::WriteAllText($wrap, $html, $utf8)
Shot ("file:///" + ($wrap -replace '\\', '/')) "12-r-375.png" 420 830 1

Write-Host "done -> $outDir"