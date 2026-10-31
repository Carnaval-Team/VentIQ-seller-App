import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/versiones_service.dart';
import 'suscripcion_ui.dart';

/// Piezas de presentación de la pantalla **Versiones de las apps**.
///
/// Aquí vive todo lo que se pinta: el catálogo de apps del ecosistema, las
/// tarjetas del historial, la lista de novedades y la **vista previa móvil**
/// (cómo verá el usuario el aviso de actualización). La pantalla solo maneja
/// estado y llamadas al [VersionesService].

// ── Apps del ecosistema ──────────────────────────────────────────────────────

/// Una app del ecosistema Inventtia con su identidad visual en el panel.
class AppEcosistema {
  const AppEcosistema({
    required this.id,
    required this.nombre,
    required this.detalle,
    required this.icono,
    required this.color,
  });

  /// Valor de `app_name` en `public.app_versiones`.
  final String id;
  final String nombre;
  final String detalle;
  final IconData icono;
  final Color color;
}

/// Las 5 apps del ecosistema, en el orden en que se ofrecen en el selector.
const List<AppEcosistema> appsEcosistema = <AppEcosistema>[
  AppEcosistema(
    id: 'ventiq_app',
    nombre: 'Inventtia Caja',
    detalle: 'TPV, ventas y caja',
    icono: Icons.point_of_sale_outlined,
    color: AppColors.primary,
  ),
  AppEcosistema(
    id: 'ventiq_admin',
    nombre: 'Inventtia Gestión',
    detalle: 'Inventario y catálogo',
    icono: Icons.inventory_2_outlined,
    color: AppColors.secondary,
  ),
  AppEcosistema(
    id: 'ventiq_marketplace',
    nombre: 'Marketplace',
    detalle: 'Catálogo de la suite',
    icono: Icons.storefront_outlined,
    color: Color(0xFF7B1FA2),
  ),
  AppEcosistema(
    id: 'inventtia_flow',
    nombre: 'GoReserva (Flow)',
    detalle: 'Turnos y reservas',
    icono: Icons.event_available_outlined,
    color: Color(0xFF00838F),
  ),
  AppEcosistema(
    id: 'inventtia_muevete',
    nombre: 'Muevete',
    detalle: 'Viajes y conductores',
    icono: Icons.local_taxi_outlined,
    color: Color(0xFFEF6C00),
  ),
];

/// Busca una app por su `app_name`; si no está en el catálogo devuelve una
/// ficha genérica para que la pantalla no se rompa con datos viejos.
AppEcosistema appEcosistema(String? id) {
  for (final app in appsEcosistema) {
    if (app.id == id) return app;
  }
  final nombre = (id == null || id.trim().isEmpty) ? 'App desconocida' : id;
  return AppEcosistema(
    id: id ?? '',
    nombre: nombre,
    detalle: 'No está en el catálogo del panel',
    icono: Icons.android_outlined,
    color: AppColors.textSecondary,
  );
}

// ── Novedades: tipo, color e icono ───────────────────────────────────────────

String etiquetaTipoNovedad(String tipo) {
  switch (tipo) {
    case NovedadVersion.tipoMejora:
      return 'Mejora';
    case NovedadVersion.tipoCorreccion:
      return 'Corrección';
    default:
      return 'Novedad';
  }
}

IconData iconoTipoNovedad(String tipo) {
  switch (tipo) {
    case NovedadVersion.tipoMejora:
      return Icons.trending_up_rounded;
    case NovedadVersion.tipoCorreccion:
      return Icons.bug_report_outlined;
    default:
      return Icons.auto_awesome;
  }
}

Color colorTipoNovedad(String tipo) {
  switch (tipo) {
    case NovedadVersion.tipoMejora:
      return AppColors.info;
    case NovedadVersion.tipoCorreccion:
      return AppColors.warning;
    default:
      return AppColors.success;
  }
}

// ── Lectura tolerante de una fila de `app_versiones` ─────────────────────────

int idDeVersion(Map<String, dynamic> version) => enteroDe(version['id']) ?? 0;

String versionDe(Map<String, dynamic> version) =>
    textoDe(version['version_actual'], porDefecto: '—');

int buildDeVersion(Map<String, dynamic> version) =>
    enteroDe(version['build_number']) ?? 0;

String? versionMinimaDe(Map<String, dynamic> version) {
  final minima = textoDe(version['version_minima']).trim();
  return minima.isEmpty ? null : minima;
}

bool obligatoriaDeVersion(Map<String, dynamic> version) =>
    boolDe(version['actualizacion_obligatoria']) ||
    boolDe(version['obligatoria']);

