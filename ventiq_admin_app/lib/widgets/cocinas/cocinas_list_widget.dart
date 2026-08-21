import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/cocina.dart';
import '../../services/cocina_service.dart';
import 'cocina_form_dialog.dart';
import 'cocina_tpv_dialog.dart';

/// Listado de cocinas de la tienda.
///
/// Prioriza que el gerente vea de un golpe si una cocina está OPERATIVA o mal
/// configurada: una cocina sin TPV ligado no recibe comandas de nadie, y eso
/// sería invisible sin un aviso explícito.
class CocinasListWidget extends StatefulWidget {
  const CocinasListWidget({
    super.key,
    required this.searchQuery,
    required this.onRefresh,
  });

  final String searchQuery;
  final VoidCallback onRefresh;

  @override
  State<CocinasListWidget> createState() => _CocinasListWidgetState();
}

class _CocinasListWidgetState extends State<CocinasListWidget> {
  List<Cocina> _cocinas = [];
  bool _cargando = true;
  String? _error;

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
    try {
      final cocinas = await CocinaService.listarCocinas();
      if (!mounted) return;
      setState(() {
        _cocinas = cocinas;
        _cargando = false;
      });
    } on CocinaException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las cocinas: $e';
        _cargando = false;
      });
    }
  }

  List<Cocina> get _filtradas {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _cocinas;
    return _cocinas.where((c) {
      return c.denominacion.toLowerCase().contains(q) ||
          c.almacen.toLowerCase().contains(q) ||
          c.tpvs.any((t) => t.denominacion.toLowerCase().contains(q));
    }).toList();
  }

  void _refrescarTodo() {
    _cargar();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EstadoVacio(
        icono: Icons.error_outline,
        titulo: 'Error al cargar',
        detalle: _error!,
        accion: FilledButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppColors.primary,
      child: Column(
        children: [
          _ResumenCocinas(cocinas: _cocinas),
          Expanded(child: _buildLista()),
        ],
      ),
    );
  }

  Widget _buildLista() {
    final lista = _filtradas;

    if (_cocinas.isEmpty) {
      return _EstadoVacio(
        icono: Icons.soup_kitchen_outlined,
        titulo: 'Todavía no hay cocinas',
        detalle:
            'Crea una cocina para empezar a enrutar platos. Cada cocina es un '
            'almacén propio con su materia prima y sus tandas.',
        accion: FilledButton.icon(
          onPressed: () => CocinaFormDialog.mostrarCrear(
            context: context,
            onSuccess: _refrescarTodo,
          ),
          icon: const Icon(Icons.add),
          label: const Text('Crear la primera cocina'),
        ),
      );
    }

    if (lista.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.search_off,
        titulo: 'Sin resultados',
        detalle: 'Ninguna cocina coincide con la búsqueda.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 88),
      itemCount: lista.length,
      itemBuilder: (_, i) => _CocinaCard(
        cocina: lista[i],
        onEditar: () => CocinaFormDialog.mostrarEditar(
          context: context,
          cocina: lista[i],
          onSuccess: _refrescarTodo,
        ),
        onEliminar: () => CocinaFormDialog.mostrarEliminar(
          context: context,
          cocina: lista[i],
          onSuccess: _refrescarTodo,
        ),
        onLigarTpvs: () => CocinaTpvDialog.mostrar(
          context: context,
          cocina: lista[i],
          onSuccess: _refrescarTodo,
        ),
        onAlternarActiva: () => _alternarActiva(lista[i]),
      ),
    );
  }

  Future<void> _alternarActiva(Cocina cocina) async {
    try {
      await CocinaService.cambiarEstadoCocina(
        idCocina: cocina.id,
        activa: !cocina.activa,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cocina.activa
                ? '"${cocina.denominacion}" desactivada: no recibirá comandas'
                : '"${cocina.denominacion}" activada',
          ),
          backgroundColor: cocina.activa
              ? AppColors.warning
              : AppColors.success,
        ),
      );
      _refrescarTodo();
    } on CocinaException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
      );
    }
  }
}

/// Tarjeta de resumen con gradiente, igual que la de TPVs.
class _ResumenCocinas extends StatelessWidget {
  const _ResumenCocinas({required this.cocinas});

  final List<Cocina> cocinas;

