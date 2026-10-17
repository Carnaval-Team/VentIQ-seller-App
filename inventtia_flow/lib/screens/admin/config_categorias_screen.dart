import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../services/auth_service.dart';
import '../../services/tipo_actividad_service.dart';
import '../../tutorial/tutorial_anchor.dart';

/// Visibilidad de categorías para los servicios de **una entidad**.
///
/// Las categorías y subcategorías las gestiona **solo el superadmin**
/// (`ventiq_superadmin`). Aquí la taxonomía es de **solo lectura**: no se crean,
/// no se editan, no se eliminan y no se desactivan.
///
/// Lo único que decide el admin de entidad en esta pantalla es qué categorías
/// **oculta** para sus propios servicios. Ocultar NO toca el nomenclador: la
/// categoría sigue activa y sigue pintada en el riel de filtros del Home. Lo que
/// cambia es que los servicios/locales de esta entidad en esa categoría dejan de
/// aparecer en el catálogo del cliente.
///
/// Un servicio se clasifica por su **hoja**: la categoría raíz o una de sus
/// subcategorías (`flow.nom_tipo_actividad_servicio.id_padre`). Por eso ocultar
/// una categoría raíz esconde también sus subcategorías (lo evalúa el servidor
/// comparando contra la hoja y contra su padre), y aquí los interruptores de las
/// subcategorías se desactivan para dejarlo claro.
class ConfigCategoriasScreen extends StatefulWidget {
  const ConfigCategoriasScreen({super.key, required this.entidad});

  /// Entidad cuyos servicios se ocultan o se muestran.
  final Entidad entidad;

  @override
  State<ConfigCategoriasScreen> createState() => _ConfigCategoriasScreenState();
}

class _ConfigCategoriasScreenState extends State<ConfigCategoriasScreen> {
  Taxonomia _taxonomia = Taxonomia.vacia;

  /// Ids del nomenclador que ESTA entidad tiene ocultos (raíces y/o hijas).
  Set<int> _ocultas = <int>{};

  bool _cargando = true;
  String? _error;

  /// `true` cuando falta la migración `55_categorias_ocultas_por_entidad.sql`:
  /// la taxonomía se puede leer, pero el interruptor todavía no funciona.
  bool _migracionPendiente = false;

  /// Categorías abiertas en el acordeón, para ver y gestionar sus subcategorías.
  final Set<int> _expandidas = <int>{};

  /// Nodos con un cambio en curso: su interruptor se deshabilita mientras viaja.
  final Set<int> _cambiando = <int>{};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    var migracionPendiente = false;
    try {
      // Solo lo activo: es exactamente lo que el cliente puede ver en el riel.
      // Las categorías que el superadmin desactivó no se listan aquí.
      final taxonomia = await TipoActividadService.taxonomia(soloActivos: true);
      Set<int> ocultas;
      try {
        ocultas = await TipoActividadService.ocultasDeEntidad(
          widget.entidad.id,
        );
      } catch (e) {
        if (!_esMigracion55Pendiente(e)) rethrow;
        migracionPendiente = true;
        ocultas = <int>{};
      }
      if (!mounted) return;
      setState(() {
        _taxonomia = taxonomia;
        _ocultas = ocultas;
        _migracionPendiente = migracionPendiente;
        _cargando = false;
        // Si una categoría abierta desapareció, se deja de recordar.
        _expandidas.removeWhere(
          (id) => !_taxonomia.todas.any((t) => t.id == id),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos leer las categorías: $e';
        _cargando = false;
      });
    }
  }

  List<TipoActividad> get _categorias => _taxonomia.raices;

  /// `true` si el nodo está oculto por sí mismo o porque lo está su categoría
  /// padre. Es el estado que el cliente percibe.
  bool _estaOculta(TipoActividad nodo) =>
      _ocultas.contains(nodo.id) ||
      (nodo.idPadre != null && _ocultas.contains(nodo.idPadre));

  /// `true` si el nodo no tiene fila propia pero su padre sí está oculto.
  bool _ocultaPorPadre(TipoActividad nodo) =>
      nodo.idPadre != null &&
      !_ocultas.contains(nodo.id) &&
      _ocultas.contains(nodo.idPadre);

