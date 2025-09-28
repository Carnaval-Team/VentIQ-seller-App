# Vendedor Cuba Admin App

Sistema de administración completo para VentIQ que permite gestionar productos, inventarios, ventas, finanzas y más.

## Características

### 🎨 Diseño Consistente
- Utiliza los mismos colores y estilos de la app VentIQ principal
- Color principal: `#4A90E2` (azul VentIQ)
- Material 3 con componentes modernos
- Navegación intuitiva con drawer y bottom navigation

### 📊 Módulos Implementados
- **Dashboard Ejecutivo**: KPIs y métricas clave
- **Gestión de Productos**: Catálogo completo con búsqueda
- **Control de Inventario**: Niveles de stock y alertas
- **Gestión de Categorías**: Organización jerárquica
- **Monitoreo de Ventas**: Análisis en tiempo real
- **Gestión Financiera**: Control de gastos y reportes
- **CRM Clientes**: Historial y fidelización
- **Recursos Humanos**: Gestión de personal
- **Configuración**: Ajustes del sistema

## Estructura del Proyecto

```
lib/
├── config/
│   ├── app_colors.dart          # Sistema de colores VentIQ
│   └── supabase_config.dart     # Configuración de Supabase
├── screens/
│   ├── dashboard_screen.dart    # Dashboard principal
│   ├── products_screen.dart     # Gestión de productos
│   ├── categories_screen.dart   # Gestión de categorías
│   ├── inventory_screen.dart    # Control de inventario
│   ├── sales_screen.dart        # Monitoreo de ventas
│   ├── financial_screen.dart    # Gestión financiera
│   ├── customers_screen.dart    # CRM clientes
│   ├── workers_screen.dart      # Gestión de personal
│   ├── warehouse_screen.dart    # Gestión de almacenes
│   ├── settings_screen.dart     # Configuración
│   └── login_screen.dart        # Autenticación
├── widgets/
│   ├── admin_drawer.dart        # Menú lateral
│   ├── admin_bottom_navigation.dart # Navegación inferior
│   └── admin_card.dart          # Componentes reutilizables
└── main.dart                    # Punto de entrada
```

## Dependencias

- `flutter`: Framework principal
- `supabase_flutter`: Backend y autenticación
- `fl_chart`: Gráficos y visualización de datos
- `file_picker`: Manejo de archivos
- `shared_preferences`: Almacenamiento local

## Instalación

1. Clonar el repositorio
2. Ejecutar `flutter pub get`
3. Configurar credenciales de Supabase en `lib/config/supabase_config.dart`
4. Ejecutar `flutter run`

## Estado Actual

✅ **Estructura base completada**
- Sistema de colores y temas
- Navegación y routing
- Dashboard con KPIs mock
- Pantallas base para todos los módulos

🚧 **Por implementar**
- Integración completa con Supabase
- Funcionalidades CRUD específicas
- Gráficos con fl_chart
- Sistema de autenticación
- Validaciones y manejo de errores

## Próximos Pasos

1. Implementar autenticación con Supabase
2. Crear servicios para cada módulo
3. Desarrollar funcionalidades CRUD
4. Agregar gráficos y reportes
5. Implementar sistema de permisos
