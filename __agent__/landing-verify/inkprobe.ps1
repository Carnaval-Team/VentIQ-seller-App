# Pixel-level proof of the gradient-clip letterform bug, take 2.
#
# The page paints <em> with background-clip:text + transparent fill and NO horizontal padding,
# so any glyph ink outside the padding box is never painted. Neighbouring hero words are hidden
# so the crop contains ONLY the "opera" glyphs, and the metric counts ink that exists in the
# CONTROL (same page with extra horizontal padding => guaranteed no clip) but is missing from the
# TEST (the page as shipped), split into "inside the em content box" (noise) and
# "outside the em content box" (real clipping).
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File __agent__/landing-verify/inkprobe.ps1 -Label x [-Landing path]
param(
    [string]$Label = "baseline",
    [string]$Landing = ""
)
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Landing) { $landing = (Resolve-Path $Landing).Path } else { $landing = Join-Path $root "ventiq_landing" }
$outDir = Join-Path $root "__agent__\landing-verify\ink-$Label"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$baseHref = "file:///" + ($landing -replace '\\', '/') + "/"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$DSF = 4

# Hide every other glyph in the headline so only the <em> paints; freeze all motion.
$COMMON = '*{animation:none!important;transition:none!important}' +
          '.v2-hero h1 .word{visibility:hidden!important;overflow:visible!important}' +
          '.v2-hero h1 br{visibility:hidden!important}' +
          '.v2-hero h1 .word-inner{transform:none!important;opacity:1!important}'
# CONTROL: same element, same gradient, but a padding box wide enough that nothing can be clipped.
$CONTROL = $COMMON + '.v2-hero h1 em{padding-inline:.45em!important;margin-inline:-.45em!important}'

$MEASURE = @'
function R2(el){var r=el.getBoundingClientRect();return {t:r.top,l:r.left,w:r.width,h:r.height,r:r.right,b:r.bottom};}
setTimeout(function(){
  var el=document.querySelector('.v2-hero h1 em');
  var cs=getComputedStyle(el);
  var pre=document.createElement('pre');pre.id='__probe';
  pre.textContent=JSON.stringify({em:R2(el),w:innerWidth,h:innerHeight,
    padL:cs.paddingLeft,padR:cs.paddingRight,marL:cs.marginLeft,marR:cs.marginRight,
    ls:cs.letterSpacing,fs:cs.fontSize,
    clip:cs.webkitBackgroundClip||cs.backgroundClip,fill:cs.webkitTextFillColor||cs.color,
    bg:cs.backgroundImage.slice(0,90)});
  document.body.appendChild(pre);
},1200);
'@

function Build([string]$name, [string]$css) {
    $html = Get-Content -Raw -LiteralPath (Join-Path $landing "index.html")
    $html = $html -replace '(?i)(<head[^>]*>)', ('$1' + "`n<base href=`"$baseHref`"><style>$css</style>")
    $html = $html -replace '(?i)(</body>)', ("<script>`n$MEASURE`n</script>`n" + '$1')
    $p = Join-Path $outDir "$name.html"
    [System.IO.File]::WriteAllText($p, $html, $utf8)
    return $p
}

$ctrl = Build "control" $CONTROL
$test = Build "test" $COMMON

foreach ($p in @($ctrl, $test)) {
    $name = [IO.Path]::GetFileNameWithoutExtension($p)
    $url = "file:///" + ($p -replace '\\', '/')
    & $chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars --blink-settings=preferredColorScheme=1 `
        --force-device-scale-factor=$DSF --virtual-time-budget=6000 --window-size=1440,900 `
        --screenshot="$(Join-Path $outDir "$name.png")" $url 2>$null | Out-Null
    Write-Host "shot -> $name.png"
}

$url = "file:///" + ($test -replace '\\', '/')
$dom = & $chrome --headless=new --disable-gpu --no-sandbox --blink-settings=preferredColorScheme=1 `
    --force-device-scale-factor=$DSF --virtual-time-budget=6000 --window-size=1440,900 --dump-dom $url 2>$null | Out-String
$m = [regex]::Match($dom, '(?s)<pre id="__probe">(.*?)</pre>')
$json = if ($m.Success) { [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) } else { "{}" }
$geomFile = Join-Path $outDir "geometry.json"
[System.IO.File]::WriteAllText($geomFile, $json, $utf8)

$py = $env:PY
if (-not $py -or -not (Test-Path $py)) { $py = "C:\Users\cesar\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" }
& $py (Join-Path $PSScriptRoot "inkdiff.py") (Join-Path $outDir "control.png") (Join-Path $outDir "test.png") $geomFile $DSF