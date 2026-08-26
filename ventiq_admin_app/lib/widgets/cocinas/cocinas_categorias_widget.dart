import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/cocina.dart';
import '../../services/cocina_service.dart';

/// Cocina por defecto por categoría.
///
/// PARA QUÉ SIRVE
/// --------------
/// Asignar la cocina plato por plato es tedioso en una carta de 60 platos. Aquí
/// se dice "todo lo de Comidas va a Cocina caliente" una vez, y luego se aplica
/// en bloque.
///
/// LA CATEGORÍA SUGIERE, NO IMPONE
/// -------------------------------
/// El defecto solo se aplica a los platos que **no tienen cocina propia**. Si el
/// gerente puso "pizza margarita" en la Pizzería y la categoría apunta a Cocina
/// caliente, la pizza se queda donde estaba. Es lo que devuelve el backend en
/// `respetados` y lo que esta pantalla informa después de cada aplicación.
class CocinasCategoriasWidget extends StatefulWidget {
  const CocinasCategoriasWidget({
    super.key,
    this.searchQuery = '',
    this.onRefresh,
  });

  final String searchQuery;
  final VoidCallback? onRefresh;

  @override
  State<CocinasCategoriasWidget> createState() =>
      _CocinasCategoriasWidgetState();
}

class _CocinasCategoriasWidgetState extends State<CocinasCategoriasWidget> {
  List<Cocina> _cocinas = const [];
  List<Map<String, dynamic>> _categorias = const [];

  bool _cargando = true;
  String? _error;
  int? _ocupada;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resultados = await Future.wait([
        CocinaService.listarCocinas(),
        CocinaService.listarCategoriasConCocina(),
      ]);

