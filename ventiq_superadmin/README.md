# Inventtia Super Admin

Sistema de administración global para la plataforma VentIQ, optimizado para web y desktop con soporte responsive para móviles.

## 🚀 Características

### ✅ Implementado
- **Login Moderno**: Pantalla de autenticación centrada y responsive
- **Dashboard Ejecutivo**: KPIs, gráficos y métricas globales
- **Gestión de Tiendas**: CRUD completo con filtros y estadísticas
- **Gestión de Usuarios**: Administración de usuarios con roles y permisos
- **Navegación Intuitiva**: Drawer con navegación organizada por secciones
- **Diseño Responsive**: Optimizado para desktop, tablet y móvil
- **Tema Personalizado**: Colores y componentes consistentes

### 🔄 En Desarrollo
- **Gestión de Licencias**: Renovaciones y vencimientos
- **Administradores de Tienda**: CRUD de administradores
- **Almacenes y Almaceneros**: Gestión de almacenes
- **TPVs y Vendedores**: Administración de puntos de venta
- **Trabajadores**: Gestión integral de empleados
- **Reportes**: Análisis y estadísticas avanzadas
- **Configuración**: Ajustes del sistema

## 🏗️ Arquitectura

### Estructura del Proyecto
```
lib/
├── config/          # Configuración de temas y colores
├── models/          # Modelos de datos
├── screens/         # Pantallas de la aplicación
├── services/        # Servicios y lógica de negocio
├── utils/           # Utilidades y helpers
└── widgets/         # Componentes reutilizables
```

### Tecnologías Utilizadas
- **Flutter 3.8+**: Framework multiplataforma
- **Material Design 3**: Sistema de diseño moderno
- **FL Chart**: Gráficos y visualizaciones
- **Syncfusion Charts**: Gráficos avanzados
- **Universal Platform**: Detección de plataforma
- **Shared Preferences**: Almacenamiento local

## 🎨 Diseño

### Paleta de Colores
- **Primario**: Verde VentIQ (#2E7D32)
- **Secundario**: Azul (#1976D2)
- **Éxito**: Verde (#4CAF50)
- **Advertencia**: Naranja (#FF9800)
- **Error**: Rojo (#F44336)
- **Información**: Azul claro (#2196F3)

### Responsive Design
- **Desktop (>1200px)**: Layout de 4-6 columnas, navegación completa
- **Tablet (768-1200px)**: Layout de 2-4 columnas, navegación adaptada
- **Móvil (<768px)**: Layout de 1-2 columnas, navegación móvil

## 🔐 Autenticación

### Credenciales de Prueba
- **Email**: admin@ventiq.com
- **Contraseña**: admin123
- **Rol**: Super Administrador

### Roles del Sistema
- **Super Admin**: Acceso completo al sistema
- **Admin Tienda**: Gestión de tienda específica
- **Gerente**: Operaciones de tienda
- **Supervisor**: Supervisión de operaciones

## 📊 Dashboard

### KPIs Principales
- **Total de Tiendas**: Tiendas registradas en el sistema
- **Tiendas Activas**: Tiendas en funcionamiento
- **Renovaciones Pendientes**: Licencias próximas a vencer
- **Ventas Globales**: Ingresos totales del mes

### Gráficos
- **Registro de Tiendas**: Tendencia mensual de nuevas tiendas
- **Ventas Globales**: Comparativo mensual de ingresos
- **Actividad Reciente**: Log de eventos importantes

## 🏪 Gestión de Tiendas

### Funcionalidades
- **Lista Completa**: Visualización de todas las tiendas
- **Filtros Avanzados**: Por estado, licencia, ubicación
- **Búsqueda**: Por nombre o ubicación
- **Estadísticas**: Contadores por estado
- **Acciones**: Ver, editar, eliminar tiendas

### Estados de Tienda
- **Activa**: Funcionando normalmente
- **Suspendida**: Temporalmente deshabilitada
- **Inactiva**: Fuera de servicio

## 👥 Gestión de Usuarios

### Funcionalidades
- **Lista de Usuarios**: Todos los usuarios del sistema
- **Filtros por Rol**: Super Admin, Admin Tienda, etc.
- **Estados**: Activos e inactivos
- **Acciones**: Ver, editar, cambiar contraseña, activar/desactivar

### Información de Usuario
- **Datos Personales**: Nombre, email, rol
- **Tiendas Asignadas**: Tiendas bajo su gestión
- **Último Acceso**: Actividad reciente
- **Estado**: Activo/Inactivo

## 🚀 Instalación y Configuración

### Requisitos
- Flutter 3.8 o superior
- Dart 3.0 o superior

### Instalación
```bash
# Clonar el repositorio
git clone [repository-url]

# Navegar al directorio
cd ventiq_superadmin

# Instalar dependencias
flutter pub get

# Ejecutar la aplicación
flutter run -d chrome  # Para web
flutter run -d windows # Para Windows
```

### Configuración de Desarrollo
```bash
# Habilitar web
flutter config --enable-web

# Habilitar desktop
flutter config --enable-windows-desktop
flutter config --enable-macos-desktop
flutter config --enable-linux-desktop
```

## 🔧 Configuración

### Variables de Entorno
- Configurar conexión a Supabase (pendiente)
- URLs de API (pendiente)
- Claves de encriptación (pendiente)

### Base de Datos
- **Desarrollo**: Datos mock integrados
- **Producción**: Integración con Supabase (pendiente)

## 📱 Plataformas Soportadas

### Principales
- ✅ **Web**: Chrome, Firefox, Safari, Edge
- ✅ **Windows**: Aplicación nativa
- ✅ **macOS**: Aplicación nativa
- ✅ **Linux**: Aplicación nativa

### Secundarias
- ✅ **Android**: APK para tablets
- ✅ **iOS**: App para iPads

## 🎯 Roadmap

### Fase 1 (Actual) ✅
- [x] Estructura base del proyecto
- [x] Sistema de autenticación
- [x] Dashboard principal
- [x] Gestión de tiendas
- [x] Gestión de usuarios

### Fase 2 (Próxima)
- [ ] Integración con Supabase
- [ ] Gestión de licencias
- [ ] Administradores de tienda
- [ ] Sistema de notificaciones

### Fase 3 (Futura)
- [ ] Reportes avanzados
- [ ] Análisis predictivo
- [ ] API REST completa
- [ ] Aplicación móvil nativa

## 🤝 Contribución

### Estándares de Código
- Seguir las convenciones de Dart/Flutter
- Documentar funciones públicas
- Mantener consistencia en el diseño
- Probar en múltiples plataformas

### Proceso de Desarrollo
1. Crear branch desde `main`
2. Implementar funcionalidad
3. Probar en web y desktop
4. Crear pull request
5. Review y merge

## 📄 Licencia

Proyecto privado de VentIQ. Todos los derechos reservados.

## 📞 Soporte

Para soporte técnico o consultas:
- **Email**: dev@ventiq.com
- **Documentación**: [Pendiente]
- **Issues**: [Pendiente]

---

**Inventtia Super Admin v1.0.0** - Sistema de Administración Global

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