  @override
  Widget build(BuildContext context) {
    final total = cocinas.length;
    final activas = cocinas.where((c) => c.activa).length;
    final conAvisos = cocinas.where((c) => !c.estaLista).length;
    final platos = cocinas.fold<int>(0, (s, c) => s + c.cantidadProductos);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Metrica(
            icono: Icons.soup_kitchen,
            valor: '$total',
            etiqueta: total == 1 ? 'Cocina' : 'Cocinas',
          ),
          _Metrica(
            icono: Icons.check_circle_outline,
            valor: '$activas',
            etiqueta: 'Activas',
          ),
          _Metrica(
            icono: Icons.restaurant_menu,
            valor: '$platos',
            etiqueta: 'Platos',
          ),
          if (conAvisos > 0)
            _Metrica(
              icono: Icons.warning_amber_rounded,
              valor: '$conAvisos',
              etiqueta: 'Por revisar',
              destacado: true,
            ),
        ],
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    this.destacado = false,
  });

  final IconData icono;
  final String valor;
  final String etiqueta;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final color = destacado ? const Color(0xFFFFD27A) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 26),
        const SizedBox(height: 6),
        Text(
          valor,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 11,
            color: color.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de una cocina: nombre, almacén, chips de estado, TPVs ligados y
/// avisos de configuración.
class _CocinaCard extends StatelessWidget {
  const _CocinaCard({
    required this.cocina,
    required this.onEditar,
    required this.onEliminar,
    required this.onLigarTpvs,
    required this.onAlternarActiva,
  });

  final Cocina cocina;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final VoidCallback onLigarTpvs;
  final VoidCallback onAlternarActiva;

  @override
  Widget build(BuildContext context) {
    final inactiva = !cocina.activa;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: inactiva ? 0 : 2,
      color: inactiva ? AppColors.surfaceVariant : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: inactiva ? AppColors.border : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(activa: cocina.activa),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cocina.denominacion,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: inactiva
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (inactiva)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.textLight.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Inactiva',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.warehouse_outlined,
                              size: 13,
                              color: AppColors.textLight,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                cocina.almacen,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (cocina.descripcion != null &&
                            cocina.descripcion!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            cocina.descripcion!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textLight,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _MenuAcciones(
                    cocina: cocina,
                    onEditar: onEditar,
                    onEliminar: onEliminar,
                    onLigarTpvs: onLigarTpvs,
                    onAlternarActiva: onAlternarActiva,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    texto: '${cocina.cantidadProductos} '
                        '${cocina.cantidadProductos == 1 ? "plato" : "platos"}',
                    icono: Icons.restaurant_menu,
                  ),
                  if (cocina.productosPorTanda > 0)
                    _Chip(
                      texto: '${cocina.productosPorTanda} por tanda',
                      icono: Icons.inventory_2_outlined,
                      color: AppColors.info,
                    ),
                  _Chip(
                    texto: '${cocina.cantidadLayouts} '
                        '${cocina.cantidadLayouts == 1 ? "ubicación" : "ubicaciones"}',
                    icono: Icons.grid_view_rounded,
                    color: AppColors.secondary,
                  ),
                  if (cocina.impresora != null && cocina.impresora!.isNotEmpty)
                    _Chip(
                      texto: cocina.impresora!,
                      icono: Icons.print_outlined,
                      color: AppColors.secondary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SeccionTpvs(cocina: cocina, onLigarTpvs: onLigarTpvs),
              if (cocina.advertencias.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...cocina.advertencias.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            a,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.activa});

  final bool activa;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: activa ? AppColors.primaryGradient : null,
        color: activa ? null : AppColors.textLight.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        Icons.soup_kitchen,
        color: activa ? Colors.white : AppColors.textSecondary,
        size: 22,
      ),
    );
  }
}

/// TPVs ligados. Si no hay ninguno, se ofrece ligar directamente: es el paso
/// que más se olvida al configurar una cocina.
class _SeccionTpvs extends StatelessWidget {
  const _SeccionTpvs({required this.cocina, required this.onLigarTpvs});

  final Cocina cocina;
  final VoidCallback onLigarTpvs;

  @override
  Widget build(BuildContext context) {
    if (cocina.tpvs.isEmpty) {
      return InkWell(
        onTap: onLigarTpvs,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.link_off, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sin TPV ligado. Toca para ligar.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.warning,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.point_of_sale, size: 14, color: AppColors.info),
            const SizedBox(width: 6),
            Text(
              'Recibe pedidos de',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onLigarTpvs,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.edit, size: 13),
              label: const Text('Cambiar', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: cocina.tpvs
              .map(
                (t) => _Chip(
                  texto: t.denominacion,
                  icono: Icons.point_of_sale,
                  color: AppColors.info,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MenuAcciones extends StatelessWidget {
  const _MenuAcciones({
    required this.cocina,
    required this.onEditar,
    required this.onEliminar,
    required this.onLigarTpvs,
    required this.onAlternarActiva,
  });

  final Cocina cocina;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final VoidCallback onLigarTpvs;
  final VoidCallback onAlternarActiva;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      onSelected: (v) => switch (v) {
        'editar' => onEditar(),
        'tpvs' => onLigarTpvs(),
        'estado' => onAlternarActiva(),
        'eliminar' => onEliminar(),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'editar',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 10),
              Text('Editar'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'tpvs',
          child: Row(
            children: [
              Icon(Icons.point_of_sale, size: 18),
              SizedBox(width: 10),
              Text('Ligar TPVs'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'estado',
          child: Row(
            children: [
              Icon(
                cocina.activa ? Icons.pause_circle_outline : Icons.play_circle_outline,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(cocina.activa ? 'Desactivar' : 'Activar'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'eliminar',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.error),
              SizedBox(width: 10),
              Text('Eliminar', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.icono, this.color});

  final String texto;
  final IconData icono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11.5,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (accion != null) ...[const SizedBox(height: 20), accion!],
          ],
        ),
      ),
    );
  }
}
