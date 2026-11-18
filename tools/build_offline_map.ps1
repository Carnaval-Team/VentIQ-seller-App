<#
.SYNOPSIS
    Genera el mapa offline opcional de Muevete (cuba-detalle.mbtiles) a partir
    del extracto .osm.pbf de Geofabrik y, si quieres, lo publica en Supabase.

.DESCRIPTION
    La app NO dibuja un .osm.pbf ni un .gpkg: esos son datos crudos. Solo
    consume .mbtiles con tiles vectoriales (metadata format=pbf, esquema
    OpenMapTiles), que es lo que producen los estilos que ya trae
    (assets/osm_offline_styles/).

    De los dos archivos que descarga Geofabrik, el bueno es el .osm.pbf:
      * cuba-*.osm.pbf      -> datos OSM. Entrada de este script.
      * cuba-*-free.gpkg.zip -> la misma data en formato SIG para QGIS.
                                Se puede usar, pero no aporta nada aqui.

    Planetiler convierte el .pbf en tiles en 5-20 min segun la maquina.
    El .mbtiles resultante NO se empaqueta en el APK: se importa desde el
    telefono o se sube al bucket `muevete` de Supabase para que la app lo
    ofrezca como descarga opcional.

.PARAMETER Pbf
    Ruta al extracto .osm.pbf.

.PARAMETER Output
    Ruta del .mbtiles a generar. Por defecto dist/cuba-detalle.mbtiles.

.PARAMETER MaxZoom
    Zoom maximo. 14 es lo que trae el mapa incluido; 15-16 pesa bastante mas.

.PARAMETER Memory
    Heap de la JVM. Regla de Planetiler: ~0.5x el tamano del .pbf.

.PARAMETER Upload
    Sube el resultado a Supabase Storage al terminar.

.PARAMETER ServiceKey
    service_role key. Nunca la pongas en el codigo de la app: pasala por
    variable de entorno SUPABASE_SERVICE_ROLE_KEY.

.EXAMPLE
    .\build_offline_map.ps1

.EXAMPLE
    .\build_offline_map.ps1 -Pbf "C:\Users\cesar\Downloads\hghg\cuba-261115.osm.pbf" -MaxZoom 15

.EXAMPLE
    $env:SUPABASE_SERVICE_ROLE_KEY = "eyJ..."
    .\build_offline_map.ps1 -Upload
#>
[CmdletBinding()]
param(
    [string] $Pbf = 'C:\Users\cesar\Downloads\hghg\cuba-261115.osm.pbf',
    [string] $Output = '',
    [int]    $MaxZoom = 15,
    [string] $Memory = '3g',
    [switch] $Upload,
    [string] $SupabaseUrl = 'https://vsieeihstajlrdvpuooh.supabase.co',
    [string] $Bucket = 'muevete',
    [string] $RemotePath = 'maps/cuba-detalle.mbtiles',
    [string] $ServiceKey = $env:SUPABASE_SERVICE_ROLE_KEY
)

$ErrorActionPreference = 'Stop'

# ── Rutas ────────────────────────────────────────────────────────────────────
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $repoRoot 'dist\cuba-detalle.mbtiles'
}
$Output = [System.IO.Path]::GetFullPath($Output)
$outDir = Split-Path -Parent $Output
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Host ''
Write-Host '=== Muevete · mapa offline opcional ===' -ForegroundColor Cyan
Write-Host "Entrada : $Pbf"
Write-Host "Salida  : $Output"
Write-Host "Zoom    : 0-$MaxZoom"
Write-Host ''

if (-not (Test-Path $Pbf)) {
    throw "No existe el archivo de entrada: $Pbf"
}
$pbfSizeMb = [math]::Round((Get-Item $Pbf).Length / 1MB, 1)
Write-Host "Tamano del .pbf: $pbfSizeMb MB"

# ── Java ────────────────────────────────────────────────────────────────────
$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) {
    throw 'Java no esta en el PATH. Planetiler (jar) pide Java 25 o superior.'
}
Write-Host "Java: $(& java -version 2>&1 | Select-Object -First 1)"

