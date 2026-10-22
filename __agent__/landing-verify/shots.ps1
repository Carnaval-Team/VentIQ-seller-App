# Screenshot harness for ventiq_landing visual verification.
# Usage:  pwsh -File __agent__/landing-verify/shots.ps1 -Label before
# Captures the CURRENT state of ventiq_landing into __agent__/landing-verify/<label>/
param(
    [string]$Label = "before",
    [string]$Only = ""
)

$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$landing = Join-Path $root "ventiq_landing"
$outDir = Join-Path $root "__agent__\landing-verify\$Label"
$probeDir = Join-Path $root "__agent__\landing-verify\probe-$Label"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null

$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$baseHref = "file:///" + ($landing -replace '\\', '/') + "/"

function New-Probe {
    param([string]$Name, [string]$Source, [string]$ScrollJs)
    $src = Join-Path $landing $Source
    $html = Get-Content -Raw -LiteralPath $src
    $html = $html -replace '(?i)(<head[^>]*>)', ('$1' + "`n<base href=`"$baseHref`">")
    $inject = "<script>window.addEventListener('load',function(){setTimeout(function(){try{" + $ScrollJs + "}catch(e){document.title='PROBE_ERR '+e;}},1200);});</script>"
    $html = $html -replace '(?i)(</body>)', ($inject + "`n" + '$1')
    $target = Join-Path $probeDir $Name
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($target, $html, $utf8)
}

function Shot {
    param([string]$Url, [string]$File, [int]$W, [int]$H, [int]$Dsf = 2, [int]$Budget = 9000)
    $abs = Join-Path $outDir $File
    & $chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars --disable-features=Translate,MediaRouter `
        --force-device-scale-factor=$Dsf --virtual-time-budget=$Budget --window-size="$W,$H" `
        --screenshot="$abs" $Url 2>$null | Out-Null
    if (Test-Path $abs) { Write-Host ("OK   {0}  ({1} KB)" -f $File, [math]::Round((Get-Item $abs).Length / 1KB)) }
    else { Write-Host ("FAIL {0}" -f $File) }
}

function LandingUrl([string]$File) { return $baseHref + $File }
function ProbeUrl([string]$File) { return "file:///" + (($probeDir + "\" + $File) -replace '\\', '/') }

# ---- probes (scroll-driven states) ----
# Card 1 top aligned under the nav
New-Probe "stack-c1.html" "index.html" "var c=document.querySelectorAll('.v2-stack-card')[0];window.scrollTo(0,Math.round(c.getBoundingClientRect().top+window.scrollY-88));"
# Card 2 arriving: card 1 should be scaled/dimmed behind it
New-Probe "stack-c2.html" "index.html" "var c=document.querySelectorAll('.v2-stack-card')[1];window.scrollTo(0,Math.round(c.getBoundingClientRect().top+window.scrollY-88));"
# Card 3 arriving
New-Probe "stack-c3.html" "index.html" "var c=document.querySelectorAll('.v2-stack-card')[2];window.scrollTo(0,Math.round(c.getBoundingClientRect().top+window.scrollY-88));"
# Between card 2 and 3 (mid transfer)
New-Probe "stack-mid.html" "index.html" "var c=document.querySelectorAll('.v2-stack-card')[1];var t=c.getBoundingClientRect().top+window.scrollY-88;var n=document.querySelectorAll('.v2-stack-card')[2];var d=n.getBoundingClientRect().top+window.scrollY-88;window.scrollTo(0,Math.round(t+(d-t)*0.5));"
# Services (dark) + bento
New-Probe "services.html" "index.html" "window.scrollTo(0,document.getElementById('servicios').offsetTop-88);"
New-Probe "bento.html" "index.html" "window.scrollTo(0,document.getElementById('producto').offsetTop-88);"
New-Probe "empresa.html" "index.html" "window.scrollTo(0,document.getElementById('empresa').offsetTop-88);"
New-Probe "flow.html" "index.html" "window.scrollTo(0,document.getElementById('flow').offsetTop-88);"
New-Probe "carnaval.html" "index.html" "window.scrollTo(0,document.getElementById('carnaval').offsetTop-88);"

$jobs = @(
    @{ Name = "01-hero-desktop.png";      Url = (LandingUrl "index.html");                      W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "02-hero-mobile.png";       Url = (LandingUrl "index.html");                      W = 390;  H = 844;  Dsf = 2 },
    @{ Name = "03-stack-card1.png";       Url = (ProbeUrl "stack-c1.html");                     W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "04-stack-card2.png";       Url = (ProbeUrl "stack-c2.html");                     W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "05-stack-mid.png";         Url = (ProbeUrl "stack-mid.html");                    W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "06-stack-card3.png";       Url = (ProbeUrl "stack-c3.html");                     W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "07-empresa.png";           Url = (ProbeUrl "empresa.html");                      W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "08-services.png";          Url = (ProbeUrl "services.html");                     W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "09-bento.png";             Url = (ProbeUrl "bento.html");                        W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "10-flow.png";              Url = (ProbeUrl "flow.html");                         W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "11-carnaval.png";          Url = (ProbeUrl "carnaval.html");                     W = 1440; H = 900;  Dsf = 2 },
    @{ Name = "12-r-mobile.png";          Url = (LandingUrl "r.html");                          W = 390;  H = 900;  Dsf = 2 },
    @{ Name = "13-r-desktop.png";         Url = (LandingUrl "r.html");                          W = 1100; H = 900;  Dsf = 1 },
    @{ Name = "14-index-tall.png";        Url = (LandingUrl "index.html");                      W = 1440; H = 7200; Dsf = 1 },
    @{ Name = "15-index-mobile-tall.png"; Url = (LandingUrl "index.html");                      W = 390;  H = 6000; Dsf = 1 }
)

foreach ($j in $jobs) {
    if ($Only -and ($j.Name -notlike "*$Only*")) { continue }
    Shot -Url $j.Url -File $j.Name -W $j.W -H $j.H -Dsf $j.Dsf
}
Write-Host "done -> $outDir"