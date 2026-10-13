import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/suscripcion_admin_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/suscripcion_ui.dart';
import 'flow_suscripcion_detalle_screen.dart';

/// Bandeja de suscripciones de Inventtia Flow.
///
/// Es la pantalla de trabajo del superadmin: quién está al día, quién se cae y
/// —lo primero— quién dice haber pagado y está esperando verificación. El orden
/// de la lista lo decide el servidor poniendo delante los pagos reportados y lo
/// vencido, porque esa es la cola real de trabajo.
class FlowSuscripcionesScreen extends StatefulWidget {
  const FlowSuscripcionesScreen({super.key});

  @override
  State<FlowSuscripcionesScreen> createState() =>
      _FlowSuscripcionesScreenState();
}

class _FlowSuscripcionesScreenState extends State<FlowSuscripcionesScreen> {
  final _buscarCtrl = TextEditingController();

  String _filtro = 'todas';
  List<Map<String, dynamic>> _lista = const [];
  bool _cargando = true;
  String? _error;

  /// Filtros en el orden en que se usan, no en orden alfabético.
  static const List<({String valor, String etiqueta})> _filtros = [
    (valor: 'pagos_pendientes', etiqueta: 'Pagos por verificar'),
    (valor: 'vencidas', etiqueta: 'Vencidas'),
    (valor: 'en_gracia', etiqueta: 'En gracia'),
    (valor: 'por_vencer', etiqueta: 'Por vencer'),
    (valor: 'activas', etiqueta: 'Activas'),
    (valor: 'sin_plan', etiqueta: 'Sin plan'),
    (valor: 'suspendidas', etiqueta: 'Suspendidas'),
    (valor: 'todas', etiqueta: 'Todas'),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final lista = await SuscripcionAdminService.listar(
        filtro: _filtro,
        buscar: _buscarCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  /// Cuántos pagos reportados hay sin verificar en la lista **sin filtrar**.
  ///
  /// Se avisa con un rótulo en la barra: si el filtro activo no es el de pagos
  /// pendientes, el superadmin podría no enterarse de que hay algo esperando.
  int get _pendientesEnLista =>
      _lista.where((e) => (enteroDe(e['pagos_reportados']) ?? 0) > 0).length;

  Future<void> _abrirDetalle(Map<String, dynamic> fila) async {
    final idEntidad = enteroDe(fila['id_entidad']);
    if (idEntidad == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => FlowSuscripcionDetalleScreen(
              idEntidad: idEntidad,
              denominacion: textoDe(
                fila['denominacion'],
                porDefecto: 'Entidad',
              ),
            ),
      ),
    );

    if (mounted) await _cargar();
  }

  /// Crea la suscripción de las entidades que no tienen ninguna.
  ///
  /// Es una acción **manual y explícita** a propósito: el backfill automático
  /// habría creado filas para todas las entidades de golpe, y con eso o se les
  /// regalaba un trial a todas o se apagaba a todo el mundo. Preguntando los días
  /// (0 = dejarlas en "sin plan") el superadmin decide caso por caso.
  Future<void> _inicializar() async {
    final dias = await showDialog<int>(
      context: context,
      builder: (_) => const _DialogoInicializar(),
    );
    if (dias == null || !mounted) return;

    _mostrarCargando('Inicializando suscripciones…');
    try {
      final n = await SuscripcionAdminService.inicializar(dias: dias);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _avisar(
        n == 0
            ? 'Todas las entidades ya tenían suscripción.'
            : 'Se inicializaron $n entidad(es).',
        esError: false,
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _avisar('$e', esError: true);
    }
  }

  void _mostrarCargando(String texto) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(texto)),
              ],
            ),
          ),
    );
  }

  void _avisar(String mensaje, {required bool esError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Suscripciones Flow'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más acciones',
            onSelected: (v) {
              switch (v) {
                case 'inicializar':
                  _inicializar();
                case 'planes':
                  Navigator.pushNamed(
                    context,
                    '/flow-planes',
                  ).then((_) => _cargar());
                case 'config':
                  Navigator.pushNamed(
                    context,
                    '/flow-config',
                  ).then((_) => _cargar());
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(
                    value: 'inicializar',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.playlist_add_check),
                      title: Text('Inicializar suscripciones'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'planes',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.workspace_premium_outlined),
                      title: Text('Planes'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'config',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune),
                      title: Text('Configuración'),
                    ),
                  ),
                ],
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          if (_pendientesEnLista > 0 && _filtro != 'pagos_pendientes')
            Material(
              color: AppColors.error.withValues(alpha: 0.10),
              child: InkWell(
                onTap: () {
                  setState(() => _filtro = 'pagos_pendientes');
                  _cargar();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hay $_pendientesEnLista entidad(es) con pagos sin verificar. Toca para verlas.',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _buscarCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(),
              decoration: InputDecoration(
                hintText: 'Buscar entidad…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _buscarCtrl.text.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _buscarCtrl.clear();
                            _cargar();
                          },
                        ),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children:
                  _filtros
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              f.etiqueta,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _filtro == f.valor,
                            onSelected: (_) {
                              setState(() => _filtro = f.valor);
                              _cargar();
                            },
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.textHint),
              const SizedBox(height: 12),
              const Text(
                'No se pudo cargar la bandeja',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_lista.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay entidades que cumplan este filtro.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _lista.length,
        itemBuilder:
            (_, i) => _TarjetaEntidad(
              fila: _lista[i],
              onTap: () => _abrirDetalle(_lista[i]),
            ),
      ),
    );
  }
}

