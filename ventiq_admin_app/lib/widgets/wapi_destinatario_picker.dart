import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_destinatario.dart';
import '../models/wapi_group.dart';
import '../models/wapi_session.dart';
import '../services/wapi_notification_service.dart';

/// Resultado del picker: lista de destinatarios seleccionados.
/// Pueden ser persistidos (id != null) o nuevos (id null).
class WapiPickerResult {
  final List<WapiDestinatario> destinatarios;
  WapiPickerResult(this.destinatarios);
}

/// Picker de destinatarios. Soporta:
///   - Selección múltiple de grupos del bot
///   - Captura de número(s) de teléfono
///   - Reuso de destinatarios persistidos
class WapiDestinatarioPicker extends StatefulWidget {
  final int idTienda;
  final WapiSession sesion;

  const WapiDestinatarioPicker({
    super.key,
    required this.idTienda,
    required this.sesion,
  });

  static Future<WapiPickerResult?> show(
    BuildContext context, {
    required int idTienda,
    required WapiSession sesion,
  }) {
    final isWeb = MediaQuery.of(context).size.width >= 700;
    if (isWeb) {
      return showDialog<WapiPickerResult>(
        context: context,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 520,
            height: 600,
            child: WapiDestinatarioPicker(
              idTienda: idTienda,
              sesion: sesion,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<WapiPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: WapiDestinatarioPicker(
          idTienda: idTienda,
          sesion: sesion,
        ),
      ),
    );
  }

  @override
  State<WapiDestinatarioPicker> createState() => _WapiDestinatarioPickerState();
}

class _WapiDestinatarioPickerState extends State<WapiDestinatarioPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  final _service = WapiNotificationService.instance;
  Future<List<WapiGroup>>? _groupsFuture;
  Future<List<WapiDestinatario>>? _savedFuture;

  final Set<String> _selectedChatIds = {};
  final Map<String, WapiDestinatario> _selectedFromSaved = {};
  final List<WapiDestinatario> _newNumeros = [];
  final List<WapiGroup> _selectedGroups = [];

  final _phoneCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
  }

  void _refresh() {
    setState(() {
      _groupsFuture = widget.sesion.status == WapiStatus.connected
          ? _service.listGroups(widget.sesion.id)
          : Future.value(<WapiGroup>[]);
      _savedFuture = _service.getDestinatarios(widget.idTienda);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _phoneCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _toggleGroup(WapiGroup g) {
    setState(() {
      if (_selectedChatIds.contains(g.chatId)) {
        _selectedChatIds.remove(g.chatId);
        _selectedGroups.removeWhere((x) => x.chatId == g.chatId);
      } else {
        _selectedChatIds.add(g.chatId);
        _selectedGroups.add(g);
      }
    });
  }

  void _toggleSaved(WapiDestinatario d) {
    setState(() {
      if (_selectedChatIds.contains(d.chatId)) {
        _selectedChatIds.remove(d.chatId);
        _selectedFromSaved.remove(d.chatId);
      } else {
        _selectedChatIds.add(d.chatId);
        _selectedFromSaved[d.chatId] = d;
      }
    });
  }

  Future<void> _addNumber() async {
    final clean = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 7) {
      setState(() => _error = 'Número inválido');
      return;
    }
    final chatId = WapiDestinatario.numeroToChatId(clean);
    if (_selectedChatIds.contains(chatId)) {
      setState(() => _error = 'Ese número ya está seleccionado');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dest = await _service.upsertDestinatario(
        idTienda: widget.idTienda,
        idSesion: widget.sesion.id,
        tipo: WapiDestinatarioTipo.numero,
        chatId: chatId,
        etiqueta: _labelCtrl.text.trim().isEmpty ? null : _labelCtrl.text.trim(),
      );
      setState(() {
        _newNumeros.add(dest);
        _selectedChatIds.add(chatId);
        _selectedFromSaved[chatId] = dest;
        _phoneCtrl.clear();
        _labelCtrl.clear();
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedChatIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un destino')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = <WapiDestinatario>[];
      // 1. Persistir grupos como destinatarios (upsert)
      for (final g in _selectedGroups) {
        final d = await _service.upsertDestinatario(
          idTienda: widget.idTienda,
          idSesion: widget.sesion.id,
          tipo: WapiDestinatarioTipo.grupo,
          chatId: g.chatId,
          etiqueta: g.name,
        );
        result.add(d);
      }
      // 2. Saved + numeros ya están persistidos
      for (final d in _selectedFromSaved.values) {
        if (!result.any((r) => r.chatId == d.chatId)) result.add(d);
      }
      if (mounted) Navigator.of(context).pop(WapiPickerResult(result));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.person_pin_circle, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Selecciona destinatarios',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.group), text: 'Grupos'),
            Tab(icon: Icon(Icons.phone), text: 'Número'),
            Tab(icon: Icon(Icons.bookmark), text: 'Guardados'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildGroupsTab(),
              _buildNumberTab(),
              _buildSavedTab(),
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(
                '${_selectedChatIds.length} seleccionados',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _saving ? null : _confirm,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: const Text('Confirmar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupsTab() {
    if (widget.sesion.status != WapiStatus.connected) {
      return const _Hint(
        icon: Icons.link_off,
        text: 'Conecta el bot a WhatsApp para listar los grupos.',
      );
    }
    return FutureBuilder<List<WapiGroup>>(
      future: _groupsFuture,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Hint(icon: Icons.error_outline, text: '${snap.error}');
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const _Hint(
              icon: Icons.group_off, text: 'Este bot no tiene grupos.');
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final g = list[i];
            final selected = _selectedChatIds.contains(g.chatId);
            return CheckboxListTile(
              value: selected,
              onChanged: (_) => _toggleGroup(g),
              activeColor: AppColors.primary,
              title: Text(g.name,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                '${g.participantsCount ?? 0} participantes',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              secondary: const Icon(Icons.groups, color: AppColors.primary),
            );
          },
        );
      },
    );
  }

  Widget _buildNumberTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Introduce el número completo con código de país (sin "+").',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Número (ej: 5215512345678)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _labelCtrl,
            decoration: const InputDecoration(
              labelText: 'Etiqueta (opcional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _saving ? null : _addNumber,
            icon: const Icon(Icons.add),
            label: const Text('Añadir y seleccionar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (_newNumeros.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Añadidos en esta sesión:',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _newNumeros
                  .map((d) => Chip(
                        label: Text(d.etiqueta ?? d.chatId.split('@').first),
                        avatar: const Icon(Icons.phone, size: 16),
                        backgroundColor:
                            AppColors.primary.withOpacity(0.1),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSavedTab() {
    return FutureBuilder<List<WapiDestinatario>>(
      future: _savedFuture,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const _Hint(
              icon: Icons.bookmark_border,
              text: 'No tienes destinatarios guardados aún.');
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = list[i];
            final selected = _selectedChatIds.contains(d.chatId);
            return CheckboxListTile(
              value: selected,
              onChanged: (_) => _toggleSaved(d),
              activeColor: AppColors.primary,
              title: Text(
                d.etiqueta ?? d.chatId,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                '${d.tipo.label} • ${d.chatId}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              secondary: Icon(
                d.tipo == WapiDestinatarioTipo.grupo
                    ? Icons.groups
                    : Icons.phone,
                color: AppColors.primary,
              ),
            );
          },
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textLight),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
