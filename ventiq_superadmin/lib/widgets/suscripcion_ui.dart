import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';

/// Piezas compartidas por las pantallas de suscripciones del panel.
///
/// Están en un solo sitio porque las tres pantallas nuevas (bandeja, planes y
/// configuración) tienen que pintar el mismo estado con el mismo color: si cada
/// una eligiera su tono, "vencida" sería roja en una y ámbar en otra.

/// Color de un estado de suscripción, derivado del texto que manda el servidor.
///
/// Los tonos no son decorativos: rojo = la entidad no funciona, ámbar = funciona
/// pero se cae pronto, verde = al día. El superadmin mira esta lista para decidir
/// a quién llamar, así que el color tiene que responder eso de un vistazo.
Color colorDeEstado(String estado) {
  switch (estado) {
    case 'activa':
      return AppColors.success;
    case 'trial':
      return AppColors.info;
    case 'en_gracia':
    case 'por_vencer':
      return AppColors.warning;
    case 'vencida':
    case 'suspendida':
    case 'cancelada':
      return AppColors.error;
    case 'sin_plan':
    case 'sin_suscripcion':
      return AppColors.textSecondary;
    default:
      return AppColors.textSecondary;
  }
}

/// Etiqueta legible de un estado.
String etiquetaDeEstado(String estado) {
  switch (estado) {
    case 'activa':
      return 'Activa';
    case 'trial':
      return 'Prueba';
    case 'en_gracia':
      return 'En gracia';
    case 'por_vencer':
      return 'Por vencer';
    case 'vencida':
      return 'Vencida';
    case 'suspendida':
      return 'Suspendida';
    case 'cancelada':
      return 'Cancelada';
    case 'sin_plan':
      return 'Sin plan';
    case 'sin_suscripcion':
      return 'Sin registro';
    default:
      return estado;
  }
}

/// Píldora de estado.
class EstadoPill extends StatelessWidget {
  const EstadoPill({super.key, required this.estado, this.compacta = false});

  final String estado;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final color = colorDeEstado(estado);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacta ? 8 : 10,
        vertical: compacta ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        etiquetaDeEstado(estado),
        style: TextStyle(
          color: color,
          fontSize: compacta ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "14/03/2026" o "—" si no hay fecha.
///
/// Se usa un formato fijo dd/MM/yyyy en vez de `DateFormat.yMd('es')` para que
/// la fecha se lea igual en todas las pantallas del panel.
String fechaCorta(DateTime? f) {
  if (f == null) return '—';
  return DateFormat('dd/MM/yyyy').format(f);
}

/// Fecha y hora, para el historial de pagos y movimientos.
String fechaHora(DateTime? f) {
  if (f == null) return '—';
  return DateFormat('dd/MM/yyyy HH:mm').format(f);
}

/// Importe con separador de miles y dos decimales: "1,500.00 CUP".
String formatearMoneda(num? monto, String? moneda) {
  if (monto == null) return '—';
  final txt = NumberFormat('#,##0.00', 'es').format(monto);
  final mon = (moneda ?? 'CUP').trim();
  return mon.isEmpty ? txt : '$txt $mon';
}

/// Convierte a `DateTime` local el valor ISO que devuelve un RPC.
DateTime? fechaDe(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int? enteroDe(dynamic v) => (v as num?)?.toInt();

double? decimalDe(dynamic v) => (v as num?)?.toDouble();

String textoDe(dynamic v, {String porDefecto = ''}) =>
    v is String && v.trim().isNotEmpty ? v : porDefecto;

bool boolDe(dynamic v, {bool porDefecto = false}) => v is bool ? v : porDefecto;

/// Tarjeta blanca con borde suave, el contenedor estándar del panel.
class TarjetaFlow extends StatelessWidget {
  const TarjetaFlow({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borde,
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borde;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borde ?? AppColors.divider),
      ),
      child: child,
    );
  }
}
