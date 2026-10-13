import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/dashboard_entidad.dart';
import '../services/dashboard_service.dart';
import 'grafico_barras.dart';

/// Panel de totales y reservas de la entidad (punto 1 del plan de mejoras).
///
/// Va al final de la pantalla de Gestión, después de los módulos: no es un
/// acceso directo sino un resumen de "cómo va el negocio". Se carga solo, con su
/// propio estado de error, para que un fallo de la RPC **no** deje la pantalla
/// de Gestión en blanco: los módulos siguen funcionando.
class DashboardEntidadPanel extends StatefulWidget {
  const DashboardEntidadPanel({
    super.key,
    required this.idEntidad,
    required this.uuidUsuario,
  });

  final int idEntidad;
  final String uuidUsuario;

  @override
  State<DashboardEntidadPanel> createState() => _DashboardEntidadPanelState();
}

class _DashboardEntidadPanelState extends State<DashboardEntidadPanel> {
  DashboardEntidad? _data;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(DashboardEntidadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cambiar de entidad en el selector de la AppBar debe refrescar el panel.
    if (oldWidget.idEntidad != widget.idEntidad ||
        oldWidget.uuidUsuario != widget.uuidUsuario) {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await DashboardService.obtener(
        uuidUsuario: widget.uuidUsuario,
        idEntidad: widget.idEntidad,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
        _error = data == null
            ? 'No se pudieron obtener los totales de esta entidad.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron obtener los totales.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resumen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (!_cargando)
              IconButton(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Actualizar resumen',
                visualDensity: VisualDensity.compact,
                color: AppTheme.textSecondary,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _Aviso(texto: _error!, onReintentar: _cargar)
        else
          _Contenido(data: _data ?? DashboardEntidad.vacio),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.onReintentar});

  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.data});

  final DashboardEntidad data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // 2 columnas en móvil, 4 en pantalla ancha.
            final cols = constraints.maxWidth < 520 ? 2 : 4;
            final kpis = <Widget>[
              _KpiCard(
                icon: Icons.store_outlined,
                color: const Color(0xFF4F7FFA),
                titulo: 'Locales',
                conteo: data.locales,
                singular: 'local',
                plural: 'locales',
              ),
              _KpiCard(
                icon: Icons.miscellaneous_services_outlined,
                color: const Color(0xFF7C5CFC),
                titulo: 'Servicios',
                conteo: data.servicios,
                singular: 'servicio',
                plural: 'servicios',
              ),
              _KpiCard(
                icon: Icons.link_outlined,
                color: const Color(0xFF34C759),
                titulo: 'Publicados',
                subtitulo: 'local · servicio',
                conteo: data.localServicios,
                singular: 'combinación',
                plural: 'combinaciones',
              ),
              _KpiReservas(reservas: data.reservas),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: cols == 2 ? 1.45 : 1.05,
              ),
              itemCount: kpis.length,
              itemBuilder: (_, i) => kpis[i],
            );
          },
        ),
        const SizedBox(height: 20),
        _CardReservas(data: data),
        if (data.topServicios.isNotEmpty) ...[
          const SizedBox(height: 20),
          _CardTopServicios(items: data.topServicios),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.color,
    required this.titulo,
    required this.conteo,
    required this.singular,
    required this.plural,
    this.subtitulo,
  });

  final IconData icon;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final ConteoActivo conteo;
  final String singular;
  final String plural;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitulo != null)
                      Text(
                        subtitulo!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          Text(
            '${conteo.total}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.1,
            ),
          ),
          Text(
            conteo.total == 0
                ? 'Sin $plural'
                : '${conteo.activos} de ${conteo.total} '
                      '${conteo.total == 1 ? singular : plural} activos',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _KpiReservas extends StatelessWidget {
  const _KpiReservas({required this.reservas});

  final ReservasResumen reservas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5856D6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.confirmation_number_outlined,
                  color: Color(0xFF5856D6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reservas',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            '${reservas.total}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.1,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              _Punto(color: AppTheme.success, texto: '${reservas.completado}'),
              _Punto(color: AppTheme.primary, texto: '${reservas.reservado}'),
              _Punto(color: AppTheme.error, texto: '${reservas.cancelado}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _CardReservas extends StatelessWidget {
  const _CardReservas({required this.data});

  final DashboardEntidad data;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d/M');
    final porDia = data.porDia;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Reservas por día',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'últimos ${data.dias} días',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GraficoBarras(
            valores: porDia.map((d) => d.total.toDouble()).toList(),
            etiquetas: porDia.map((d) => fmt.format(d.fecha)).toList(),
            maxValor: data.maximoDiario.toDouble(),
            altura: 150,
            textoVacio: 'Sin reservas en los últimos ${data.dias} días',
          ),
        ],
      ),
    );
  }
}

class _CardTopServicios extends StatelessWidget {
  const _CardTopServicios({required this.items});

  final List<TopServicio> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Servicios con más reservas',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 18, thickness: 0.6),
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].servicio,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (items[i].local.isNotEmpty)
                        Text(
                          items[i].local,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items[i].total}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'reservas',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
