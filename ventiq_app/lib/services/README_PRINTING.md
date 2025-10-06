# Sistema de Impresión Multiplataforma - VentIQ Seller App

Este documento explica el nuevo sistema de impresión que funciona tanto en móvil (Bluetooth) como en web (impresoras de red/USB).

## Arquitectura del Sistema

### 1. **PlatformUtils** (`lib/utils/platform_utils.dart`)
Detecta automáticamente la plataforma de ejecución:
- `PlatformUtils.isWeb` - Detecta si es web
- `PlatformUtils.isMobile` - Detecta si es móvil
- `PlatformUtils.isDesktop` - Detecta si es desktop

### 2. **WebPrinterService** (`lib/services/web_printer_service.dart`)
Servicio específico para impresión web:
- **Funcionalidad**: Imprime usando la API del navegador
- **Compatibilidad**: Impresoras de red (WiFi/Ethernet) y USB
- **Método principal**: `printInvoice(Order order)`
- **Diálogo**: `showPrintConfirmationDialog()`

### 3. **WebPrintDialog** (`lib/widgets/web_print_dialog.dart`)
Widget de diálogo específico para web:
- **Información**: Muestra detalles de la orden
- **Instrucciones**: Guía al usuario sobre el proceso
- **Compatibilidad**: Lista tipos de impresoras soportadas

### 4. **PrinterManager** (`lib/services/printer_manager.dart`)
Servicio unificado que decide automáticamente qué tipo de impresión usar:
- **Detección automática**: Web vs Móvil
- **Método principal**: `printInvoice(BuildContext context, Order order)`
- **Resultado**: Retorna `PrintResult` con detalles del proceso

## Flujo de Funcionamiento

### En Móvil (Android/iOS):
1. Usuario confirma pago de orden
2. Sistema detecta plataforma móvil
3. Muestra diálogo de confirmación Bluetooth
4. Usuario selecciona impresora Bluetooth
5. Se conecta y envía datos ESC/POS
6. Imprime ticket térmico

### En Web (Windows/macOS/Linux):
1. Usuario confirma pago de orden
2. Sistema detecta plataforma web
3. Muestra diálogo de confirmación web
4. Genera HTML de la factura
5. Abre diálogo de impresión del navegador
6. Usuario selecciona impresora (red/USB)
7. Imprime factura formateada

## Integración en OrdersScreen

### Cambios Realizados:
```dart
// Antes (solo Bluetooth):
final BluetoothPrinterService _printerService = BluetoothPrinterService();

// Después (multiplataforma):
final PrinterManager _printerManager = PrinterManager();

// Uso unificado:
await _printerManager.printInvoice(context, order);
```

### Método Actualizado:
```dart
Future<void> _printOrderWithManager(Order order) async {
  final result = await _printerManager.printInvoice(context, order);
  
  if (result.success) {
    _showSuccessDialog('¡Factura Impresa!', result.message);
  } else {
    _showErrorDialog('Error de Impresión', result.message);
  }
}
```

## Configuración de Impresión

### UserPreferencesService:
- `isPrintEnabled()` - Verifica si la impresión está habilitada
- `setPrintEnabled(bool enabled)` - Configura la impresión

### Integración con Configuración:
```dart
Future<void> _checkAndShowPrintDialog(Order order) async {
  final isPrintEnabled = await _userPreferencesService.isPrintEnabled();
  
  if (isPrintEnabled) {
    await _printOrderWithManager(order);
  }
}
```

## Características por Plataforma

### Móvil (Bluetooth):
- ✅ Impresoras térmicas Bluetooth
- ✅ Formato ESC/POS optimizado
- ✅ Selección de dispositivos
- ✅ Gestión de conexión automática
- ❌ Impresoras de red/USB

### Web (Navegador):
- ✅ Impresoras de red (WiFi/Ethernet)
- ✅ Impresoras USB conectadas a la PC
- ✅ Impresoras predeterminadas del sistema
- ✅ Formato HTML profesional
- ✅ Diálogo nativo del navegador
- ❌ Impresoras Bluetooth

## Formato de Factura Web

### Características:
- **Diseño**: HTML/CSS profesional
- **Tipografía**: Courier New (monospace)
- **Responsive**: Se adapta al tamaño de papel
- **Información completa**:
  - Datos de la tienda
  - Información del cliente
  - Lista detallada de productos
  - Totales y subtotales
  - Fecha y hora de impresión

### Ejemplo de Estructura:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Factura - ORDER_ID</title>
    <style>/* Estilos CSS optimizados */</style>
</head>
<body>
    <div class="invoice-header"><!-- Header --></div>
    <div class="invoice-info"><!-- Datos --></div>
    <table class="products-table"><!-- Productos --></table>
    <div class="total-section"><!-- Totales --></div>
    <div class="footer"><!-- Footer --></div>
</body>
</html>
```

## Manejo de Errores

### PrintResult:
```dart
class PrintResult {
  final bool success;
  final String message;
  final String platform;
  final String? details;
}
```

### Tipos de Error:
- **Conexión**: No se puede conectar a la impresora
- **Permisos**: Sin acceso a impresoras
- **Configuración**: Impresión deshabilitada
- **Plataforma**: Funcionalidad no soportada

## Logging Implementado

### Detección de Plataforma:
```
🖨️ Plataforma detectada: Web
🖨️ Iniciando impresión con PrinterManager para orden ORDER_ID
```

### Impresión Web:
```
✅ Factura enviada a impresión web
🌐 Se abrió el diálogo de impresión del navegador
```

### Impresión Móvil:
```
📱 Conectando a impresora Bluetooth...
✅ Factura impresa correctamente via Bluetooth
```

## Beneficios del Sistema

1. **Multiplataforma**: Funciona en web y móvil automáticamente
2. **Transparente**: El usuario no nota la diferencia
3. **Optimizado**: Cada plataforma usa su mejor método
4. **Escalable**: Fácil agregar nuevos tipos de impresión
5. **Mantenible**: Código separado por responsabilidades
6. **Configurable**: Usuario puede habilitar/deshabilitar

## Uso Futuro

### Para agregar nuevos tipos de impresión:
1. Crear nuevo servicio específico (ej: `UsbPrinterService`)
2. Agregar detección en `PrinterManager`
3. Implementar lógica en `_printInvoice[Type]()`
4. Mantener compatibilidad con `PrintResult`

### Para personalizar formatos:
1. Modificar `_generateInvoiceHtml()` en `WebPrinterService`
2. Ajustar comandos ESC/POS en `BluetoothPrinterService`
3. Agregar configuraciones en `UserPreferencesService`

## Archivos del Sistema

```
lib/
├── utils/
│   └── platform_utils.dart          # Detección de plataforma
├── services/
│   ├── web_printer_service.dart     # Impresión web
│   ├── printer_manager.dart         # Gestor unificado
│   └── bluetooth_printer_service.dart # Impresión Bluetooth (existente)
├── widgets/
│   └── web_print_dialog.dart        # Diálogo web
└── screens/
    └── orders_screen.dart           # Integración principal
```

## Próximos Pasos

1. **Pruebas**: Validar en diferentes navegadores y dispositivos
2. **Configuración avanzada**: Opciones de formato, tamaño, etc.
3. **Plantillas**: Múltiples formatos de factura
4. **Impresión masiva**: Imprimir múltiples órdenes
5. **Reportes**: Impresión de reportes y estadísticas