bool activaDeVersion(Map<String, dynamic> version) =>
    boolDe(version['activa'], porDefecto: true);

String tituloDeVersion(Map<String, dynamic> version) =>
    textoDe(version['titulo']).trim();

String? urlDescargaDeVersion(Map<String, dynamic> version) {
  final url = textoDe(version['url_descarga']).trim();
  return url.isEmpty ? null : url;
}

DateTime? fechaDeVersion(Map<String, dynamic> version) =>
    fechaDe(version['fecha_lanzamiento']) ?? fechaDe(version['created_at']);

String textoFechaVersion(Map<String, dynamic> version) =>
    fechaCorta(fechaDeVersion(version));

List<NovedadVersion> novedadesDeVersion(Map<String, dynamic> version) =>
    NovedadVersion.listaDesde(version['novedades']);

// ── Widgets pequeños reutilizables ───────────────────────────────────────────

/// Icono de una app dentro de un cuadrado tintado.
class IconoApp extends StatelessWidget {
  const IconoApp({super.key, required this.app, this.tamano = 42});

  final AppEcosistema app;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: app.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tamano * 0.28),
      ),
      child: Icon(app.icono, size: tamano * 0.52, color: app.color),
    );
  }
}

/// Píldora compacta con el número de build.
class ChipBuild extends StatelessWidget {
  const ChipBuild({super.key, required this.numero});

  final int numero;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        'build $numero',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Etiqueta de estado (obligatoria, inactiva…).
class EtiquetaBadge extends StatelessWidget {
  const EtiquetaBadge({
    super.key,
    required this.texto,
    required this.color,
    this.icono,
  });

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista de novedades de un changelog, con icono y color por tipo.
class ListaNovedades extends StatelessWidget {
  const ListaNovedades({
    super.key,
    required this.novedades,
    this.compacta = false,
    this.mostrarTipo = false,
  });

  final List<NovedadVersion> novedades;
  final bool compacta;

