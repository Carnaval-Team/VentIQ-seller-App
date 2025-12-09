# Script de Build y Deploy para Flutter APK a Supabase
# Uso: .\build_and_deploy.ps1 -AppFolder "ventiq_app" -ApkName "vendedor cuba"

param(
    [Parameter(Mandatory=$true)]
    [string]$AppFolder,
    
    [Parameter(Mandatory=$true)]
    [string]$ApkName
)

# Configuración de colores
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

# Obtener directorio del script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppPath = Join-Path $ScriptDir $AppFolder

# Validar que la carpeta existe
if (-not (Test-Path $AppPath)) {
    Write-Error-Custom "La carpeta $AppFolder no existe"
    exit 1
}

Write-Info "Iniciando proceso de build y deploy para $AppFolder"
Write-Host ""

# ============================================
# PASO 1: Build del APK
# ============================================
Write-Info "PASO 1/5: Compilando APK en modo release..."
Push-Location $AppPath

try {
    flutter build apk --release
    if ($LASTEXITCODE -eq 0) {
        Write-Success "APK compilado exitosamente"
    } else {
        throw "Falló la compilación del APK"
    }
} catch {
    Write-Error-Custom "Error durante la compilación: $_"
    Pop-Location
    exit 1
}
Write-Host ""

# ============================================
# PASO 2: Renombrar APK
# ============================================
Write-Info "PASO 2/5: Renombrando APK..."
$ApkSource = Join-Path $AppPath "build\app\outputs\flutter-apk\app-release.apk"
$ApkTemp = Join-Path $AppPath "build\app\outputs\flutter-apk\$ApkName.apk"

if (-not (Test-Path $ApkSource)) {
    Write-Error-Custom "No se encontró el APK en: $ApkSource"
    Pop-Location
    exit 1
}

Copy-Item $ApkSource $ApkTemp -Force
Write-Success "APK renombrado a: $ApkName.apk"
Write-Host ""

# ============================================
# PASO 3: Leer configuración de Supabase
# ============================================
Write-Info "PASO 3/5: Leyendo configuración de Supabase..."
$SupabaseConfigPath = Join-Path $AppPath "lib\config\supabase_config.dart"

if (-not (Test-Path $SupabaseConfigPath)) {
    Write-Warning "No se encontró supabase_config.dart, usando variables de entorno"
    $SupabaseUrl = $env:SUPABASE_URL
    $SupabaseKey = $env:SUPABASE_ANON_KEY
} else {
    # Leer archivo Dart y extraer configuración
    $ConfigContent = Get-Content $SupabaseConfigPath -Raw
    
    # Extraer URL (buscar patrón: supabaseUrl = 'https://...')
    if ($ConfigContent -match "supabaseUrl\s*=\s*'([^']+)'") {
        $SupabaseUrl = $matches[1]
        Write-Success "URL de Supabase encontrada"
    } elseif ($ConfigContent -match 'supabaseUrl\s*=\s*"([^"]+)"') {
        $SupabaseUrl = $matches[1]
        Write-Success "URL de Supabase encontrada"
    } else {
        Write-Warning "No se pudo extraer URL de Supabase del archivo de configuración"
        $SupabaseUrl = $env:SUPABASE_URL
    }
    
    # Extraer Key (buscar patrón: supabaseAnonKey = '...')
    if ($ConfigContent -match "supabaseAnonKey\s*=\s*'([^']+)'") {
        $SupabaseKey = $matches[1]
        Write-Success "Anon Key de Supabase encontrada"
    } elseif ($ConfigContent -match 'supabaseAnonKey\s*=\s*"([^"]+)"') {
        $SupabaseKey = $matches[1]
        Write-Success "Anon Key de Supabase encontrada"
    } else {
        Write-Warning "No se pudo extraer Anon Key de Supabase del archivo de configuración"
        $SupabaseKey = $env:SUPABASE_ANON_KEY
    }
}

if (-not $SupabaseUrl -or -not $SupabaseKey) {
    Write-Error-Custom "No se pudo obtener la configuración de Supabase"
    Write-Info "Asegúrate de tener configurado supabase_config.dart o las variables de entorno"
    Pop-Location
    exit 1
}

Write-Host ""

