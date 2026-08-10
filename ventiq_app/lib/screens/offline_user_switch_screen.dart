import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/device_offline_prep_service.dart';
import '../services/user_preferences_service.dart';

/// Selector local de usuario cuando el dispositivo está en full offline.
/// No llama al servidor para login ni para cambiar entre admin/vendedor.
class OfflineUserSwitchScreen extends StatefulWidget {
  const OfflineUserSwitchScreen({super.key});

  @override
  State<OfflineUserSwitchScreen> createState() =>
      _OfflineUserSwitchScreenState();
}

class _OfflineUserSwitchScreenState extends State<OfflineUserSwitchScreen> {
  final _prefs = UserPreferencesService();
  final _localSession = LocalOfflineSessionService();
  final _passwordCtrl = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _selected;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final storeId = await _prefs.getDeviceFullOfflineStoreId() ??
          await _prefs.getOfflineInventoryStoreId();
      if (storeId == null) {
        setState(() {
          _users = [];
          _error = 'No hay dispositivo preparado para full offline';
        });
        return;
      }
      final users = await _prefs.getOfflineUsersForStore(storeId);
      setState(() => _users = users);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    final user = _selected;
    if (user == null) {
      setState(() => _error = 'Selecciona un usuario');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final route = await _localSession.activateFromOfflineUser(
        email: user['email']?.toString() ?? '',
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _exitDevice() async {
    final hasUnsynced = await _prefs.hasUnsyncedOfflineData();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del dispositivo'),
        content: Text(
          hasUnsynced
              ? 'Hay datos sin sincronizar. Al salir se cierra la sesión '
                  'del servidor y se desactiva el modo full offline de este teléfono. '
                  '¿Continuar?'
              : 'Se cerrará la sesión del servidor y se desactivará el modo '
                  'full offline en este dispositivo. El inventario local se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await AuthService().signOut();
    } catch (_) {}
    await _prefs.clearDeviceFullOffline();
    await _prefs.clearSessionKeepingStoreOffline();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elegir usuario'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _exitDevice,
            child: const Text(
              'Salir del dispositivo',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Dispositivo en modo offline. Elige quién trabaja '
                    '(sin conexión al servidor).',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _users.isEmpty
                        ? Center(
                            child: Text(
                              _error ?? 'No hay usuarios offline registrados',
                            ),
                          )
                        : ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final u = _users[i];
                              final email = u['email']?.toString() ?? '';
                              final name =
                                  '${u['nombres'] ?? ''} ${u['apellidos'] ?? ''}'
                                      .trim();
                              final role = u['entryRole']?.toString() ?? '';
                              final selected =
                                  _selected?['email']?.toString() == email;
                              return ListTile(
                                selected: selected,
                                leading: CircleAvatar(
                                  child: Icon(
                                    role == 'vendedor'
                                        ? Icons.point_of_sale
                                        : Icons.admin_panel_settings,
                                  ),
                                ),
                                title: Text(
                                  name.isEmpty ? email : name,
                                ),
                                subtitle: Text('$email · $role'),
                                onTap: () {
                                  setState(() {
                                    _selected = u;
                                    _passwordCtrl.clear();
                                    _error = null;
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  if (_selected != null) ...[
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _activate(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _submitting ? null : _activate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Entrar'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
    );
  }
}