# ── planetiler.jar ──────────────────────────────────────────────────────────
$toolsDir = Join-Path $env:LOCALAPPDATA 'planetiler'
$jar = Join-Path $toolsDir 'planetiler.jar'
if (-not (Test-Path $jar)) {
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    $jarUrl = 'https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar'
    Write-Host "Descargando planetiler.jar -> $jar"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -fL --retry 3 -o $jar $jarUrl
    } else {
        Invoke-WebRequest -Uri $jarUrl -OutFile $jar -UseBasicParsing
    }
    if (-not (Test-Path $jar)) {
        throw "No se pudo descargar planetiler.jar desde $jarUrl"
    }
}
Write-Host "Planetiler: $jar"
Write-Host ''

# ── Conversion ──────────────────────────────────────────────────────────────
# --download baja los datos auxiliares (Natural Earth, poligonos de agua).
# Sin ellos la isla queda sin costa ni oceano.
$planetilerArgs = @(
    "-Xmx$Memory",
    '-jar', $jar,
    "--osm-path=$Pbf",
    "--output=$Output",
    "--maxzoom=$MaxZoom",
    '--download',
    '--force'
)

Write-Host 'Ejecutando Planetiler (puede tardar bastante)...' -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& java @planetilerArgs
$exit = $LASTEXITCODE
$sw.Stop()

if ($exit -ne 0) {
    throw "Planetiler fallo con codigo $exit. Revisa la salida de arriba."
}
if (-not (Test-Path $Output)) {
    throw "Planetiler termino pero no genero $Output"
}

$sizeMb = [math]::Round((Get-Item $Output).Length / 1MB, 1)
Write-Host ''
Write-Host "Listo en $([math]::Round($sw.Elapsed.TotalMinutes, 1)) min · $sizeMb MB" -ForegroundColor Green

# ── Verificacion rapida ─────────────────────────────────────────────────────
$sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
if ($sqlite) {
    $meta = & $sqlite.Source $Output "select name||'='||value from metadata where name in ('format','minzoom','maxzoom','scheme','name') order by name;"
    Write-Host 'Metadata:'
    $meta | ForEach-Object { Write-Host "  $_" }
    if (($meta -join "`n") -notmatch 'format=pbf') {
        Write-Warning 'El metadata no reporta format=pbf: la app lo rechazara al importarlo.'
    }
    $tiles = & $sqlite.Source $Output 'select count(*) from tiles;'
    Write-Host "Tiles: $tiles"
} else {
    Write-Host 'sqlite3 no esta en el PATH: sáltate la verificacion de metadata.'
}

# ── Publicacion opcional ────────────────────────────────────────────────────
if ($Upload) {
    if ([string]::IsNullOrWhiteSpace($ServiceKey)) {
        throw 'Falta la service_role key. Define $env:SUPABASE_SERVICE_ROLE_KEY o pasa -ServiceKey.'
    }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw 'curl.exe no esta disponible para subir el archivo.'
    }
    $url = "$SupabaseUrl/storage/v1/object/$Bucket/$RemotePath"
    Write-Host ''
    Write-Host "Subiendo a $Bucket/$RemotePath ..." -ForegroundColor Yellow
    & curl.exe -sS -X PUT $url `
        -H "apikey: $ServiceKey" `
        -H "Authorization: Bearer $ServiceKey" `
        -H 'x-upsert: true' `
        -H 'Content-Type: application/octet-stream' `
        --data-binary "@$Output"
    if ($LASTEXITCODE -ne 0) {
        throw "La subida fallo con codigo $LASTEXITCODE"
    }
    Write-Host 'Subido.' -ForegroundColor Green
}

# ── Siguientes pasos ────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Siguiente paso:' -ForegroundColor Cyan
Write-Host '  1) Copia el .mbtiles al telefono (por cable, Drive, WhatsApp...).'
Write-Host '  2) En la app: Mi Perfil -> Mapa Offline -> "Cuba detallado (OSM reciente)"'
Write-Host '     -> "Importar archivo".'
Write-Host '  3) O publica una vez con -Upload y luego basta con tocar la fuente'
Write-Host '     y pulsar "Descargar" (no hay que tocar el telefono).'
Write-Host ''
Write-Host 'NO lo pongas en inventtia_muevete\assets\tiles\: se empaquetaria en el'
Write-Host 'APK y pesaria cientos de MB. La carpeta assets solo lleva el mapa base.'