import 'package:flutter/material.dart';

import '../services/permissions_service.dart';

/// Muestra [child] solo al rol Dueño. El resto ve un aviso, sin cifras.
class ProfitGate extends StatefulWidget {
  const ProfitGate({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  State<ProfitGate> createState() => _ProfitGateState();
}

class _ProfitGateState extends State<ProfitGate> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allowed = await PermissionsService().canViewGanancias();
    if (!mounted) return;
    setState(() => _allowed = allowed);
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allowed == true) return widget.child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              widget.title ?? 'Información de ganancias restringida',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Solo el Dueño de la tienda puede ver ganancias, márgenes y rentabilidad.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