class _TarjetaEntidad extends StatelessWidget {
  const _TarjetaEntidad({required this.fila, required this.onTap});

  final Map<String, dynamic> fila;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estado = textoDe(fila['estado'], porDefecto: 'sin_suscripcion');
    final reportados = enteroDe(fila['pagos_reportados']) ?? 0;
    final vence = fechaDe(fila['fecha_vencimiento']);
    final dias = enteroDe(fila['dias_restantes']);
    final plan = textoDe(fila['plan_nombre']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: TarjetaFlow(
          borde:
              reportados > 0
                  ? AppColors.error.withValues(alpha: 0.5)
                  : AppColors.divider,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      textoDe(fila['denominacion'], porDefecto: 'Entidad'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EstadoPill(estado: estado),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _MiniDato(
                    icono: Icons.workspace_premium_outlined,
                    texto: plan.isEmpty ? 'Sin plan' : plan,
                  ),
                  _MiniDato(
                    icono: Icons.event,
                    texto: 'Vence ${fechaCorta(vence)}',
                  ),
                  if (dias != null)
                    _MiniDato(
                      icono: Icons.timelapse,
                      texto:
                          dias >= 0
                              ? 'Quedan $dias día(s)'
                              : 'Vencida hace ${-dias} día(s)',
                      color: dias < 0 ? AppColors.error : null,
                    ),
                ],
              ),
              if (reportados > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reportados == 1
                              ? '1 pago reportado sin verificar'
                              : '$reportados pagos reportados sin verificar',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.error,
                      ),
                    ],
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

class _MiniDato extends StatelessWidget {
  const _MiniDato({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: c),
        const SizedBox(width: 4),
        Text(texto, style: TextStyle(fontSize: 12, color: c)),
      ],
    );
  }
}

/// Pregunta con cuántos días se inicializan las entidades sin suscripción.
///
/// `0` es una opción legítima y está explicada: deja la entidad en "sin plan",
/// que es lo que se quiere cuando no se le va a regalar tiempo a nadie. El
/// default viene de la configuración (meses de trial), para que el caso normal
/// sea un solo toque.
class _DialogoInicializar extends StatefulWidget {
  const _DialogoInicializar();

  @override
  State<_DialogoInicializar> createState() => _DialogoInicializarState();
}

class _DialogoInicializarState extends State<_DialogoInicializar> {
  final _diasCtrl = TextEditingController(text: '30');
  bool _cargandoConfig = true;

  @override
  void initState() {
    super.initState();
    _leerConfig();
  }

  @override
  void dispose() {
    _diasCtrl.dispose();
    super.dispose();
  }

  Future<void> _leerConfig() async {
    try {
      final cfg = await SuscripcionAdminService.config();
      final meses = enteroDe(cfg['trial_meses_default']) ?? 1;
      if (!mounted) return;
      setState(() {
        _diasCtrl.text = '${meses * 30}';
        _cargandoConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoConfig = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Inicializar suscripciones'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crea la suscripción de las entidades que todavía no tienen ninguna. '
            'No toca a las que ya la tienen.',
            style: TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diasCtrl,
            enabled: !_cargandoConfig,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Días a otorgar',
              helperText: '0 = dejarlas en "sin plan" (sin regalar tiempo)',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _cargandoConfig
                  ? null
                  : () => Navigator.pop(
                    context,
                    int.tryParse(_diasCtrl.text.trim()) ?? 30,
                  ),
          child: const Text('Inicializar'),
        ),
      ],
    );
  }
}
