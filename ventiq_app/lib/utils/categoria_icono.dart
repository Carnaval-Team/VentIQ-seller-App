import 'package:flutter/material.dart';

/// Icono de una categoría o subcategoría del catálogo del TPV.
///
/// Vive en `utils/` y no como función privada de una pantalla porque lo
/// necesitan al menos tres sitios: la rejilla del Home, la tarjeta de "Tienda"
/// y las tarjetas del drawer. Antes cada pantalla tenía su propia copia del
/// `switch` (`categories_screen.dart` y `categories_web_screen.dart`), con
/// listas distintas, así que la misma categoría salía con dos iconos según la
/// plataforma.
///
/// El mapeo es por **palabras clave en español**, sin acentos y sobre el nombre
/// en minúsculas, porque el catálogo real está lleno de variantes ("Bebidas",
/// "bebida", "BEBIDAS FRÍAS"). Un nombre que no encaje en ninguna regla cae al
/// icono genérico sin romper nada: **añadir una categoría nueva nunca debe
/// requerir tocar este archivo**.
IconData iconoCategoria(String? nombre, {String? skuCodigo}) {
  return iconoCategoriaPorTexto(nombre) ??
      iconoCategoriaPorTexto(skuCodigo) ??
      Icons.category_outlined;
}

/// Igual que [iconoCategoria] pero desde un texto suelto (nombre o código).
/// Devuelve `null` cuando no reconoce nada, para poder encadenar búsquedas.
IconData? iconoCategoriaPorTexto(String? texto) {
  final String t = _normalizar(texto);
  if (t.isEmpty) return null;

  for (final _ReglaCategoria regla in _reglas) {
    if (regla.coincide(t)) return regla.icono;
  }
  return null;
}

/// Minúsculas y sin acentos, para que "Electrónica" y "electronica" coincidan.
///
/// Se hace a mano en vez de con `unaccent`/`diacritic` para no arrastrar una
/// dependencia solo por esto.
String _normalizar(String? texto) {
  if (texto == null) return '';
  final StringBuffer salida = StringBuffer();
  for (final int rune in texto.toLowerCase().runes) {
    final String c = String.fromCharCode(rune);
    salida.write(_sinTilde[c] ?? c);
  }
  return salida.toString().trim();
}

