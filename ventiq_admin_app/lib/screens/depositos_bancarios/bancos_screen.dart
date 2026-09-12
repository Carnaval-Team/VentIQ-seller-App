import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/depositos_bancarios.dart';
import '../../services/depositos_bancarios_service.dart';

class BancosScreen extends StatefulWidget {
  const BancosScreen({super.key});

  @override
  State<BancosScreen> createState() => _BancosScreenState();
}

class _BancosScreenState extends State<BancosScreen> {
  final DepositosBancariosService _service = DepositosBancariosService();
  List<BancoDeposito> _bancos = [];
  List<MonedaDeposito> _monedas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getBancos(),
        _service.getMonedas(soloActivas: true),
      ]);
      setState(() {
        _bancos = results[0] as List<BancoDeposito>;
        _monedas = results[1] as List<MonedaDeposito>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando bancos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showBancoDialog({BancoDeposito? banco}) async {
    if (_monedas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Crea al menos una moneda activa antes de agregar bancos',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final isEditing = banco != null;
    final nombreCtrl = TextEditingController(text: banco?.denominacion ?? '');
    final obsCtrl = TextEditingController(text: banco?.observacion ?? '');
    int? idMoneda = banco?.idMoneda ?? _monedas.first.id;
    bool activo = banco?.activo ?? true;
    bool esPredeterminada = banco?.esPredeterminadaFondoCaja ?? false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar banco' : 'Nuevo banco'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: idMoneda,
                  decoration: const InputDecoration(
                    labelText: 'Moneda *',
                    border: OutlineInputBorder(),
                  ),
                  items: _monedas
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.codigo} (${m.simbolo})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => idMoneda = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observación',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: activo,
                  onChanged: (v) => setDialogState(() {
                    activo = v;
                    if (!v) esPredeterminada = false;
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cuenta predeterminada de Fondo de Caja'),
                  subtitle: const Text(
                    'Los egresos contabilizados alimentarán esta cuenta',
                  ),
                  value: esPredeterminada,
                  onChanged: activo
                      ? (v) => setDialogState(() => esPredeterminada = v)
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty || idMoneda == null) return;
                Navigator.pop(ctx);
                try {
                  if (isEditing) {
                    await _service.updateBanco(
                      id: banco.id,
                      denominacion: nombre,
                      idMoneda: idMoneda!,
                      observacion: obsCtrl.text.trim().isEmpty
                          ? null
                          : obsCtrl.text.trim(),
                      activo: activo,
                      esPredeterminadaFondoCaja: esPredeterminada,
                    );
                  } else {
                    await _service.createBanco(
                      denominacion: nombre,
                      idMoneda: idMoneda!,
                      observacion: obsCtrl.text.trim().isEmpty
                          ? null
                          : obsCtrl.text.trim(),
                      activo: activo,
                      esPredeterminadaFondoCaja: esPredeterminada,
                    );
                  }
                  await _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEditing ? 'Banco actualizado' : 'Banco creado',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivate(BancoDeposito banco) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar banco'),
        content: Text('¿Desactivar "${banco.denominacion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deactivateBanco(banco.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bancos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showBancoDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bancos.isEmpty
          ? const Center(child: Text('No hay bancos. Crea el primero.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _bancos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final b = _bancos[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.account_balance,
                      color: b.activo ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(b.denominacion),
                    subtitle: Text(
                      [
                        b.monedaLabel.isNotEmpty
                            ? 'Moneda: ${b.monedaLabel}'
                            : null,
                        b.activo ? 'Activo' : 'Inactivo',
                        if (b.esPredeterminadaFondoCaja)
                          'Predeterminada para Fondo de Caja',
                        if (b.observacion != null && b.observacion!.isNotEmpty)
                          b.observacion,
                      ].whereType<String>().join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _showBancoDialog(banco: b);
                        if (v == 'off') _deactivate(b);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar'),
                        ),
                        if (b.activo)
                          const PopupMenuItem(
                            value: 'off',
                            child: Text('Desactivar'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
