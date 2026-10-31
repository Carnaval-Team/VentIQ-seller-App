import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import 'suscripcion_ui.dart';

/// Piezas de presentación de la pantalla **Planes de suscripción**.
///
/// La tarjeta tiene que leerse como una ficha de producto (precio grande,
/// límites visibles, cinta de "Más popular"), no como una fila de tabla: el
/// superadmin decide mirando varias tarjetas a la vez qué plan ofrecer y a qué
/// precio. Por eso todo lo que se pinta aquí deriva del contrato del servidor
/// (`limites`, `modalidad`, `etiqueta`, `id_entidad`) y es **tolerante** a que
/// esos campos todavía no existan: si faltan, se comporta como un plan público
/// de pago sin límites declarados.

/// WhatsApp de ventas/soporte por defecto.
///
/// Es el valor de `flow.suscripcion_config.soporte_whatsapp` (migración 43,
/// `default '5354590207'`) y el que usa la app de Flow cuando no puede leer la
/// configuración. La pantalla intenta leer el número real de
/// `admin_config_obtener`; esto es solo el respaldo para cuando esa lectura
/// falla. Si cambia el soporte, se cambia en **Configuración** del panel y este
/// valor solo aplica si esa lectura falla.
const String kWhatsAppVentasPorDefecto = '5354590207';

/// Claves de `limites` que entiende el servidor, en el orden en que se pintan.
///
/// El orden es deliberado: de lo global (entidades) a lo granular (usuarios),
/// para que dos planes se puedan comparar de un vistazo.
const List<String> kClavesLimite = <String>[
  'entidades',
  'locales',
  'servicios_por_local',
  'servicios_catalogo',
  'usuarios',
];

/// Rótulo legible de una clave de límite (para el editor).
String etiquetaDeLimite(String clave) {
  switch (clave) {
    case 'entidades':
      return 'Entidades';
    case 'locales':
      return 'Locales';
    case 'servicios_por_local':
      return 'Servicios por local';
    case 'servicios_catalogo':
      return 'Servicios en catálogo';
    case 'usuarios':
      return 'Usuarios';
    default:
      return clave;
  }
}

/// Texto de ayuda de una clave de límite (para el editor).
String ayudaDeLimite(String clave) {
  switch (clave) {
    case 'entidades':
      return 'Negocios distintos que puede crear el mismo dueño';
    case 'locales':
      return 'Sucursales de una misma entidad';
    case 'servicios_por_local':
      return 'Servicios que se pueden activar en cada local';
    case 'servicios_catalogo':
      return 'Servicios del catálogo de la entidad';
    case 'usuarios':
      return 'Cuentas de trabajo dentro de la entidad';
    default:
      return '';
  }
}

/// "1 local" / "2 locales": el número siempre se lee con su sustantivo.
String textoSingularPluralLimite(String clave, int cantidad) {
  final n = cantidad;
  switch (clave) {
    case 'entidades':
      return n == 1 ? '1 entidad' : '$n entidades';
    case 'locales':
      return n == 1 ? '1 local' : '$n locales';
    case 'servicios_por_local':
      return n == 1 ? '1 servicio por local' : '$n servicios por local';
    case 'servicios_catalogo':
      return n == 1 ? '1 servicio en catálogo' : '$n servicios en catálogo';
    case 'usuarios':
      return n == 1 ? '1 usuario' : '$n usuarios';
    default:
      return '$n $clave';
  }
}

// ── Lectura tolerante del plan ───────────────────────────────────────────────

/// `limites` llega como objeto jsonb (o como texto si el driver lo serializa).
Map<String, dynamic> mapaDeLimites(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decodificado = jsonDecode(raw);
      if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
    } catch (_) {
      // jsonb corrupto o null: se trata como "sin límites", no se rompe.
    }
  }
  return const <String, dynamic>{};
}

/// Solo las claves con valor `> 0`.
///
/// Regla del contrato: ausente, null, 0 o negativo = **sin límite**. El editor
/// manda únicamente las claves positivas, así que aquí se aplica la misma regla
/// al pintar para que ambos lados digan lo mismo.
Map<String, int> limitesPositivos(dynamic raw) {
  final salida = <String, int>{};
  mapaDeLimites(raw).forEach((clave, valor) {
    final n =
        valor is num
            ? valor.toInt()
            : (valor is String ? int.tryParse(valor.trim()) : null);
    if (n != null && n > 0) salida[clave] = n;
  });
  return salida;
}

