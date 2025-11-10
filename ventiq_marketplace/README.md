# VentIQ Marketplace

Marketplace para vender productos de todas las tiendas registradas en VentIQ.

## 🎯 Descripción

VentIQ Marketplace es una aplicación Flutter que permite a los usuarios explorar y comprar productos de múltiples tiendas registradas en el ecosistema VentIQ. La aplicación está diseñada con un enfoque moderno y elegante, inspirada en los mejores marketplaces del mercado.

## ✨ Características Principales

### Home Screen
- **Productos Más Vendidos**: Sección horizontal con los productos más populares
- **Tiendas Destacadas**: Tiendas con mejor rendimiento y más ventas
- **Buscador Inteligente**: Búsqueda de productos y tiendas en tiempo real
- **Diseño Responsivo**: Optimizado para todas las plataformas

### Navegación Global
- **Home**: Pantalla principal con destacados
- **Tiendas**: Explorar todas las tiendas disponibles
- **Productos**: Catálogo completo de productos
- **Carrito**: Gestión de compras

## 🎨 Diseño

La aplicación utiliza el mismo esquema de colores que VentIQ App para mantener consistencia visual en todo el ecosistema.

### Colores Principales
- **Primario**: Azul VentIQ (#4A90E2)
- **Secundario**: Teal (#009688)
- **Acento**: Verde (#4CAF50)
- **Advertencia**: Naranja (#FF9800)

## 🚀 Tecnologías

- **Flutter**: Framework principal
- **Material Design 3**: Sistema de diseño
- **Dart**: Lenguaje de programación

## 📱 Estructura del Proyecto

```
lib/
├── config/
│   └── app_theme.dart          # Tema y colores
├── screens/
│   ├── main_screen.dart        # Navegación principal
│   ├── home_screen.dart        # Pantalla de inicio
│   ├── stores_screen.dart      # Pantalla de tiendas
│   ├── products_screen.dart    # Pantalla de productos
│   └── cart_screen.dart        # Pantalla de carrito
├── widgets/
│   ├── product_card.dart       # Tarjeta de producto
│   ├── store_card.dart         # Tarjeta de tienda
│   └── search_bar_widget.dart  # Barra de búsqueda
└── main.dart                   # Punto de entrada
```

## 🛠️ Instalación

1. Clonar el repositorio
2. Instalar dependencias:
   ```bash
   flutter pub get
   ```
3. Ejecutar la aplicación:
   ```bash
   flutter run
   ```

## 📋 Próximas Funcionalidades

- [ ] Integración con backend de VentIQ
- [ ] Sistema de autenticación
- [ ] Procesamiento de pagos
- [ ] Gestión de pedidos
- [ ] Notificaciones push
- [ ] Sistema de reviews y ratings
- [ ] Filtros avanzados de búsqueda
- [ ] Wishlist
- [ ] Historial de compras

## 👥 Equipo

Desarrollado por el equipo de VentIQ

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