      if (!mounted) return;
      setState(() {
        _cocinas = resultados[0] as List<Cocina>;
        _categorias = resultados[1] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _filtradas {
    final q = widget.searchQuery.trim().toLowerCase();
    final lista = List<Map<String, dynamic>>.from(_categorias);

    lista.sort((a, b) => _nombre(a).toLowerCase().compareTo(
          _nombre(b).toLowerCase(),
        ));

    if (q.isEmpty) return lista;
    return lista.where((c) => _nombre(c).toLowerCase().contains(q)).toList();
  }

  String _nombre(Map<String, dynamic> c) {
    final cat = c['app_dat_categoria'];
    if (cat is Map && cat['denominacion'] != null) {
      return cat['denominacion'].toString();
    }
    return 'Categoría ${c['id_categoria']}';
  }

  Cocina? _cocinaDe(Map<String, dynamic> c) {
    final id = (c['id_cocina'] as num?)?.toInt();
    if (id == null) return null;
    for (final k in _cocinas) {
      if (k.id == id) return k;
    }
    return null;
  }

  Future<void> _cambiarCocina(Map<String, dynamic> cat, int? idCocina) async {
    final idCategoria = (cat['id_categoria'] as num?)?.toInt();
    if (idCategoria == null || _ocupada != null) return;

    setState(() => _ocupada = idCategoria);
    try {
      final res = await CocinaService.asignarCocinaACategoria(
        idCategoria: idCategoria,
        idCocina: idCocina,
      );
      await _cargar();
      if (!mounted) return;
      _aviso(res['message']?.toString() ?? 'Cocina por defecto actualizada');
      widget.onRefresh?.call();
    } catch (e) {
      if (mounted) _aviso('$e', error: true);
    } finally {
      if (mounted) setState(() => _ocupada = null);
    }
  }

  Future<void> _aplicarABloque(Map<String, dynamic> cat) async {
    final idCategoria = (cat['id_categoria'] as num?)?.toInt();
    final cocina = _cocinaDe(cat);
    if (idCategoria == null || cocina == null || _ocupada != null) return;

    final modo = await showDialog<ModoElaboracion?>(
      context: context,
      builder: (ctx) => _AplicarBloqueDialog(
        categoria: _nombre(cat),
        cocina: cocina.denominacion,
      ),
    );
    if (modo == null) return;

    setState(() => _ocupada = idCategoria);
    try {
      final res = await CocinaService.aplicarCocinaCategoriaAPlatos(
        idCategoria: idCategoria,
        // El diálogo devuelve alPedido como "no cambiar el modo" cuando el
        // usuario elige dejarlo como está; ver _AplicarBloqueDialog.
        modoElaboracion: modo == ModoElaboracion.alPedido ? null : modo,
      );

      if (!mounted) return;

      final asignados = (res['total_asignados'] as num?)?.toInt() ?? 0;
      final respetados = (res['total_respetados'] as num?)?.toInt() ?? 0;

      // Se muestran los respetados en un diálogo, no en un snackbar: el gerente
      // necesita saber QUÉ platos no se movieron y por qué.
      if (respetados > 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => _ResultadoBloqueDialog(
            asignados: asignados,
            respetados: res['respetados'],
            cocina: cocina.denominacion,
          ),
        );
      } else {
        _aviso(res['message']?.toString() ?? '$asignados platos asignados');
      }

      widget.onRefresh?.call();
    } catch (e) {
      if (mounted) _aviso('$e', error: true);
    } finally {
      if (mounted) setState(() => _ocupada = null);
    }
  }

  void _aviso(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: error ? 5 : 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _vacio(
        icono: Icons.cloud_off,
        titulo: 'No se pudieron cargar las categorías',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargar,
      );
    }

    if (_cocinas.isEmpty) {
      return _vacio(
        icono: Icons.soup_kitchen_outlined,
        titulo: 'Primero crea una cocina',
        detalle: 'La cocina por defecto de una categoría se elige entre las '
            'cocinas de la tienda.',
      );
    }

    final lista = _filtradas;

    if (lista.isEmpty) {
      return _vacio(
        icono: Icons.category_outlined,
        titulo: widget.searchQuery.isEmpty
            ? 'La tienda no tiene categorías'
            : 'Sin resultados para "${widget.searchQuery}"',
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _explicacion(),
          const SizedBox(height: 10),
          for (final cat in lista) _tarjeta(cat),
        ],
      ),
    );
  }

  Widget _explicacion() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'La cocina de una categoría es una sugerencia: al aplicarla, los '
              'platos que ya tienen cocina propia no se tocan.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> cat) {
    final cocina = _cocinaDe(cat);
    final idCategoria = (cat['id_categoria'] as num?)?.toInt();
    final ocupada = _ocupada == idCategoria;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  cocina == null ? Icons.category_outlined : Icons.soup_kitchen,
                  size: 20,
                  color: cocina == null
                      ? Colors.grey.shade500
                      : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nombre(cat),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (ocupada)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              value: cocina?.id,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Cocina por defecto',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sin cocina por defecto'),
                ),
                for (final k in _cocinas)
                  DropdownMenuItem<int?>(
                    value: k.id,
                    child: Text(k.denominacion),
                  ),
              ],
              onChanged:
                  ocupada ? null : (value) => _cambiarCocina(cat, value),
            ),
            if (cocina != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: ocupada ? null : () => _aplicarABloque(cat),
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: Text('Aplicar a los platos de ${_nombre(cat)}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vacio({
    required IconData icono,
    required String titulo,
    String? detalle,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      children: [
        Icon(icono, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (detalle != null) ...[
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        if (accion != null && onAccion != null) ...[
          const SizedBox(height: 18),
          Center(
            child: FilledButton.icon(
              onPressed: onAccion,
              icon: const Icon(Icons.refresh),
              label: Text(accion),
            ),
          ),
        ],
      ],
    );
  }
}

/// Confirmación antes de aplicar en bloque, eligiendo si además fijar el modo.
class _AplicarBloqueDialog extends StatefulWidget {
  const _AplicarBloqueDialog({required this.categoria, required this.cocina});

  final String categoria;
  final String cocina;

  @override
  State<_AplicarBloqueDialog> createState() => _AplicarBloqueDialogState();
}

class _AplicarBloqueDialogState extends State<_AplicarBloqueDialog> {
  /// null = no cambiar el modo de elaboración de los platos.
  ModoElaboracion? _modo;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Aplicar a ${widget.categoria}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Los platos de "${widget.categoria}" que todavía no tengan cocina '
            'pasarán a ${widget.cocina}.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 6),
          Text(
            'Los que ya tengan cocina propia no se tocan.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Modo de elaboración',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          RadioListTile<ModoElaboracion?>(
            value: null,
            groupValue: _modo,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('No cambiarlo', style: TextStyle(fontSize: 13)),
            onChanged: (v) => setState(() => _modo = v),
          ),
          RadioListTile<ModoElaboracion?>(
            value: ModoElaboracion.alPedido,
            groupValue: _modo,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Al pedido', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Se cocina cuando lo piden',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (v) => setState(() => _modo = v),
          ),
          RadioListTile<ModoElaboracion?>(
            value: ModoElaboracion.porTanda,
            groupValue: _modo,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Por tanda', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Se produce en lote y se sirve hasta agotar',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (v) => setState(() => _modo = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          // Se devuelve alPedido para señalar "no cambiar": el llamador lo
          // traduce a null antes de mandarlo al backend. Es un apaño para poder
          // distinguir "cancelado" (null del showDialog) de "sin cambio".
          onPressed: () => Navigator.pop(
            context,
            _modo ?? ModoElaboracion.alPedido,
          ),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

/// Resultado del bulk, detallando qué platos se respetaron.
class _ResultadoBloqueDialog extends StatelessWidget {
  const _ResultadoBloqueDialog({
    required this.asignados,
    required this.respetados,
    required this.cocina,
  });

  final int asignados;
  final dynamic respetados;
  final String cocina;

  @override
  Widget build(BuildContext context) {
    final lista = respetados is List
        ? respetados.whereType<Map>().toList()
        : const <Map>[];

    return AlertDialog(
      title: const Text('Platos asignados'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$asignados plato(s) enviados a $cocina.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            'Estos ya tenían cocina propia y se dejaron como estaban:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in lista)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${r['producto']} → ${r['cocina'] ?? 'otra cocina'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
