import 'package:flutter/material.dart';

import '../services/home_catalog_service.dart';

/// Icono de una categoría o subcategoría del nomenclador.
///
/// Vive aquí y no en el Home porque lo necesitan tres sitios: el riel/la
/// rejilla del Home, la tarjeta del feed y la pantalla de categorías. Antes era
/// una función privada de `home_client_screen.dart` y cualquier pantalla nueva
/// habría tenido que copiarla.
///
/// Cubre los dos juegos de códigos: los de la taxonomía REAL de la migración 47
/// (`alojamiento`, `gastronomia`, `belleza`, `transporte`, `recreacion`,
/// `juridicos`) y los que quedaron como subcategorías o como código legado
/// (`unas`, `cejas_pestanas`, `transporte_omnibus`...). Un código nuevo creado
/// desde el panel cae al icono genérico sin romper nada.
IconData iconoCategoria(HomeCatalogCategory category) =>
    iconoCategoriaPorCodigo(category.codigo);

/// Igual que [iconoCategoria] pero desde el código suelto.
IconData iconoCategoriaPorCodigo(String? codigo) =>
    switch (codigo?.trim() ?? '') {
      'general' => Icons.grid_view_rounded,
      // Taxonomía real (migración 47).
      'alojamiento' => Icons.hotel_outlined,
      'gastronomia' => Icons.restaurant_outlined,
      'belleza' => Icons.auto_awesome_rounded,
      'transporte' => Icons.directions_car_filled_outlined,
      'recreacion' => Icons.attractions_outlined,
      'juridicos' => Icons.gavel_rounded,
      // Subcategorías y códigos heredados.
      'unas' => Icons.back_hand_rounded,
      'cejas_pestanas' => Icons.remove_red_eye_outlined,
      'peluqueria' => Icons.content_cut_rounded,
      'estetica_spa' => Icons.spa_outlined,
      'salud' => Icons.medical_services_outlined,
      'hogar' => Icons.home_repair_service_outlined,
      'mascotas' => Icons.pets_outlined,
      'eventos' => Icons.celebration_outlined,
      'tecnologia' => Icons.devices_other_outlined,
      'transporte_omnibus' => Icons.directions_bus_filled_outlined,
      'transporte_privado' => Icons.local_taxi_outlined,
      'talleres_gasolineras' => Icons.local_gas_station_outlined,
      _ => Icons.category_outlined,
    };