# ============================================
# PASO 4: Subir a Supabase Storage
# ============================================
Write-Info "PASO 4/5: Subiendo APK a Supabase bucket 'apk'..."

# Obtener tamaño del archivo
$FileSize = (Get-Item $ApkTemp).Length
$FileSizeMB = [math]::Round($FileSize / 1MB, 2)
Write-Info "Tamaño del archivo: $FileSizeMB MB"

# Nombre temporal con (1)
$TempName = "$ApkName (1).apk"
$BucketPath = "apk/$TempName"

# Leer archivo como bytes
$FileBytes = [System.IO.File]::ReadAllBytes($ApkTemp)

# Subir a Supabase usando API REST
$UploadUrl = "$SupabaseUrl/storage/v1/object/$BucketPath"
$Headers = @{
    "Authorization" = "Bearer $SupabaseKey"
    "Content-Type" = "application/octet-stream"
}

Write-Info "Subiendo a: $BucketPath"
Write-Info "Esto puede tomar varios minutos dependiendo de tu conexión..."

try {
    # Mostrar progreso
    $ProgressPreference = 'Continue'
    
    $Response = Invoke-RestMethod -Uri $UploadUrl -Method Post -Headers $Headers -Body $FileBytes -ContentType "application/octet-stream"
    
    Write-Success "APK subido exitosamente a Supabase"
} catch {
    Write-Error-Custom "Error al subir APK: $_"
    Write-Info "Detalles: $($_.Exception.Message)"
    Pop-Location
    exit 1
}
Write-Host ""

# ============================================
# PASO 5: Gestionar archivos en bucket
# ============================================
Write-Info "PASO 5/5: Gestionando archivos en el bucket..."

# Eliminar archivo antiguo si existe
$OldFilePath = "apk/$ApkName.apk"
$DeleteUrl = "$SupabaseUrl/storage/v1/object/$OldFilePath"

try {
    Write-Info "Eliminando archivo antiguo (si existe)..."
    Invoke-RestMethod -Uri $DeleteUrl -Method Delete -Headers $Headers -ErrorAction SilentlyContinue
    Write-Success "Archivo antiguo eliminado"
} catch {
    Write-Warning "No se encontró archivo antiguo o ya fue eliminado"
}

# Renombrar archivo nuevo
$MoveUrl = "$SupabaseUrl/storage/v1/object/move"
$MoveBody = @{
    bucketId = "apk"
    sourceKey = $TempName
    destinationKey = "$ApkName.apk"
} | ConvertTo-Json

$MoveHeaders = $Headers.Clone()
$MoveHeaders["Content-Type"] = "application/json"

try {
    Write-Info "Renombrando archivo..."
    Invoke-RestMethod -Uri $MoveUrl -Method Post -Headers $MoveHeaders -Body $MoveBody
    Write-Success "Archivo renombrado correctamente"
} catch {
    Write-Error-Custom "Error al renombrar archivo: $_"
    Write-Warning "Es posible que necesites renombrar manualmente en Supabase Dashboard"
    Write-Info "Renombrar: '$TempName' → '$ApkName.apk'"
}

Write-Host ""

# ============================================
# PASO 6: Leer y mostrar información del changelog
# ============================================
Write-Info "PASO 6/6: Leyendo información de la versión..."
$ChangelogPath = Join-Path $AppPath "assets\changelog.json"

if (-not (Test-Path $ChangelogPath)) {
    Write-Error-Custom "No se encontró changelog.json en: $ChangelogPath"
    Pop-Location
    exit 1
}

# Leer JSON
$Changelog = Get-Content $ChangelogPath -Raw | ConvertFrom-Json
$AppName = $Changelog.app_name
$Version = $Changelog.current_version
$Build = $Changelog.build

Pop-Location

# Mostrar resumen final
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    BUILD COMPLETADO                        ║" -ForegroundColor Cyan
Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  App:      $AppName" -ForegroundColor White
Write-Host "║  Versión:  $Version" -ForegroundColor White
Write-Host "║  Build:    $Build" -ForegroundColor White
Write-Host "║  APK:      $ApkName.apk" -ForegroundColor White
Write-Host "║  Tamaño:   $FileSizeMB MB" -ForegroundColor White
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Success "Proceso completado exitosamente!"
Write-Info "APK disponible en Supabase Storage: apk/$ApkName.apk"
Write-Host ""

exit 0
