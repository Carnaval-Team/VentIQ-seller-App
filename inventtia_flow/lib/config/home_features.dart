/// Interruptores de las secciones del Home cuyo respaldo **todavía no existe**
/// ni en la base de datos ni en la administración de `inventtia_flow`.
///
/// El Home del cliente pintaba estas secciones con datos inventados
/// (`_mockCatalog` en `home_catalog_service.dart`, "Luna Studio", "Casa Aura",
/// ratings 4.9, "-25 %", "20 % de descuento"…), lo que anunciaba un producto
/// que nadie podía configurar. Cada bandera documenta qué falta para poder
/// encenderla, y `plan.md` es el plan de trabajo.
///
/// Regla: una sección solo se enciende cuando existe la tabla/RPC **y** la
/// pantalla de administración que la alimenta.
library;

class HomeFeatures {
  const HomeFeatures._();

  /// Promociones con vigencia, descuento y cupos atómicos.
  ///
  /// **Ya implementado**: `flow.promocion` + `cotizar_reserva` +
  /// `promociones_por_servicio`. El descuento se auto-detecta: si la migración
  /// `27_promociones.sql` no está aplicada, el Home se pinta sin badges.
  ///
  /// Punto clave de diseño: el precio que se **muestra** y el que se **cobra**
  /// salen de la misma función del servidor (`_resolver_promocion`), así que no
  /// pueden descuadrar. Antes la app calculaba el precio en Dart y el servidor
  /// lo recalculaba al cobrar: dos implementaciones de la misma regla.
  ///
  /// El **bot no aplica promociones**: cuando mueve a alguien de la sala de
  /// espera a la agenda nadie eligió una oferta, así que cobra precio de lista.
  static const bool ofertasRelampago = true;

  /// Campañas patrocinadas con prioridad de publicación.
  /// Falta: tabla `flow.campana` + facturación/prioridad + CRUD admin.
  static const bool patrocinados = false;

  /// Colecciones temáticas curadas ("Pack Novia", "Self-care Sunday").
  /// Falta: `flow.coleccion` + `flow.coleccion_servicio` + CRUD admin.
  static const bool colecciones = false;

  /// Reseñas y rating por servicio, verificadas contra una reserva completada.
  ///
  /// **Ya implementado**: `flow.resena` + `resenas_de_servicio`,
  /// `resenas_recientes` y `resenas_por_servicio`. Igual que los favoritos, se
  /// auto-detecta: si la migración `26_resenas.sql` no está aplicada, el Home no
  /// pinta estrellas ni el bloque de reseñas, en vez de mostrar datos falsos.
  ///
  /// Nota: un servicio **sin** reseñas no muestra "0.0" ni estrellas rellenas.
  /// Antes el Home inventaba 4.8 con 142 reseñas.
  static const bool resenas = true;

  /// "Servicios populares de la semana" (ranking por reservas reales).
  /// Falta: RPC de ranking con ventana semanal.
  static const bool rankingSemanal = false;

  /// Programa de fidelidad y beneficio de bienvenida.
  /// Falta: reglas, saldo, vencimiento y auditoría de puntos.
  static const bool fidelidad = false;

  /// Favoritos persistentes por usuario.
  ///
  /// **Ya implementado**: `flow.favorito` + `FavoritosProvider`. No necesita
  /// bandera porque se auto-detecta en tiempo de ejecución: si la migración
  /// `25_favoritos.sql` no está aplicada, `FavoritosProvider.disponible` queda
  /// en `false` y el corazón no se pinta. Así el mismo binario funciona antes y
  /// después de aplicar la migración, sin recompilar.
  ///
  /// Nota de nombres: "Mis Listas" en la barra inferior es la **sala de espera**
  /// (`flow.sala_espera`), no favoritos. Ver §3 del plan.
  static const bool favoritos = true;

  /// Distancia real y filtro "Cerca de mí".
  /// Falta: `app_dat_locales.coordenadas` está vacío en todos los locales y no
  /// se guarda la ubicación del usuario. Sin coordenadas no hay distancia.
  static const bool distancia = false;

  /// Filtro "Mejor valorados".
  ///
  /// **Ya implementado**: depende de [resenas]. Ordena por el promedio real y,
  /// a igualdad de promedio, por número de reseñas. Los servicios sin ninguna
  /// reseña van al final: no se les supone una valoración.
  static const bool mejorValorados = true;

  /// Búsqueda por voz.
  /// Falta: integración de reconocimiento de voz.
  static const bool busquedaPorVoz = false;

  /// Duración del servicio ("45 min").
  /// Falta: no existe columna de duración en `flow.app_dat_servicios`.
  static const bool duracion = false;
}