/// Lista legible de características del plan a partir de `limites`.
///
/// Un plan sin límites declarados devuelve `['Sin límite']` en vez de una lista
/// vacía: la tarjeta nunca se queda sin ese bloque y el superadmin sabe que ese
/// plan no restringe nada.
List<String> caracteristicasDePlan(Map<String, dynamic> plan) {
  final limites = limitesPositivos(plan['limites']);
  if (limites.isEmpty) return const <String>['Sin límite'];
  return <String>[
    for (final clave in kClavesLimite)
      if (limites.containsKey(clave))
        textoSingularPluralLimite(clave, limites[clave]!),
  ];
}

/// `pago` | `contacto`. Cualquier otro valor (servidor viejo) se lee como pago.
String modalidadDePlan(Map<String, dynamic> plan) {
  final m = textoDe(plan['modalidad']).trim().toLowerCase();
  return m == 'contacto' ? 'contacto' : 'pago';
}

bool esPlanContacto(Map<String, dynamic> plan) =>
    modalidadDePlan(plan) == 'contacto';

/// Un plan es privado si tiene `id_entidad`; el servidor lo limita a esa entidad.
bool esPlanPrivado(Map<String, dynamic> plan) =>
    enteroDe(plan['id_entidad']) != null;

String nombreEntidadDePlan(Map<String, dynamic> plan) {
  final nombre = textoDe(plan['entidad_denominacion']).trim();
  if (nombre.isNotEmpty) return nombre;
  final id = enteroDe(plan['id_entidad']);
  return id == null ? 'Entidad' : 'Entidad #$id';
}

/// Cinta de la tarjeta ("Más popular", "Recomendado") o `null` si no lleva.
String? etiquetaDePlan(Map<String, dynamic> plan) {
  final etiqueta = textoDe(plan['etiqueta']).trim();
  return etiqueta.isEmpty ? null : etiqueta;
}

double precioDePlan(Map<String, dynamic> plan) =>
    decimalDe(plan['precio']) ?? 0;

String monedaDePlan(Map<String, dynamic> plan) {
  final moneda =
      textoDe(plan['moneda'], porDefecto: 'USD').trim().toUpperCase();
  return moneda.isEmpty ? 'USD' : moneda;
}

String numeroDePrecio(num valor) =>
    NumberFormat('#,##0.##', 'es').format(valor);

/// Precio mensual equivalente, solo cuando la duración permite compararlo.
///
/// Se usa `dias / 30` tal como pide el contrato: 30 días = 1 mes, 365 días =
/// 12,17 meses. Para duraciones menores a 28 días no se muestra "/mes" porque
/// la comparación sería engañosa.
double? precioMensualDePlan(Map<String, dynamic> plan) {
  final dias = enteroDe(plan['duracion_dias']) ?? 0;
  final precio = precioDePlan(plan);
  if (dias < 28 || precio <= 0) return null;
  return precio / (dias / 30);
}

/// Texto pequeño bajo el precio: el importe real del periodo.
///
/// Ejemplo: "Facturado 30,00 USD cada 30 días". Para los planes de contacto o
/// de cortesía se explica el caso en vez de repetir el número.
String textoPeriodoDePlan(Map<String, dynamic> plan) {
  final dias = enteroDe(plan['duracion_dias']) ?? 0;
  final precio = precioDePlan(plan);
  if (esPlanContacto(plan)) return 'Precio según tu operación';
  if (precio <= 0) return 'Sin coste (plan de cortesía)';
  final importe = formatearMoneda(precio, monedaDePlan(plan));
  if (dias >= 28) return 'Facturado $importe cada $dias días';
  return 'Pago único · $dias días';
}

/// Sufijo grande del precio: `/mes` o `/N días`.
String sufijoPrecioDePlan(Map<String, dynamic> plan) {
  final dias = enteroDe(plan['duracion_dias']) ?? 0;
  if (precioMensualDePlan(plan) != null) return '/mes';
  return dias > 0 ? '/$dias días' : '';
}

/// Número grande: el mensual si se puede comparar, si no el del periodo.
double precioDestacadoDePlan(Map<String, dynamic> plan) =>
    precioMensualDePlan(plan) ?? precioDePlan(plan);

// ── Tarifa vs cobro ──────────────────────────────────────────────────────────

/// Aviso del editor: el plan se tarifa en la moneda elegida, pero el cobro
/// real es en CUP.
///
/// La conversión la hace el servidor al crear el intent de pago (migración 74)
/// con el cambio del día; el panel solo informa y por eso este texto no debe
/// acompañarse de ninguna conversión local.
const String kAvisoCobroCupEditor =
    'El precio del plan se guarda en la moneda que elijas, pero el cobro por '
    'Transfermóvil se hace siempre en CUP, al cambio del día.';

