#!/bin/bash

# Script para build y deploy de APK a Supabase
# Uso: ./build_and_deploy.sh <carpeta_app> <nombre_apk>
# Ejemplo: ./build_and_deploy.sh ventiq_app "vendedor cuba"

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Validar parámetros
if [ $# -lt 2 ]; then
    log_error "Faltan parámetros"
    echo "Uso: $0 <carpeta_app> <nombre_apk>"
    echo "Ejemplo: $0 ventiq_app \"vendedor cuba\""
    exit 1
fi

APP_FOLDER="$1"
APK_NAME="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$SCRIPT_DIR/$APP_FOLDER"

# Validar que la carpeta existe
if [ ! -d "$APP_PATH" ]; then
    log_error "La carpeta $APP_FOLDER no existe"
    exit 1
fi

log_info "Iniciando proceso de build y deploy para $APP_FOLDER"
echo ""

# ============================================
# PASO 1: Build del APK
# ============================================
log_info "PASO 1/5: Compilando APK en modo release..."
cd "$APP_PATH"

if flutter build apk --release; then
    log_success "APK compilado exitosamente"
else
    log_error "Falló la compilación del APK"
    exit 1
fi
echo ""

# ============================================
# PASO 2: Renombrar APK
# ============================================
log_info "PASO 2/5: Renombrando APK..."
APK_SOURCE="$APP_PATH/build/app/outputs/flutter-apk/app-release.apk"
APK_TEMP="$APP_PATH/build/app/outputs/flutter-apk/${APK_NAME}.apk"

if [ ! -f "$APK_SOURCE" ]; then
    log_error "No se encontró el APK en: $APK_SOURCE"
    exit 1
fi

# Copiar con el nuevo nombre
cp "$APK_SOURCE" "$APK_TEMP"
log_success "APK renombrado a: ${APK_NAME}.apk"
echo ""

# ============================================
# PASO 3: Subir a Supabase
# ============================================
log_info "PASO 3/5: Subiendo APK a Supabase bucket 'apk'..."

# Verificar que Supabase CLI esté instalado
# if ! command -v supabase &> /dev/null; then
#     log_error "Supabase CLI no está instalado"
#     log_info "Instala con: npm install -g supabase"
#     exit 1
# fi

# Obtener tamaño del archivo para progreso
FILE_SIZE=$(stat -f%z "$APK_TEMP" 2>/dev/null || stat -c%s "$APK_TEMP" 2>/dev/null)
FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
log_info "Tamaño del archivo: ${FILE_SIZE_MB} MB"

# Subir con nombre temporal (nombre (1).apk)
TEMP_NAME="${APK_NAME} (1).apk"
log_info "Subiendo como: $TEMP_NAME"

# Mostrar progreso (Supabase CLI muestra su propio progreso)
# if supabase storage upload apk "$APK_TEMP" --bucket-id apk --upsert; then
#     log_success "APK subido exitosamente"
# else
#     log_error "Falló la subida del APK"
#     exit 1
# fi
# echo ""

# ============================================
# PASO 4: Gestionar archivos en bucket
# ============================================
log_info "PASO 4/5: Gestionando archivos en el bucket..."

# Nota: Supabase CLI tiene limitaciones para renombrar/eliminar
# Necesitamos usar la API REST de Supabase para esto
log_warning "Este paso requiere configuración adicional de Supabase"
log_info "Pasos manuales necesarios:"
echo "  1. Ir a Supabase Dashboard > Storage > apk"
echo "  2. Eliminar archivo antiguo: ${APK_NAME}.apk (si existe)"
echo "  3. Renombrar ${TEMP_NAME} a ${APK_NAME}.apk"
echo ""

# Alternativa: Si tienes las credenciales de Supabase configuradas
# Descomentar y configurar estas líneas:
SUPABASE_URL="https://vsieeihstajlrdvpuooh.supabase.co"
SUPABASE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8"

# Eliminar archivo antiguo
curl -X DELETE "${SUPABASE_URL}/storage/v1/object/apk/${APK_NAME}.apk" \
  -H "Authorization: Bearer ${SUPABASE_KEY}"

# Renombrar archivo nuevo
curl -X POST "${SUPABASE_URL}/storage/v1/object/move" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"bucketId\":\"apk\",\"sourceKey\":\"${TEMP_NAME}\",\"destinationKey\":\"${APK_NAME}.apk\"}"

log_info "Nota: Puedes automatizar esto configurando las variables SUPABASE_URL y SUPABASE_KEY"
echo ""

# ============================================
# PASO 5: Leer y mostrar información del changelog
# ============================================
log_info "PASO 5/5: Leyendo información de la versión..."
CHANGELOG_PATH="$APP_PATH/assets/changelog.json"

if [ ! -f "$CHANGELOG_PATH" ]; then
    log_error "No se encontró changelog.json en: $CHANGELOG_PATH"
    exit 1
fi

# Leer usando jq si está disponible, sino usar grep/sed básico
if command -v jq &> /dev/null; then
    APP_NAME=$(jq -r '.app_name' "$CHANGELOG_PATH")
    VERSION=$(jq -r '.current_version' "$CHANGELOG_PATH")
    BUILD=$(jq -r '.build' "$CHANGELOG_PATH")
else
    log_warning "jq no está instalado, usando parsing básico"
    APP_NAME=$(grep -o '"app_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$CHANGELOG_PATH" | sed 's/.*: "\(.*\)".*/\1/')
    VERSION=$(grep -o '"current_version"[[:space:]]*:[[:space:]]*"[^"]*"' "$CHANGELOG_PATH" | sed 's/.*: "\(.*\)".*/\1/')
    BUILD=$(grep -o '"build"[[:space:]]*:[[:space:]]*[0-9]*' "$CHANGELOG_PATH" | sed 's/.*: \(.*\)/\1/')
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETADO                        ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  App:      ${APP_NAME}"
echo "║  Versión:  ${VERSION}"
echo "║  Build:    ${BUILD}"
echo "║  APK:      ${APK_NAME}.apk"
echo "║  Tamaño:   ${FILE_SIZE_MB} MB"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_success "Proceso completado exitosamente!"
log_info "APK disponible en: $APK_TEMP"

# Limpiar APK temporal (opcional)
# rm "$APK_TEMP"

exit 0
