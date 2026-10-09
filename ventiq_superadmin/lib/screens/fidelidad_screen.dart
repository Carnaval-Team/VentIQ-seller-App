import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/fidelidad.dart';
import '../services/auth_service.dart';
import '../services/catalogo_destinos_service.dart';
import '../services/fidelidad_service.dart';
import '../widgets/app_drawer.dart';

/// Panel del programa de fidelidad: interruptor global, reglas de acumulación,
/// beneficios de bienvenida y auditoría de puntos.
///
/// **Comprueba en el servidor, no aquí.** Las 10 RPC exigen
/// `fn_is_superadmin_full_access()`, así que la pantalla se gatea con
/// [AuthService.hasFullAccess] — *no* con `canWrite()`, que deja pasar hasta
/// nivel 2 y mostraría botones que el servidor rechaza.
///
/// Todo lo que se pinta viene de las RPC salvo las **etiquetas** de lectura. El
/// panel nunca recalcula un saldo ni un descuento: dos implementaciones de
/// "cuántos puntos tengo" es exactamente cómo aparecen los descuadres.
class FidelidadScreen extends StatefulWidget {
  const FidelidadScreen({super.key});

  @override
  State<FidelidadScreen> createState() => _FidelidadScreenState();
}

class _FidelidadScreenState extends State<FidelidadScreen> {
  FidelidadConfig _config = const FidelidadConfig();
  List<ReglaFidelidadAdmin> _reglas = const [];
  List<BeneficioBienvenidaAdmin> _beneficios = const [];
  List<({int id, String etiqueta})> _entidades = const [];

  bool _cargando = true;
  bool _cambiandoSwitch = false;
  String? _error;

