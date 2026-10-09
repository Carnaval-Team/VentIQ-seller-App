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

  /// Campañas patrocinadas del Home.
  ///
  /// **Ya implementado**: `flow.campana` + `campanas_activas()`. Las configura el
  /// **superadmin** desde la app `ventiq_superadmin` (migración
  /// `28_patrocinados.sql`), no el admin de la entidad: es contenido de
  /// plataforma, no de un negocio concreto.
  ///
  /// **Una campaña no toca el precio.** Solo decide qué se destaca. Los
  /// descuentos son `flow.promocion` (ver [ofertasRelampago]).
  ///
  /// Igual que el resto, se auto-detecta: si la migración 28 no está aplicada o
  /// no hay campañas vigentes, la sección **no se pinta**. Antes mostraba tres
  /// tarjetas inventadas ("Luna Studio", "Casa Aura", "Moverte") con un sello
  /// "Verificado" que no respaldaba ningún dato.
  static const bool patrocinados = true;

  /// Colecciones temáticas curadas ("Pack Novia", "Self-care Sunday").
  ///
  /// **Ya implementado**: `flow.coleccion` + `flow.coleccion_servicio` +
  /// `colecciones_activas()` (migración `30_colecciones.sql`). Las cura el
  /// **superadmin** desde `ventiq_superadmin`, junto a los patrocinados: una
  /// colección cruza entidades, así que no es contenido de un negocio concreto.
  ///
  /// **Una colección no toca el precio.** Solo agrupa servicios. Los descuentos
  /// son `flow.promocion` (ver [ofertasRelampago]).
  ///
  /// Se auto-detecta: si la migración 30 no está aplicada o el superadmin no ha
  /// curado ninguna, la sección **no se pinta**. Antes mostraba cuatro tarjetas
  /// inventadas ("Pack Novia" con "12 servicios", "Self-care Sunday" con 8…)
  /// que nadie podía configurar.
  static const bool colecciones = true;

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

  /// "Servicios populares de la semana": lugares reservados en la semana en
  /// curso, de `flow.cliente_ranking_semanal()` (migración 36).
  ///
  /// **Ya implementado.** Ordena por *lugares* reservados, no por número de
  /// reservas: en los datos reales hay dos servicios con 3 reservas cada uno que
  /// suman 11 y 3 lugares, así que por número de reservas empatarían y el
  /// desempate sería invisible. El número que se pinta es el que ordena.
  ///
  /// Solo cuentan `Reservado` y `Completado`: una reserva cancelada no es
  /// demanda.
  ///
  /// Se auto-detecta: sin reservas esta semana el bloque **no se pinta**, en vez
  /// de rellenar con el orden del catálogo, que es lo que hacía antes
  /// (`_items.take(3)` con posiciones 1-2-3 que no significaban nada).
  static const bool rankingSemanal = true;

  /// Programa de fidelidad: puntos por reservas completadas.
  ///
  /// **Ya implementado**: `flow.regla_fidelidad` + `flow.puntos_movimiento` +
  /// `flow.cliente_mi_fidelidad()` (migración `31_fidelidad.sql`), más las RPC de
  /// configuración y auditoría de la `32`. Los puntos se acreditan con un
  /// **trigger** cuando una reserva pasa a *Completado* — no redefiniendo
  /// `staff_marcar_estado_agenda`, para no pisar una función viva que podría estar
  /// desviada del repo.
  ///
  /// **Los puntos no tocan el precio.** Solo se acumulan y se muestran: el canje
  /// por descuento es un paso aparte, a propósito. Dos cambios de precio a la vez
  /// en el mismo camino crítico son mucho más difíciles de verificar.
  ///
  /// El saldo **no es una columna**: es la suma del libro de movimientos, así que
  /// no puede desincronizarse de la auditoría. Tampoco hay cron de vencimiento:
  /// el saldo ya excluye los puntos caducados, se haya asentado o no el asiento.
  ///
  /// Se auto-detecta: si la migración 31 no está aplicada, el banner no se pinta.
  /// Antes anunciaba un "20 % de descuento" que no existía en ninguna tabla.
  static const bool fidelidad = true;

  /// Descuento del beneficio de bienvenida **aplicado al precio** de la reserva.
  ///
  /// **Ya implementado** (migración 34): `_beneficio_bienvenida_aplicable` +
  /// `cotizar_reserva` + `cliente_reservar_directo`. Lo mostrado y lo cobrado
  /// salen de la misma función, así que el banner ya puede anunciarlo.
  ///
  /// Se aplica **después** de la promoción y sobre lo que queda, así que los dos
  /// descuentos no se solapan. Y respeta el interruptor global
  /// (`flow.fidelidad_config`): con la fidelidad apagada el precio no baja ni
  /// aunque el beneficio siga activo.
  ///
  /// Esta bandera es manual, a diferencia de [fidelidad]: el servidor no puede
  /// decirle al Home si el descuento está integrado en el precio, así que existe
  /// justo para no volver a anunciar un descuento que nadie cobra. Se enciende
  /// cuando la migración 34 está aplicada.
  static const bool beneficioBienvenida = true;

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
