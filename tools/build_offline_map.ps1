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

# ── Preflight de la cache de fuentes de Planetiler ──────────────────────────
# Planetiler guarda los auxiliares (Natural Earth, water polygons, lake
# centerlines) en .\data\sources y NO los vuelve a descargar si el archivo
# existe, aunque este a medias. Una descarga cortada deja un ZIP cuyo final son
# ceros, y la fase que lo usa revienta con "zip END header not found" (asi murio
# water_polygons tras 18 min de descarga). Aqui se detecta leyendo el EOCD del
# final del archivo y se borra para que se vuelva a descargar.
function Test-ZipCompleto {
    param([string] $Ruta)
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($Ruta)
        # El EOCD son 22 bytes; con comentario puede quedar algo mas atras.
        # Con 4 KB de cola sobra para estos archivos, que no llevan comentario.
        $n = [int][Math]::Min(4096, $fs.Length)
        if ($n -lt 22) { return $false }
        $fs.Seek(-$n, 'End') | Out-Null
        $buf = New-Object byte[] $n
        [void]$fs.Read($buf, 0, $n)
        for ($i = 0; $i -le $n - 4; $i++) {
            if ($buf[$i] -eq 0x50 -and $buf[$i + 1] -eq 0x4B -and
                $buf[$i + 2] -eq 0x05 -and $buf[$i + 3] -eq 0x06) { return $true }
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($fs) { $fs.Dispose() }
    }
}

$candidatos = @(
    (Join-Path (Get-Location).Path 'data\sources'),
    (Join-Path $repoRoot 'data\sources')
) | Select-Object -Unique

foreach ($dirFuentes in $candidatos) {
    if (-not (Test-Path $dirFuentes)) { continue }
    foreach ($zip in Get-ChildItem $dirFuentes -Filter *.zip -File) {
        if (-not (Test-ZipCompleto $zip.FullName)) {
            $aviso = 'Cache de Planetiler corrupta: {0} ({1} MB, sin EOCD). Se borra para que se vuelva a descargar.' -f `
                $zip.Name, [math]::Round($zip.Length / 1MB, 1)
            Write-Warning $aviso
            Remove-Item -Force $zip.FullName
        } else {
            Write-Host "Cache OK: $($zip.Name)"
        }
    }
}

# ── Java ────────────────────────────────────────────────────────────────────
$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) {
    throw 'Java no esta en el PATH. Planetiler (jar) pide Java 25 o superior.'
}
# `java -version` escribe en stderr. Al redirigirlo con `2>&1` PowerShell lo
# convierte en ErrorRecord y, con $ErrorActionPreference='Stop', en un error
# terminante (NativeCommandError): el script moria justo aqui. Se baja el EA
# solo para leer la linea y se restaura de inmediato.
$eaPrevio = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$javaVersion = & java -version 2>&1 |
    Select-Object -First 1 |
    ForEach-Object { "$_" }
$ErrorActionPreference = $eaPrevio
Write-Host "Java: $javaVersion"

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

# ── Normalizacion de metadata.version ──────────────────────────────────────
# La app valida el .mbtiles con el paquete `mbtiles`, que hace
# `double.parse(metadata.version)`. Planetiler escribe la version del esquema
# OpenMapTiles ("3.16.0"), que NO es un double: el parseo lanza FormatException
# y la app rechaza el mapa con "no es un .mbtiles valido" (bug verificado
# tambien en mbtiles 0.5.1). Se deja en dos componentes ("3.16").
$sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
if (-not $sqlite) {
    $aviso = 'sqlite3 no esta en el PATH: no se puede normalizar metadata.version. ' +
        'Planetiler escribe "3.16.0" y la app rechazara el mapa. ' +
        'Instala sqlite3 o sube el archivo corregido a mano.'
    Write-Warning $aviso
} else {
    $versionRaw = & $sqlite.Source $Output "select value from metadata where name='version';"
    $versionRaw = "$versionRaw".Trim()
    if ([string]::IsNullOrWhiteSpace($versionRaw)) {
        Write-Host 'metadata.version: no existe la fila, nada que normalizar'
    } elseif ($versionRaw -match '^\d+\.\d+\.\d+') {
        $versionOk = (($versionRaw -split '\.')[0..1]) -join '.'
        & $sqlite.Source $Output "update metadata set value='$versionOk' where name='version';" | Out-Null
        Write-Host "metadata.version: '$versionRaw' -> '$versionOk' (la app hace double.parse)"
    } elseif ($versionRaw -as [double] -ne $null) {
        Write-Host "metadata.version: '$versionRaw' ya es parseable"
    } else {
        Write-Warning "metadata.version='$versionRaw' no es numerico: la app lo rechazara"
    }
}

# ── Verificacion rapida ─────────────────────────────────────────────────────
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