  Future<void> _alternar(TipoActividad nodo) async {
    if (AuthService.currentUserId == null) return;
    final ocultar = !_ocultas.contains(nodo.id);
    setState(() => _cambiando.add(nodo.id));
    try {
      await TipoActividadService.ocultarParaEntidad(
        idEntidad: widget.entidad.id,
        idNodo: nodo.id,
        oculto: ocultar,
      );
      if (!mounted) return;
      setState(() {
        if (ocultar) {
          _ocultas.add(nodo.id);
        } else {
          _ocultas.remove(nodo.id);
        }
        _cambiando.remove(nodo.id);
      });
      if (!ocultar) {
        _avisar('«${nodo.nombre}» vuelve a mostrarse.');
        return;
      }
      final hijas = nodo.esSubcategoria
          ? 0
          : _taxonomia.subcategoriasDe(nodo.id).length;
      _avisar(
        hijas == 0
            ? '«${nodo.nombre}» oculta: tus servicios de esa categoría ya no '
                  'aparecen en el catálogo.'
            : '«${nodo.nombre}» oculta, con sus $hijas subcategorías: tus '
                  'servicios ya no aparecen en el catálogo.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cambiando.remove(nodo.id));
      if (_esMigracion55Pendiente(e)) {
        setState(() => _migracionPendiente = true);
        _avisar(
          'Falta aplicar la migración 55_categorias_ocultas_por_entidad.sql '
          'en Supabase.',
          error: true,
        );
        return;
      }
      _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  /// `true` cuando el error significa "la migración 55 no está aplicada" (ni la
  /// tabla ni el RPC existen todavía).
  static bool _esMigracion55Pendiente(Object e) {
    final texto = e.toString();
    return texto.contains('PGRST205') ||
        texto.contains('PGRST202') ||
        texto.contains('entidad_categoria_oculta') ||
        texto.contains('admin_ocultar_categoria_entidad') ||
        texto.contains('Could not find the table') ||
        texto.contains('Could not find the function');
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: error ? AppTheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _categorias;
    final totalSubcategorias = _taxonomia.todas
        .where((t) => t.esSubcategoria)
        .length;
    final ocultasVisibles = _ocultas
        .where((id) => _taxonomia.porId(id) != null)
        .length;

    final resumen = StringBuffer(
      categorias.length == 1 ? '1 categoría' : '${categorias.length} categorías',
    )
      ..write(' · ')
      ..write(
        totalSubcategorias == 1
            ? '1 subcategoría'
            : '$totalSubcategorias subcategorías',
      );
    if (ocultasVisibles > 0) resumen.write(' · $ocultasVisibles ocultas');

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Categorías')),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: _cargando && _taxonomia.estaVacia
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  TutorialAnchor(
                    id: 'admin_categorias',
                    child: _ExplicacionCard(
                      entidad: widget.entidad.denominacion,
                    ),
                  ),
                  if (_migracionPendiente) ...[
                    const SizedBox(height: 12),
                    const _AvisoMigracionCard(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(mensaje: _error!, onReintentar: _cargar),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    resumen.toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (categorias.isEmpty && _error == null)
                    const _VacioCard()
                  else
                    ...categorias.map(
                      (categoria) => _CategoriaCard(
                        categoria: categoria,
                        subcategorias: _taxonomia.subcategoriasDe(categoria.id),
                        expandida: _expandidas.contains(categoria.id),
                        oculta: _estaOculta(categoria),
                        cambiando: _cambiando.contains(categoria.id),
                        onToggleExpandir: () => setState(() {
                          if (!_expandidas.remove(categoria.id)) {
                            _expandidas.add(categoria.id);
                          }
                        }),
                        onAlternar: () => _alternar(categoria),
                        subcategoriaOculta: _estaOculta,
                        subcategoriaOcultaPorPadre: _ocultaPorPadre,
                        subcategoriaCambiando: _cambiando.contains,
                        onAlternarSubcategoria: _alternar,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ExplicacionCard extends StatelessWidget {
  const _ExplicacionCard({required this.entidad});

  /// Denominación de la entidad cuyos servicios se ocultan.
  final String entidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cómo se usan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Las categorías y subcategorías las crea, edita y desactiva el '
                  'superadmin: aquí no se añaden ni se eliminan.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Lo que sí decides es qué categorías quieres ocultar para '
                  '$entidad. Ocultar no la quita del riel de filtros del Home ni '
                  'la desactiva: solo hace que tus servicios y locales de esa '
                  'categoría dejen de aparecer en el catálogo del cliente, en los '
                  'patrocinados y en las colecciones. Puedes volver a mostrarla '
                  'cuando quieras.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoMigracionCard extends StatelessWidget {
  const _AvisoMigracionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Falta aplicar en este proyecto de Supabase la migración '
              '`55_categorias_ocultas_por_entidad.sql`. Hasta entonces la '
              'taxonomía se puede consultar, pero ocultar y volver a mostrar no '
              'funciona.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorCard({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 20),
              SizedBox(width: 8),
              Text(
                'No se pudo leer',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _VacioCard extends StatelessWidget {
  const _VacioCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 38,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'Todavía no hay categorías activas',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Las crea el superadmin. Cuando existan, aquí podrás decidir cuáles '
            'ocultas para tus servicios.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de una categoría con su lista desplegable de subcategorías.
class _CategoriaCard extends StatelessWidget {
  final TipoActividad categoria;
  final List<TipoActividad> subcategorias;
  final bool expandida;
  final bool oculta;
  final bool cambiando;
  final VoidCallback onToggleExpandir;
  final VoidCallback onAlternar;

  final bool Function(TipoActividad) subcategoriaOculta;
  final bool Function(TipoActividad) subcategoriaOcultaPorPadre;
  final bool Function(int) subcategoriaCambiando;
  final void Function(TipoActividad) onAlternarSubcategoria;

  const _CategoriaCard({
    required this.categoria,
    required this.subcategorias,
    required this.expandida,
    required this.oculta,
    required this.cambiando,
    required this.onToggleExpandir,
    required this.onAlternar,
    required this.subcategoriaOculta,
    required this.subcategoriaOcultaPorPadre,
    required this.subcategoriaCambiando,
    required this.onAlternarSubcategoria,
  });

  @override
  Widget build(BuildContext context) {
    final ocultasHijas = subcategorias.where(subcategoriaOculta).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: oculta
              ? AppTheme.textSecondary.withValues(alpha: 0.35)
              : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Row(
              children: [
                // Desplegar solo tiene sentido si hay hijas, pero se deja también
                // sin ellas para poder ver qué implica ocultar la categoría.
                IconButton(
                  onPressed: onToggleExpandir,
                  tooltip: expandida
                      ? 'Ocultar subcategorías'
                      : 'Ver subcategorías',
                  icon: Icon(
                    expandida
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              categoria.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: oculta
                                    ? AppTheme.textSecondary
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (oculta) ...[
                            const SizedBox(width: 7),
                            const _EtiquetaOculta(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subcategorias.isEmpty
                            ? '${categoria.codigo} · sin subcategorías'
                            : '${categoria.codigo} · $ocultasHijas de '
                                  '${subcategorias.length} subcategorías '
                                  'ocultas',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: !oculta,
                  activeTrackColor: AppTheme.primary,
                  onChanged: cambiando ? null : (_) => onAlternar(),
                ),
              ],
            ),
          ),
          if (expandida)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 6),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                border: const Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (oculta)
                    const Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(
                        'La categoría está oculta: sus subcategorías también '
                        'quedan fuera del catálogo.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  if (subcategorias.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Esta categoría no tiene subcategorías: sus servicios se '
                        'clasifican solo por ella.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    )
                  else
                    ...subcategorias.map(
                      (sub) => _SubcategoriaTile(
                        subcategoria: sub,
                        oculta: subcategoriaOculta(sub),
                        ocultaPorPadre: subcategoriaOcultaPorPadre(sub),
                        cambiando: subcategoriaCambiando(sub.id),
                        onAlternar: () => onAlternarSubcategoria(sub),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubcategoriaTile extends StatelessWidget {
  final TipoActividad subcategoria;
  final bool oculta;
  final bool ocultaPorPadre;
  final bool cambiando;
  final VoidCallback onAlternar;

  const _SubcategoriaTile({
    required this.subcategoria,
    required this.oculta,
    required this.ocultaPorPadre,
    required this.cambiando,
    required this.onAlternar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 17,
            color: AppTheme.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subcategoria.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: oculta
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (oculta) ...[
                      const SizedBox(width: 6),
                      const _EtiquetaOculta(),
                    ],
                  ],
                ),
                Text(
                  ocultaPorPadre
                      ? '${subcategoria.codigo} · oculta con la categoría'
                      : subcategoria.codigo,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            // Si la categoría padre está oculta, esta subcategoría ya no se
            // muestra al cliente: el interruptor queda bloqueado para no dar a
            // entender que se puede activar por separado. Al volver a mostrar la
            // categoría, recupera su propio estado.
            value: !oculta,
            activeTrackColor: AppTheme.primary,
            onChanged: (cambiando || ocultaPorPadre) ? null : (_) => onAlternar(),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaOculta extends StatelessWidget {
  const _EtiquetaOculta();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'OCULTA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}