const Map<String, String> _sinTilde = <String, String>{
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Una regla = una lista de fragmentos que, si aparecen en el nombre, eligen el
/// icono. El orden importa: gana la primera que coincida, así que las reglas
/// específicas van antes que las genéricas ("cuidado personal" antes que
/// "personal", "electrodomestico" antes que "electro").
class _ReglaCategoria {
  const _ReglaCategoria(this.fragmentos, this.icono);
  final List<String> fragmentos;
  final IconData icono;

  bool coincide(String texto) {
    for (final String f in fragmentos) {
      if (f.length < _largoMinimoSubcadena) {
        // Fragmentos cortos exigen **límite de palabra**.
        //
        // Sin esto, "ron" (Ron) casa dentro de "electrónica" y "te" (Té) dentro
        // de "textil": los dos casos se vieron de verdad al escribir los tests.
        if (_palabra(f).hasMatch(texto)) return true;
      } else if (texto.contains(f)) {
        return true;
      }
    }
    return false;
  }
}

/// Por debajo de este largo, un fragmento se busca como palabra completa.
/// Cinco es el punto donde "bebida", "cafe" o "hogar" ya son suficientemente
/// específicos como para que una subcadena no dé falsos positivos.
const int _largoMinimoSubcadena = 5;

final Map<String, RegExp> _cachePalabra = <String, RegExp>{};

/// `fragmento` como palabra suelta, rodeada de inicio/fin o de algo que no sea
/// letra o dígito.
RegExp _palabra(String fragmento) => _cachePalabra.putIfAbsent(
      fragmento,
      () => RegExp(
        '(^|[^a-z0-9])${RegExp.escape(fragmento)}([^a-z0-9]|\$)',
      ),
    );

/// Ordenadas de lo más específico a lo más genérico.
const List<_ReglaCategoria> _reglas = <_ReglaCategoria>[
  // Combustible y automoción. "servicentro" y "gasolinera" antes que "servicio".
  _ReglaCategoria(<String>['combustible', 'gasolina', 'diesel', 'gasoil', 'servicentro', 'gasolinera'],
      Icons.local_gas_station_rounded),
  _ReglaCategoria(<String>['lubricante', 'aceite motor'], Icons.oil_barrel_outlined),
  _ReglaCategoria(<String>['taller', 'mecanic', 'automotriz', 'repuesto'], Icons.car_repair_rounded),

  // Servicios y reparaciones.
  _ReglaCategoria(<String>['servicio'], Icons.room_service_rounded),
  _ReglaCategoria(<String>['reparacion', 'reparac'], Icons.handyman_rounded),
  _ReglaCategoria(<String>['lavander', 'lavado'], Icons.local_laundry_service_rounded),
  _ReglaCategoria(<String>['peluquer', 'barber'], Icons.content_cut_rounded),
  _ReglaCategoria(<String>['estetica', 'spa', 'belleza'], Icons.spa_outlined),
  _ReglaCategoria(<String>['gimnasio', 'deporte', 'fitness'], Icons.fitness_center_rounded),
  _ReglaCategoria(<String>['juridic', 'abogad', 'legal', 'notari'], Icons.gavel_rounded),
  _ReglaCategoria(<String>['contab', 'auditor'], Icons.calculate_rounded),
  _ReglaCategoria(<String>['alojamiento', 'hotel', 'hostal'], Icons.hotel_outlined),
  _ReglaCategoria(<String>['transporte', 'omnibus', 'taxi', 'flete'], Icons.directions_car_filled_outlined),
  _ReglaCategoria(<String>['recreacion', 'entretenimiento', 'parque'], Icons.attractions_outlined),
  _ReglaCategoria(<String>['evento', 'fiesta', 'celebracion'], Icons.celebration_outlined),

  // Alimentos y bebidas.
  _ReglaCategoria(<String>['panader', 'panificad', 'reposter'], Icons.bakery_dining_rounded),
  _ReglaCategoria(<String>['lacteo', 'leche', 'queso', 'yogur'], Icons.icecream_rounded),
  _ReglaCategoria(<String>['carnic', 'carnes', 'pollo', 'pescado', 'embutido'], Icons.set_meal_rounded),
  _ReglaCategoria(<String>['fruta', 'verdura', 'vegetal', 'hortaliza'], Icons.eco_rounded),
  _ReglaCategoria(<String>['confitura', 'dulce', 'golosina', 'caramelo', 'chocolat'], Icons.cake_rounded),
  _ReglaCategoria(<String>['snack', 'pica'], Icons.fastfood_rounded),
  _ReglaCategoria(<String>['cafe', 'infusion', 'te'], Icons.local_cafe_rounded),
  _ReglaCategoria(<String>['alcohol', 'ron', 'cerveza', 'vino', 'licor'], Icons.liquor_rounded),
  _ReglaCategoria(<String>['refresco', 'gaseosa', 'jugo', 'bebida', 'agua'], Icons.local_drink_rounded),
  _ReglaCategoria(<String>['aliment', 'comida', 'gastronom', 'vianda', 'mercad'], Icons.restaurant_rounded),

  // Aseo, higiene y salud.
  _ReglaCategoria(<String>['cuidado personal', 'higiene', 'aseo personal', 'aseo'], Icons.face_retouching_natural_rounded),
  _ReglaCategoria(<String>['limpieza', 'detergente', 'jabon'], Icons.cleaning_services_rounded),
  _ReglaCategoria(<String>['farmac', 'medicament', 'salud', 'botiquin'], Icons.medical_services_outlined),
  _ReglaCategoria(<String>['optica', 'lente', 'gafa'], Icons.visibility_rounded),

  // Hogar, ferretería y construcción.
  _ReglaCategoria(<String>['ferreter', 'herramienta'], Icons.build_rounded),
  _ReglaCategoria(<String>['construccion', 'materiales', 'cemento', 'pintura'], Icons.construction_rounded),
  _ReglaCategoria(<String>['electric', 'electricid', 'cable', 'bombillo'], Icons.electrical_services_rounded),
  _ReglaCategoria(<String>['plomer', 'fontaner', 'tuberia'], Icons.plumbing_rounded),
  _ReglaCategoria(<String>['jardin', 'vivero', 'planta'], Icons.local_florist_rounded),
  _ReglaCategoria(<String>['hogar', 'oficina', 'casa', 'mueble'], Icons.chair_rounded),

  // Tecnología.
  _ReglaCategoria(<String>['electrodomest'], Icons.kitchen_rounded),
  _ReglaCategoria(<String>['electron', 'tecnolog', 'telefono', 'celular', 'comput'], Icons.devices_other_rounded),

  // Textil y varios.
  _ReglaCategoria(<String>['textil', 'confeccion', 'ropa', 'vestuario'], Icons.checkroom_rounded),
  _ReglaCategoria(<String>['calzado', 'zapato', 'tenis'], Icons.hiking_rounded),
  _ReglaCategoria(<String>['joyeria', 'bisuter', 'reloj'], Icons.diamond_outlined),
  _ReglaCategoria(<String>['juguete', 'infantil', 'nino'], Icons.toys_rounded),
  _ReglaCategoria(<String>['mascota', 'animal', 'veterinar'], Icons.pets_rounded),
  _ReglaCategoria(<String>['papeler', 'escolar', 'cuaderno', 'liber'], Icons.menu_book_rounded),
  _ReglaCategoria(<String>['paquete', 'paqueteria', 'envio', 'shipping', 'encomienda'], Icons.inventory_2_rounded),
  _ReglaCategoria(<String>['gasto', 'servicio publico', 'factura'], Icons.receipt_long_rounded),
  _ReglaCategoria(<String>['bolsa', 'plastico', 'desechable'], Icons.shopping_bag_rounded),
];