  // Auditoría de puntos
  final TextEditingController _uuidCtrl = TextEditingController();
  AuditoriaPuntos? _auditoria;
  bool _auditando = false;
  String? _errorAuditoria;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _uuidCtrl.dispose();
    super.dispose();
  }

  String get _uuid => AuthService.currentSuperAdmin?.uuid ?? '';

  /// `silencioso` evita el spinner al refrescar tras una acción: si no, la
  /// pantalla parpadea entera y se pierde el sitio donde estabas.
  Future<void> _cargar({bool silencioso = false}) async {
    if (!mounted) return;
    setState(() {
      if (!silencioso) _cargando = true;
      _error = null;
    });
    try {
      final config = await FidelidadService.obtenerConfig(uuidUsuario: _uuid);
      final reglas = await FidelidadService.listarReglas(uuidUsuario: _uuid);
      final beneficios = await FidelidadService.listarBeneficios(
        uuidUsuario: _uuid,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _reglas = reglas;
        _beneficios = beneficios;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mensajeError(e);
        _cargando = false;
      });
    }
  }

  String _mensajeError(Object e) {
    final t = e.toString();
    if (t.contains('PGRST202') || t.contains('Could not find the function')) {
      return 'Faltan aplicar las migraciones 32 y 33 (panel de fidelidad) en '
          'Supabase.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: error ? AppColors.error : null,
        ),
      );
  }

  // ── Interruptor global ─────────────────────────────────────────────────────

  Future<void> _alternarSwitch(bool valor) async {
    setState(() => _cambiandoSwitch = true);
    try {
      final aviso = await FidelidadService.guardarConfig(
        uuidUsuario: _uuid,
        activa: valor,
      );
      await _cargar(silencioso: true);
      if (!mounted) return;
      _avisar(
        aviso ?? (valor ? 'Fidelidad activada.' : 'Fidelidad desactivada.'),
      );
    } catch (e) {
      if (mounted) _avisar(_mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _cambiandoSwitch = false);
    }
  }

  // ── Reglas ─────────────────────────────────────────────────────────────────

  /// Las entidades se cargan bajo demanda y una sola vez: no hacen falta para
  /// ver las listas.
  Future<bool> _asegurarEntidades() async {
    if (_entidades.isNotEmpty) return true;
    try {
      _entidades = await CatalogoDestinosService.entidades();
      return true;
    } catch (e) {
      if (mounted) _avisar('No se pudieron leer las entidades: $e', error: true);
      return false;
    }
  }

  Future<void> _abrirFormularioRegla({ReglaFidelidadAdmin? regla}) async {
    if (!await _asegurarEntidades()) return;
    if (!mounted) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _ReglaDialog(regla: regla, entidades: _entidades),
    );
    if (guardado != true || !mounted) return;
    await _cargar(silencioso: true);
    if (mounted) _avisar(regla == null ? 'Regla creada.' : 'Regla actualizada.');
  }

  Future<void> _eliminarRegla(ReglaFidelidadAdmin r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar regla'),
        content: Text(
          '¿Eliminar «${r.nombre}» (${r.etiquetaAlcance})?\n\n'
          'Los puntos que ya concedió **no se borran**: el libro de movimientos '
          'es la auditoría y se conserva. Solo deja de aplicar hacia adelante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FidelidadService.eliminarRegla(uuidUsuario: _uuid, id: r.id);
      await _cargar(silencioso: true);
      if (mounted) _avisar('Regla eliminada.');
    } catch (e) {
      if (mounted) _avisar(_mensajeError(e), error: true);
    }
  }

  // ── Beneficios ─────────────────────────────────────────────────────────────

  Future<void> _abrirFormularioBeneficio({
    BeneficioBienvenidaAdmin? beneficio,
  }) async {
    if (!await _asegurarEntidades()) return;
    if (!mounted) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _BeneficioDialog(beneficio: beneficio, entidades: _entidades),
    );
    if (guardado != true || !mounted) return;
    await _cargar(silencioso: true);
    if (mounted) {
      _avisar(beneficio == null ? 'Beneficio creado.' : 'Beneficio actualizado.');
    }
  }

  Future<void> _eliminarBeneficio(BeneficioBienvenidaAdmin b) async {
    // Con canjes anotados el servidor lo rechaza (`on delete restrict`): se
    // avisa antes de intentarlo, en vez de dejar que falle.
    if (!b.sePuedeBorrar) {
      _avisar(
        'No se puede borrar: ${b.etiquetaCanjes}. Desactívalo para que deje de '
        'aplicar sin perder el registro de quién lo usó.',
        error: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar beneficio'),
        content: Text(
          '¿Eliminar «${b.titulo}»?\n\n'
          'Nadie lo ha canjeado todavía, así que no se pierde ningún registro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FidelidadService.eliminarBeneficio(uuidUsuario: _uuid, id: b.id);
      await _cargar(silencioso: true);
      if (mounted) _avisar('Beneficio eliminado.');
    } catch (e) {
      if (mounted) _avisar(_mensajeError(e), error: true);
    }
  }

  // ── Auditoría de puntos ────────────────────────────────────────────────────

  Future<void> _consultarPuntos() async {
    final destino = _uuidCtrl.text.trim();
    if (destino.isEmpty) {
      _avisar('Escribe el UUID del cliente.', error: true);
      return;
    }
    setState(() {
      _auditando = true;
      _errorAuditoria = null;
      _auditoria = null;
    });
    try {
      final a = await FidelidadService.auditarPuntos(
        uuidUsuario: _uuid,
        uuidDestino: destino,
      );
      if (!mounted) return;
      setState(() {
        _auditoria = a;
        _auditando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorAuditoria = _mensajeError(e);
        _auditando = false;
      });
    }
  }

  Future<void> _abrirAjuste() async {
    final a = _auditoria;
    if (a == null) return;
    final ajuste = await showDialog<({int puntos, String motivo})>(
      context: context,
      builder: (_) => _AjusteDialog(saldoActual: a.saldo),
    );
    if (ajuste == null || !mounted) return;
    try {
      final r = await FidelidadService.ajustarPuntos(
        uuidUsuario: _uuid,
        uuidDestino: a.uuidUsuario,
        puntos: ajuste.puntos,
        motivo: ajuste.motivo,
      );
      await _consultarPuntos();
      if (mounted) {
        _avisar('Saldo: ${r.saldoAnterior} → ${r.saldoNuevo} puntos.');
      }
    } catch (e) {
      if (mounted) _avisar(_mensajeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeEditar = AuthService.hasFullAccess();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Programa de fidelidad'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _cargar(),
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _cargar(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _ExplicacionCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(mensaje: _error!, onReintentar: () => _cargar()),
                  ],
                  if (!puedeEditar) ...[
                    const SizedBox(height: 12),
                    const _SinPermisoCard(),
                  ],
                  const SizedBox(height: 12),
                  _InterruptorCard(
                    activa: _config.activa,
                    ocupado: _cambiandoSwitch,
                    puedeEditar: puedeEditar,
                    onCambiar: _alternarSwitch,
                  ),

                  // ── Reglas ──
                  _SeccionTitulo(
                    titulo: 'Reglas de acumulación',
                    detalle:
                        'Cuántos puntos gana el cliente por cada reserva. La '
                        'regla global aplica a todos; una por entidad solo a sus '
                        'servicios y tiene prioridad.',
                    accion: puedeEditar
                        ? _BotonNuevo(
                            etiqueta: 'Nueva regla',
                            onPressed: () => _abrirFormularioRegla(),
                          )
                        : null,
                  ),
                  if (_reglas.isEmpty)
                    const _VacioCard(
                      mensaje:
                          'No hay reglas. Sin ninguna regla vigente no se '
                          'acreditan puntos, aunque la fidelidad esté activada.',
                    )
                  else
                    ..._reglas.map(
                      (r) => _ReglaCard(
                        regla: r,
                        puedeEditar: puedeEditar,
                        onEditar: () => _abrirFormularioRegla(regla: r),
                        onEliminar: () => _eliminarRegla(r),
                      ),
                    ),

                  // ── Beneficios ──
                  _SeccionTitulo(
                    titulo: 'Beneficios de bienvenida',
                    detalle:
                        'Descuento real en la primera reserva. Se aplica '
                        'DESPUÉS de la promoción y sobre lo que queda. Cada '
                        'cliente lo puede gastar una sola vez.',
                    accion: puedeEditar
                        ? _BotonNuevo(
                            etiqueta: 'Nuevo beneficio',
                            onPressed: () => _abrirFormularioBeneficio(),
                          )
                        : null,
                  ),
                  if (_beneficios.isEmpty)
                    const _VacioCard(
                      mensaje: 'No hay beneficios de bienvenida configurados.',
                    )
                  else
                    ..._beneficios.map(
                      (b) => _BeneficioCard(
                        beneficio: b,
                        puedeEditar: puedeEditar,
                        onEditar: () => _abrirFormularioBeneficio(beneficio: b),
                        onEliminar: () => _eliminarBeneficio(b),
                      ),
                    ),

                  // ── Auditoría ──
                  _SeccionTitulo(
                    titulo: 'Auditoría de puntos',
                    detalle:
                        'Consulta el saldo y el historial de un cliente, y '
                        'corrige a mano cuando haga falta. Todo ajuste queda '
                        'asentado con su motivo: no hay forma de cambiar un '
                        'saldo sin dejar rastro.',
                  ),
                  _AuditoriaCard(
                    controller: _uuidCtrl,
                    auditoria: _auditoria,
                    cargando: _auditando,
                    error: _errorAuditoria,
                    puedeEditar: puedeEditar,
                    onConsultar: _consultarPuntos,
                    onAjustar: _abrirAjuste,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ── Piezas de lectura ────────────────────────────────────────────────────────

class _ExplicacionCard extends StatelessWidget {
  const _ExplicacionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.loyalty_outlined, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'El cliente acumula puntos al COMPLETAR una reserva (no al '
                'reservarla) y los ve en su Home. El saldo no es una columna: '
                'es la suma del libro de movimientos, así que nunca puede '
                'descuadrar con la auditoría.\n\n'
                'Apagar la fidelidad es PAUSAR, no borrar: el libro se conserva '
                'y al reactivar se sigue acumulando donde se quedó.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterruptorCard extends StatelessWidget {
  const _InterruptorCard({
    required this.activa,
    required this.ocupado,
    required this.puedeEditar,
    required this.onCambiar,
  });

  final bool activa;
  final bool ocupado;
  final bool puedeEditar;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: activa
          ? AppColors.success.withValues(alpha: 0.08)
          : AppColors.warning.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: (activa ? AppColors.success : AppColors.warning).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: SwitchListTile(
        value: activa,
        onChanged: (puedeEditar && !ocupado) ? onCambiar : null,
        secondary: ocupado
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                activa ? Icons.toggle_on : Icons.toggle_off,
                color: activa ? AppColors.success : AppColors.warning,
                size: 32,
              ),
        title: Text(
          activa ? 'Fidelidad ACTIVADA' : 'Fidelidad DESACTIVADA',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          activa
              ? 'Los clientes acumulan puntos y ven su saldo en el Home. El '
                    'beneficio de bienvenida también se aplica.'
              : 'Nadie acumula puntos y el Home no muestra la sección. Los '
                    'puntos ya ganados NO se borran: al reactivar, el cliente '
                    'los vuelve a ver.',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  const _SeccionTitulo({
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (accion != null) accion!,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detalle,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BotonNuevo extends StatelessWidget {
  const _BotonNuevo({required this.etiqueta, required this.onPressed});

  final String etiqueta;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReglaCard extends StatelessWidget {
  const _ReglaCard({
    required this.regla,
    required this.puedeEditar,
    required this.onEditar,
    required this.onEliminar,
  });

  final ReglaFidelidadAdmin regla;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final vigente = regla.vigente;
    return Card(
      elevation: 0,
      color: AppColors.cardBackground,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    regla.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (puedeEditar) ...[
                  IconButton(
                    onPressed: onEditar,
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    onPressed: onEliminar,
                    tooltip: 'Eliminar',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              regla.etiquetaRegla,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  texto: regla.etiquetaAlcance,
                  color: regla.esGlobal
                      ? AppColors.secondary
                      : AppColors.primary,
                  icono: regla.esGlobal ? Icons.public : Icons.storefront,
                ),
                if (regla.etiquetaVigencia != null)
                  _Chip(
                    texto: regla.etiquetaVigencia!,
                    color: AppColors.textSecondary,
                    icono: Icons.schedule,
                  ),
                _Chip(
                  texto: vigente ? 'Vigente' : 'No aplica',
                  color: vigente ? AppColors.success : AppColors.textSecondary,
                  icono: vigente ? Icons.check_circle : Icons.pause_circle,
                ),
              ],
            ),
            if (regla.desde != null || regla.hasta != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ventana: ${_fechaCorta(regla.desde)} → ${_fechaCorta(regla.hasta)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BeneficioCard extends StatelessWidget {
  const _BeneficioCard({
    required this.beneficio,
    required this.puedeEditar,
    required this.onEditar,
    required this.onEliminar,
  });

  final BeneficioBienvenidaAdmin beneficio;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final vigente = beneficio.vigente;
    return Card(
      elevation: 0,
      color: AppColors.cardBackground,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    beneficio.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (puedeEditar) ...[
                  IconButton(
                    onPressed: onEditar,
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    onPressed: onEliminar,
                    tooltip: beneficio.sePuedeBorrar
                        ? 'Eliminar'
                        : 'No se puede borrar: ya tiene canjes',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: beneficio.sePuedeBorrar
                          ? AppColors.error
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              beneficio.etiquetaDescuento,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
            if (beneficio.descripcion != null &&
                beneficio.descripcion!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                beneficio.descripcion!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  texto: beneficio.etiquetaAlcance,
                  color: beneficio.esGlobal
                      ? AppColors.secondary
                      : AppColors.primary,
                  icono: beneficio.esGlobal ? Icons.public : Icons.storefront,
                ),
                if (beneficio.montoMinimo != null)
                  _Chip(
                    texto:
                        'Mínimo ${_numero(beneficio.montoMinimo!)}${beneficio.moneda != null ? ' ${beneficio.moneda}' : ''}',
                    color: AppColors.textSecondary,
                    icono: Icons.shopping_cart_outlined,
                  ),
                _Chip(
                  texto: beneficio.etiquetaCanjes,
                  color: beneficio.canjes > 0
                      ? AppColors.info
                      : AppColors.textSecondary,
                  icono: Icons.redeem,
                ),
                _Chip(
                  texto: vigente ? 'Vigente' : 'No aplica',
                  color: vigente ? AppColors.success : AppColors.textSecondary,
                  icono: vigente ? Icons.check_circle : Icons.pause_circle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditoriaCard extends StatelessWidget {
  const _AuditoriaCard({
    required this.controller,
    required this.auditoria,
    required this.cargando,
    required this.error,
    required this.puedeEditar,
    required this.onConsultar,
    required this.onAjustar,
  });

  final TextEditingController controller;
  final AuditoriaPuntos? auditoria;
  final bool cargando;
  final String? error;
  final bool puedeEditar;
  final VoidCallback onConsultar;
  final VoidCallback onAjustar;

  @override
  Widget build(BuildContext context) {
    final a = auditoria;
    return Card(
      elevation: 0,
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'UUID del cliente',
                hintText: '00000000-0000-0000-0000-000000000000',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.person_search),
              ),
              onSubmitted: (_) => onConsultar(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: cargando ? null : onConsultar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                  ),
                  icon: cargando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Consultar saldo'),
                ),
                const SizedBox(width: 8),
                if (a != null && puedeEditar)
                  OutlinedButton.icon(
                    onPressed: onAjustar,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Ajustar'),
                  ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            if (a != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.stars,
                    color: a.saldo > 0 ? AppColors.warning : AppColors.textHint,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${a.saldo} ${a.saldo == 1 ? 'punto' : 'puntos'}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (a.yaCanjeo)
                    const _Chip(
                      texto: 'Ya usó la bienvenida',
                      color: AppColors.info,
                      icono: Icons.redeem,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                a.uuidUsuario,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textHint,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              if (a.sinMovimientos)
                const Text(
                  'Sin movimientos. Este cliente todavía no ha completado una '
                  'reserva.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                )
              else ...[
                Text(
                  'Últimos ${a.movimientos.length} movimientos',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                ...a.movimientos.map((m) => _MovimientoTile(movimiento: m)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  const _MovimientoTile({required this.movimiento});

  final MovimientoPuntosAdmin movimiento;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final positivo = m.puntos > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: (positivo ? AppColors.success : AppColors.error).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              m.etiquetaPuntos,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: positivo ? AppColors.success : AppColors.error,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      m.etiquetaTipo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (m.vencido) ...[
                      const SizedBox(width: 6),
                      const _Chip(
                        texto: 'Caducado',
                        color: AppColors.error,
                        icono: Icons.timer_off,
                      ),
                    ],
                  ],
                ),
                if (m.motivo != null && m.motivo!.trim().isNotEmpty)
                  Text(
                    m.motivo!,
                    style: const TextStyle(fontSize: 11),
                  ),
                if (m.regla != null)
                  Text(
                    'Regla: ${m.regla}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                Text(
                  [
                    _fechaHora(m.createdAt),
                    if (m.monto != null)
                      '${_numero(m.monto!)}${m.moneda != null ? ' ${m.moneda}' : ''}',
                    if (m.idAgenda != null) 'agenda #${m.idAgenda}',
                    if (m.venceEn != null) 'vence ${_fechaCorta(m.venceEn)}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textHint,
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

class _VacioCard extends StatelessWidget {
  const _VacioCard({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: AppColors.textHint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.error.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error),
                SizedBox(width: 8),
                Text(
                  'No se pudo cargar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(mensaje, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinPermisoCard extends StatelessWidget {
  const _SinPermisoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.warning.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Solo lectura. El programa de fidelidad exige acceso total '
                '(nivel 1): con tu nivel puedes verlo, pero no editarlo.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formularios ──────────────────────────────────────────────────────────────

class _ReglaDialog extends StatefulWidget {
  const _ReglaDialog({this.regla, required this.entidades});

  final ReglaFidelidadAdmin? regla;
  final List<({int id, String etiqueta})> entidades;

  @override
  State<_ReglaDialog> createState() => _ReglaDialogState();
}

class _ReglaDialogState extends State<_ReglaDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _puntos;
  late final TextEditingController _monto;
  late final TextEditingController _vigencia;
  late final TextEditingController _moneda;

  int? _idEntidad;
  bool _activo = true;
  DateTime? _desde;
  DateTime? _hasta;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.regla;
    _nombre = TextEditingController(text: r?.nombre ?? 'Programa de fidelidad');
    _puntos = TextEditingController(
      text: r == null ? '1' : _numero(r.puntosPorMonto),
    );
    _monto = TextEditingController(
      text: r == null ? '10' : _numero(r.montoBase),
    );
    _vigencia = TextEditingController(
      text: r?.vigenciaDias?.toString() ?? '365',
    );
    _moneda = TextEditingController(text: r?.moneda ?? 'USD');
    _idEntidad = r?.idEntidad;
    _activo = r?.activo ?? true;
    _desde = r?.desde;
    _hasta = r?.hasta;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _puntos.dispose();
    _monto.dispose();
    _vigencia.dispose();
    _moneda.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final puntos = double.tryParse(_puntos.text.trim().replaceAll(',', '.'));
    final monto = double.tryParse(_monto.text.trim().replaceAll(',', '.'));
    final vigenciaTexto = _vigencia.text.trim();
    final vigencia = vigenciaTexto.isEmpty
        ? null
        : int.tryParse(vigenciaTexto);
    final moneda = _moneda.text.trim();

    // Se valida aquí lo que el servidor también valida: así el usuario ve el
    // fallo al instante en vez de después de una ida y vuelta.
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (puntos == null || puntos < 0) {
      setState(() => _error = 'Los puntos por monto deben ser un número ≥ 0.');
      return;
    }
    if (monto == null || monto <= 0) {
      setState(() => _error = 'El monto base debe ser mayor que cero.');
      return;
    }
    if (vigenciaTexto.isNotEmpty && (vigencia == null || vigencia < 1)) {
      setState(() => _error = 'La vigencia debe ser de al menos 1 día.');
      return;
    }
    if (_desde != null && _hasta != null && !_hasta!.isAfter(_desde!)) {
      setState(() => _error = 'La fecha de fin debe ser posterior a la de inicio.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await FidelidadService.guardarRegla(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        nombre: nombre,
        idEntidad: _idEntidad,
        moneda: moneda.isEmpty ? null : moneda,
        puntosPorMonto: puntos,
        montoBase: monto,
        vigenciaDias: vigencia,
        activo: _activo,
        desde: _desde,
        hasta: _hasta,
        id: widget.regla?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.regla == null ? 'Nueva regla' : 'Editar regla'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _idEntidad,
                decoration: const InputDecoration(
                  labelText: 'Alcance',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos los clientes (global)'),
                  ),
                  ...widget.entidades.map(
                    (e) => DropdownMenuItem<int?>(
                      value: e.id,
                      child: Text(e.etiqueta, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _idEntidad = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _puntos,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Puntos',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Text('por cada'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _monto,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Monto base',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Ejemplo: 1 punto por cada 10 USD.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _moneda,
                      decoration: const InputDecoration(
                        labelText: 'Moneda',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _vigencia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Vigencia (días)',
                        helperText: 'Vacío = no caducan',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FilaFecha(
                etiqueta: 'Vigente desde',
                valor: _desde,
                onElegir: () => _elegirFecha(esDesde: true),
                onLimpiar: () => setState(() => _desde = null),
              ),
              _FilaFecha(
                etiqueta: 'Vigente hasta',
                valor: _hasta,
                onElegir: () => _elegirFecha(esDesde: false),
                onLimpiar: () => setState(() => _hasta = null),
              ),
              SwitchListTile(
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Activa', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Apagada = solo esta regla no se aplica',
                  style: TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _BeneficioDialog extends StatefulWidget {
  const _BeneficioDialog({this.beneficio, required this.entidades});

  final BeneficioBienvenidaAdmin? beneficio;
  final List<({int id, String etiqueta})> entidades;

  @override
  State<_BeneficioDialog> createState() => _BeneficioDialogState();
}

class _BeneficioDialogState extends State<_BeneficioDialog> {
  late final TextEditingController _titulo;
  late final TextEditingController _descripcion;
  late final TextEditingController _valor;
  late final TextEditingController _moneda;
  late final TextEditingController _minimo;

  String _tipo = 'porcentaje';
  int? _idEntidad;
  bool _activo = true;
  DateTime? _desde;
  DateTime? _hasta;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.beneficio;
    // El mínimo se saca a un local antes de decidir: `b?.montoMinimo == null`
    // NO promociona `b`, así que `b.montoMinimo!` no compila.
    final minimo = b?.montoMinimo;
    _titulo = TextEditingController(text: b?.titulo ?? 'Bienvenida');
    _descripcion = TextEditingController(text: b?.descripcion ?? '');
    _valor = TextEditingController(text: b == null ? '10' : _numero(b.valor));
    _moneda = TextEditingController(text: b?.moneda ?? 'USD');
    _minimo = TextEditingController(
      text: minimo == null ? '' : _numero(minimo),
    );
    _tipo = b?.tipo ?? 'porcentaje';
    _idEntidad = b?.idEntidad;
    _activo = b?.activo ?? true;
    _desde = b?.desde;
    _hasta = b?.hasta;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _valor.dispose();
    _moneda.dispose();
    _minimo.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    final titulo = _titulo.text.trim();
    final valor = double.tryParse(_valor.text.trim().replaceAll(',', '.'));
    final moneda = _moneda.text.trim();
    final minimoTexto = _minimo.text.trim();
    final minimo = minimoTexto.isEmpty
        ? null
        : double.tryParse(minimoTexto.replaceAll(',', '.'));

    if (titulo.isEmpty) {
      setState(() => _error = 'El título es obligatorio.');
      return;
    }
    if (valor == null || valor <= 0) {
      setState(() => _error = 'El valor debe ser mayor que cero.');
      return;
    }
    if (_tipo == 'porcentaje' && valor > 100) {
      setState(() => _error = 'Un porcentaje no puede superar el 100%.');
      return;
    }
    if (minimoTexto.isNotEmpty && minimo == null) {
      setState(() => _error = 'El mínimo no es un número válido.');
      return;
    }
    if (_desde != null && _hasta != null && !_hasta!.isAfter(_desde!)) {
      setState(() => _error = 'La fecha de fin debe ser posterior a la de inicio.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await FidelidadService.guardarBeneficio(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        titulo: titulo,
        descripcion:
            _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
        tipo: _tipo,
        valor: valor,
        moneda: moneda.isEmpty ? null : moneda,
        idEntidad: _idEntidad,
        montoMinimo: minimo,
        activo: _activo,
        desde: _desde,
        hasta: _hasta,
        id: widget.beneficio?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esPorcentaje = _tipo == 'porcentaje';
    return AlertDialog(
      title: Text(
        widget.beneficio == null ? 'Nuevo beneficio' : 'Editar beneficio',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titulo,
                decoration: const InputDecoration(
                  labelText: 'Título (lo que ve el cliente)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descripcion,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo de descuento',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'porcentaje',
                    child: Text('Porcentaje (%)'),
                  ),
                  DropdownMenuItem(
                    value: 'monto',
                    child: Text('Monto fijo'),
                  ),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? 'porcentaje'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _valor,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: esPorcentaje ? 'Porcentaje' : 'Monto',
                        suffixText: esPorcentaje ? '%' : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (!esPorcentaje) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _moneda,
                        decoration: const InputDecoration(
                          labelText: 'Moneda',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _idEntidad,
                      decoration: const InputDecoration(
                        labelText: 'Alcance',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos (global)'),
                        ),
                        ...widget.entidades.map(
                          (e) => DropdownMenuItem<int?>(
                            value: e.id,
                            child: Text(
                              e.etiqueta,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _idEntidad = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _minimo,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Gasto mínimo',
                        helperText: 'Vacío = sin mínimo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FilaFecha(
                etiqueta: 'Vigente desde',
                valor: _desde,
                onElegir: () => _elegirFecha(esDesde: true),
                onLimpiar: () => setState(() => _desde = null),
              ),
              _FilaFecha(
                etiqueta: 'Vigente hasta',
                valor: _hasta,
                onElegir: () => _elegirFecha(esDesde: false),
                onLimpiar: () => setState(() => _hasta = null),
              ),
              SwitchListTile(
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Activo', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Apagado = no se aplica ni se muestra',
                  style: TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const Text(
                'Ojo: cada cliente lo puede gastar UNA sola vez. Si ya hay '
                'canjes, no se podrá borrar (solo desactivar).',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AjusteDialog extends StatefulWidget {
  const _AjusteDialog({required this.saldoActual});

  final int saldoActual;

  @override
  State<_AjusteDialog> createState() => _AjusteDialogState();
}

class _AjusteDialogState extends State<_AjusteDialog> {
  final TextEditingController _puntos = TextEditingController();
  final TextEditingController _motivo = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _puntos.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _enviar() {
    final puntos = int.tryParse(_puntos.text.trim());
    final motivo = _motivo.text.trim();
    if (puntos == null || puntos == 0) {
      setState(() => _error = 'Escribe un número de puntos distinto de cero.');
      return;
    }
    if (widget.saldoActual + puntos < 0) {
      setState(
        () => _error =
            'Dejaría el saldo en ${widget.saldoActual + puntos}. Un saldo '
            'negativo no significa nada para el cliente.',
      );
      return;
    }
    if (motivo.isEmpty) {
      setState(
        () => _error = 'El motivo es obligatorio: un ajuste sin explicación no '
            'es auditable.',
      );
      return;
    }
    Navigator.pop(context, (puntos: puntos, motivo: motivo));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar puntos'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo actual: ${widget.saldoActual} puntos. '
              'Usa un número positivo para sumar y negativo para restar.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _puntos,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Puntos (+/-)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivo,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ej: compensación por reserva cancelada por el local',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _enviar, child: const Text('Aplicar')),
      ],
    );
  }
}

class _FilaFecha extends StatelessWidget {
  const _FilaFecha({
    required this.etiqueta,
    required this.valor,
    required this.onElegir,
    required this.onLimpiar,
  });

  final String etiqueta;
  final DateTime? valor;
  final VoidCallback onElegir;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$etiqueta: ${valor == null ? 'sin límite' : _fechaCorta(valor)}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: onElegir,
          child: const Text('Elegir'),
        ),
        if (valor != null)
          IconButton(
            onPressed: onLimpiar,
            tooltip: 'Quitar',
            icon: const Icon(Icons.clear, size: 18),
          ),
      ],
    );
  }
}

// ── Formato ──────────────────────────────────────────────────────────────────

String _fechaCorta(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/'
      '${l.month.toString().padLeft(2, '0')}/${l.year}';
}

String _fechaHora(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  return '${_fechaCorta(l)} '
      '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

/// Número sin decimales de relleno: 20.0 -> "20", 7.5 -> "7.5".
String _numero(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}