  /// Muestra el rótulo "NOVEDAD/MEJORA/CORRECCIÓN" encima del título.
  final bool mostrarTipo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final novedad in novedades)
          Padding(
            padding: EdgeInsets.only(bottom: compacta ? 5 : 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  iconoTipoNovedad(novedad.tipo),
                  size: compacta ? 14 : 16,
                  color: colorTipoNovedad(novedad.tipo),
                ),
                SizedBox(width: compacta ? 6 : 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mostrarTipo)
                        Text(
                          etiquetaTipoNovedad(novedad.tipo).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: colorTipoNovedad(novedad.tipo),
                          ),
                        ),
                      Text(
                        novedad.titulo,
                        style: TextStyle(
                          fontSize: compacta ? 12 : 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (!compacta && novedad.descripcion.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          novedad.descripcion,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Resumen de la última versión ─────────────────────────────────────────────

/// Tarjeta de cabecera del historial: la versión más reciente de la app.
class ResumenUltimaVersion extends StatelessWidget {
  const ResumenUltimaVersion({
    super.key,
    required this.version,
    required this.app,
    required this.onEditar,
  });

  final Map<String, dynamic> version;
  final AppEcosistema app;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final novedades = novedadesDeVersion(version);
    final titulo = tituloDeVersion(version);
    final obligatoria = obligatoriaDeVersion(version);
    final activa = activaDeVersion(version);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: app.color.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoApp(app: app, tamano: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ÚLTIMA VERSIÓN · ${app.nombre.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: app.color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'v${versionDe(version)}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ChipBuild(numero: buildDeVersion(version)),
                        if (obligatoria)
                          const EtiquetaBadge(
                            texto: 'OBLIGATORIA',
                            color: AppColors.error,
                            icono: Icons.priority_high_rounded,
                          ),
                        if (!activa)
                          const EtiquetaBadge(
                            texto: 'INACTIVA',
                            color: AppColors.textSecondary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Publicada el ${textoFechaVersion(version)} · '
                      '${novedades.length} cambio(s) en el changelog',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (titulo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
              ),
            ],
          ),
          if (novedades.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            ListaNovedades(
              novedades: novedades.take(3).toList(growable: false),
              compacta: true,
            ),
            if (novedades.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+ ${novedades.length - 3} cambio(s) más en el historial',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Tarjeta de versión del historial ─────────────────────────────────────────

/// Una versión del historial, con el changelog desplegable.
class TarjetaVersion extends StatefulWidget {
  const TarjetaVersion({
    super.key,
    required this.version,
    required this.app,
    required this.onEditar,
    required this.onEliminar,
    this.expandida = false,
  });

  final Map<String, dynamic> version;
  final AppEcosistema app;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final bool expandida;

  @override
  State<TarjetaVersion> createState() => _TarjetaVersionState();
}

class _TarjetaVersionState extends State<TarjetaVersion> {
  late bool _abierta = widget.expandida;

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
    final app = widget.app;
    final novedades = novedadesDeVersion(version);
    final titulo = tituloDeVersion(version);
    final url = urlDescargaDeVersion(version);
    final minima = versionMinimaDe(version);
    final obligatoria = obligatoriaDeVersion(version);
    final activa = activaDeVersion(version);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              activa
                  ? AppColors.divider
                  : AppColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _abierta = !_abierta),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconoApp(app: app, tamano: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'v${versionDe(version)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            ChipBuild(numero: buildDeVersion(version)),
                            if (obligatoria)
                              const EtiquetaBadge(
                                texto: 'OBLIGATORIA',
                                color: AppColors.error,
                              ),
                            if (!activa)
                              const EtiquetaBadge(
                                texto: 'INACTIVA',
                                color: AppColors.warning,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          titulo.isNotEmpty
                              ? titulo
                              : (novedades.isEmpty
                                  ? 'Sin changelog'
                                  : '${novedades.length} cambio(s)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        textoFechaVersion(version),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        _abierta ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_abierta) ...[
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (novedades.isEmpty)
                    const Text(
                      'Esta versión no tiene changelog: los usuarios verán el '
                      'aviso de actualización sin detalle de cambios.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    )
                  else
                    ListaNovedades(novedades: novedades, mostrarTipo: true),
                  if (minima != null || url != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        if (minima != null)
                          _DatoLinea(
                            icono: Icons.vertical_align_bottom_rounded,
                            texto: 'Versión mínima: $minima',
                          ),
                        if (url != null)
                          _DatoLinea(icono: Icons.link_rounded, texto: url),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: widget.onEditar,
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Editar'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: widget.onEliminar,
                        icon: const Icon(Icons.delete_outline, size: 17),
                        label: const Text('Eliminar'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DatoLinea extends StatelessWidget {
  const _DatoLinea({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Vista previa móvil ───────────────────────────────────────────────────────

/// Cómo verá el usuario el aviso de actualización en el móvil.
///
/// Es solo presentación: no simula el flujo de descarga, dibuja la tarjeta con
/// el mismo lenguaje visual que usa la app (título, versión, cambios con iconos
/// y botón de actualizar).
class VistaPreviaMovil extends StatelessWidget {
  const VistaPreviaMovil({
    super.key,
    required this.app,
    required this.version,
    required this.buildNumber,
    this.titulo = '',
    this.novedades = const [],
    this.obligatoria = false,
    this.versionMinima,
    this.urlDescarga,
    this.fecha,
  });

  final AppEcosistema app;
  final String version;
  final int buildNumber;
  final String titulo;
  final List<NovedadVersion> novedades;
  final bool obligatoria;
  final String? versionMinima;
  final String? urlDescarga;
  final String? fecha;

  @override
  Widget build(BuildContext context) {
    final versionMostrada = version.trim().isEmpty ? '1.0.0' : version.trim();
    final buildMostrado = buildNumber > 0 ? buildNumber : 1;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          color: AppColors.background,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _barraSuperior(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: Column(
                  children: [
                    IconoApp(app: app, tamano: 56),
                    const SizedBox(height: 10),
                    const Text(
                      'Nueva versión disponible',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${app.nombre} · v$versionMostrada (build $buildMostrado)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (fecha != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        fecha!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                    if (obligatoria) ...[
                      const SizedBox(height: 8),
                      const EtiquetaBadge(
                        texto: 'ACTUALIZACIÓN OBLIGATORIA',
                        color: AppColors.error,
                        icono: Icons.priority_high_rounded,
                      ),
                    ],
                    if (titulo.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        titulo.trim(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                    if (novedades.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: ListaNovedades(
                          novedades: novedades,
                          mostrarTipo: true,
                        ),
                      ),
                    ],
                    if (versionMinima != null && versionMinima!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Requiere al menos v$versionMinima',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          backgroundColor: app.color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Actualizar ahora'),
                      ),
                    ),
                    if (!obligatoria)
                      TextButton(
                        onPressed: () {},
                        child: const Text(
                          'Más tarde',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    if (urlDescarga != null &&
                        urlDescarga!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.download_outlined,
                            size: 12,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              urlDescarga!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraSuperior() {
    return Container(
      color: app.color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Text(
            app.nombre,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          const Icon(Icons.wifi, size: 11, color: Colors.white70),
          const SizedBox(width: 5),
          const Text(
            '12:30',
            style: TextStyle(fontSize: 9.5, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