/// Nota corta de la tarjeta cuando el plan no está tarifado en CUP.
const String kAvisoCobroCupTarjeta = 'Se cobra en CUP al cambio del día.';

/// Recuerda que el cobro es en CUP aunque la tarifa esté en otra moneda.
///
/// [discreta] `true` pinta la nota pequeña de la tarjeta (bajo el precio);
/// `false` pinta el bloque informativo del editor, donde el superadmin elige la
/// moneda y conviene que lo lea antes de guardar.
class NotaCobroCup extends StatelessWidget {
  const NotaCobroCup({super.key, this.discreta = false});

  final bool discreta;

  @override
  Widget build(BuildContext context) {
    if (discreta) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 12, color: AppColors.textHint),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              kAvisoCobroCupTarjeta,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.info),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              kAvisoCobroCupEditor,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── WhatsApp de ventas ───────────────────────────────────────────────────────

/// Deja solo dígitos y normaliza prefijos (`+`, `00`).
///
/// `wa.me` exige el número completo con código de país y sin signos.
String whatsappDigitos(String crudo) {
  var s = crudo.trim();
  if (s.startsWith('00')) s = s.substring(2);
  s = s.replaceAll(RegExp(r'[^0-9]'), '');
  return s;
}

/// Abre el WhatsApp de ventas con un mensaje ya redactado.
///
/// Devuelve `true` si se pudo abrir. Cuando no hay número válido o el
/// lanzamiento falla, avisa al usuario con un SnackBar en vez de dejar el botón
/// muerto sin explicación.
Future<bool> abrirWhatsAppVentas(
  BuildContext contexto, {
  required String numero,
  String mensaje = '',
}) async {
  final digitos = whatsappDigitos(numero);
  if (digitos.length < 8) {
    _avisar(
      contexto,
      'El WhatsApp de ventas no está configurado. Añádelo en Configuración.',
      AppColors.warning,
    );
    return false;
  }

  final texto = mensaje.trim();
  final uri = Uri.https(
    'wa.me',
    '/$digitos',
    texto.isEmpty ? null : {'text': texto},
  );

  var abierto = false;
  try {
    abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    abierto = false;
  }
  if (!abierto && contexto.mounted) {
    _avisar(
      contexto,
      'No se pudo abrir WhatsApp. Revisa que esté instalado en este equipo.',
      AppColors.error,
    );
  }
  return abierto;
}

void _avisar(BuildContext contexto, String mensaje, Color color) {
  if (!contexto.mounted) return;
  ScaffoldMessenger.of(
    contexto,
  ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
}

// ── Tarjeta de plan ──────────────────────────────────────────────────────────

/// Tarjeta de plan del catálogo del superadmin.
///
/// Es solo presentación: activar, editar, eliminar y contactar se delegan en
/// callbacks para que la pantalla siga siendo la única dueña del estado.
class TarjetaPlanFlow extends StatelessWidget {
  const TarjetaPlanFlow({
    super.key,
    required this.plan,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
    this.whatsappVentas = kWhatsAppVentasPorDefecto,
  });

  final Map<String, dynamic> plan;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;
  final String whatsappVentas;

  @override
  Widget build(BuildContext context) {
    final activo = boolDe(plan['activo']);
    final privado = esPlanPrivado(plan);
    final contacto = esPlanContacto(plan);
    final etiqueta = etiquetaDePlan(plan);
    final nombre = textoDe(plan['nombre'], porDefecto: 'Sin nombre');
    final codigo = textoDe(plan['codigo']).trim();
    final descripcion = textoDe(plan['descripcion']).trim();
    final acento = privado ? AppColors.secondary : AppColors.primary;
    final caracteristicas = caracteristicasDePlan(plan);
    final borde =
        !activo
            ? AppColors.warning.withValues(alpha: 0.45)
            : (privado || etiqueta != null
                ? acento.withValues(alpha: 0.45)
                : AppColors.divider);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borde),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (etiqueta != null) _CintaEtiqueta(texto: etiqueta, color: acento),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconoPlan(
                      icono:
                          contacto
                              ? Icons.handshake_outlined
                              : (privado
                                  ? Icons.lock_outline_rounded
                                  : Icons.workspace_premium_outlined),
                      color: acento,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (codigo.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              codigo,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!activo)
                      Padding(
                        padding: const EdgeInsets.only(right: 2, top: 2),
                        child: _Pildora(
                          texto: 'INACTIVO',
                          color: AppColors.warning,
                        ),
                      ),
                    Tooltip(
                      message:
                          activo
                              ? 'Desactivar: deja de ofrecerse'
                              : 'Activar: se ofrece a los clientes',
                      child: Switch(
                        value: activo,
                        onChanged: (_) => onAlternar(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                if (privado) ...[
                  const SizedBox(height: 10),
                  _Pildora(
                    texto: 'PRIVADO · ${nombreEntidadDePlan(plan)}',
                    color: AppColors.secondary,
                    icono: Icons.lock_outline_rounded,
                    expande: true,
                  ),
                ],
                const SizedBox(height: 14),
                if (contacto)
                  _BloqueContacto(
                    color: acento,
                    nombrePlan: nombre,
                    whatsappVentas: whatsappVentas,
                  )
                else
                  _BloquePrecio(plan: plan, color: acento),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 12),
                const Text(
                  'INCLUYE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final caracteristica in caracteristicas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Caracteristica(
                      texto: caracteristica,
                      color: acento,
                      sinLimite:
                          caracteristicas.length == 1 &&
                          caracteristica == 'Sin límite',
                    ),
                  ),
                if (descripcion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    descripcion,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Divider(height: 1, color: AppColors.divider),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onEditar,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Editar'),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Eliminar plan',
                      onPressed: onEliminar,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cinta superior de la tarjeta ("MÁS POPULAR", "RECOMENDADO").
class _CintaEtiqueta extends StatelessWidget {
  const _CintaEtiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconoPlan extends StatelessWidget {
  const _IconoPlan({required this.icono, required this.color});

  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icono, size: 22, color: color),
    );
  }
}

class _Pildora extends StatelessWidget {
  const _Pildora({
    required this.texto,
    required this.color,
    this.icono,
    this.expande = false,
  });

  final String texto;
  final Color color;
  final IconData? icono;

  /// `true` para píldoras que ocupan todo el ancho disponible (la de "PRIVADO ·
  /// entidad"), donde el texto largo se recorta con puntos suspensivos en vez de
  /// desbordar. Las del encabezado van `false` para poder vivir dentro de un
  /// `Row` sin anchura acotada.
  final bool expande;

  @override
  Widget build(BuildContext context) {
    final etiqueta = Text(
      texto,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: expande ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          if (expande) Expanded(child: etiqueta) else etiqueta,
        ],
      ),
    );
  }
}

class _Caracteristica extends StatelessWidget {
  const _Caracteristica({
    required this.texto,
    required this.color,
    required this.sinLimite,
  });

  final String texto;
  final Color color;
  final bool sinLimite;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          sinLimite ? Icons.all_inclusive_rounded : Icons.check_circle_rounded,
          size: 16,
          color: sinLimite ? AppColors.textSecondary : color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bloque de precio de un plan de pago.
class _BloquePrecio extends StatelessWidget {
  const _BloquePrecio({required this.plan, required this.color});

  final Map<String, dynamic> plan;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final moneda = monedaDePlan(plan);
    final destacado = precioDestacadoDePlan(plan);
    final sufijo = sufijoPrecioDePlan(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: numeroDePrecio(destacado),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: ' $moneda',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (sufijo.isNotEmpty)
                  TextSpan(
                    text: ' $sufijo',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          textoPeriodoDePlan(plan),
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            height: 1.3,
          ),
        ),
        // El importe está tarifado en otra moneda, pero el cobro es en CUP al
        // cambio del día: se dice aquí, sin recalcular nada en el panel.
        if (moneda != 'CUP') ...[
          const SizedBox(height: 4),
          const NotaCobroCup(discreta: true),
        ],
      ],
    );
  }
}

/// Bloque de "Contactar con ventas" para los planes de modalidad `contacto`.
class _BloqueContacto extends StatelessWidget {
  const _BloqueContacto({
    required this.color,
    required this.nombrePlan,
    required this.whatsappVentas,
  });

  final Color color;
  final String nombrePlan;
  final String whatsappVentas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Precio a medida',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            height: 1.1,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Se negocia con el equipo de ventas según el tamaño de tu operación.',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                () => abrirWhatsAppVentas(
                  context,
                  numero: whatsappVentas,
                  mensaje:
                      'Hola, quiero información sobre el plan "$nombrePlan" de '
                      'Inventtia Flow.',
                ),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Contactar con ventas'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Abre WhatsApp con el número de soporte del panel.',
          style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
        ),
      ],
    );
  }
}
