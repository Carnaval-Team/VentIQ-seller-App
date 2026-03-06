import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_theme.dart';
import '../../models/wallet_transaction_model.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/profile_photo_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/wallet_balance_card.dart';
import '../../widgets/transaction_list_item.dart';
import 'incoming_requests_screen.dart';
import 'driver_profile_screen.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWalletData();
    });
  }

  int? get _driverId =>
      context.read<AuthProvider>().driverProfile?['id'] as int?;

  void _loadWalletData() {
    final walletProvider = context.read<WalletProvider>();
    final driverId = _driverId;

    if (driverId != null) {
      walletProvider.loadDriverBalance(driverId);
      walletProvider.loadDriverTransactions(driverId);
    }
  }

  void _showAddFundsDialog() {
    final isDark = context.read<ThemeProvider>().isDark;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final parsed = double.tryParse(amountController.text);
            final totalPagar =
                parsed != null && parsed > 0 ? parsed * 1.11 : null;

            return AlertDialog(
              backgroundColor:
                  isDark ? AppTheme.darkSurface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Recargar Billetera',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ingresa el monto a acreditar. Se aplica 11% de comision.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                      hintText: '0.00',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color:
                            isDark ? Colors.white24 : Colors.grey[400],
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppTheme.darkCard
                          : Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : Colors.grey[300]!,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  if (totalPagar != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkCard
                            : AppTheme.primaryColor
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Debes pagar:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${totalPagar.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '(\$${parsed!.toStringAsFixed(2)} recarga + 11% comision)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amount =
                        double.tryParse(amountController.text);
                    if (amount != null && amount > 0) {
                      Navigator.pop(dialogContext);
                      final driverId = _driverId;
                      if (driverId != null) {
                        final txId = await context
                            .read<WalletProvider>()
                            .addDriverFunds(driverId, amount);
                        if (mounted && txId != null) {
                          _showVerificacionDialog(txId, amount);
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al recargar'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Confirmar',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showVerificacionDialog(int transaccionId, double montoRecarga) {
    final isDark = context.read<ThemeProvider>().isDark;
    final detalleController = TextEditingController();
    String? _pickedImageName;
    XFile? _pickedFile;
    final totalPagar = montoRecarga * 1.11;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor:
                  isDark ? AppTheme.darkSurface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Verificar Recarga',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkCard
                            : AppTheme.primaryColor
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Importe a pagar:',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${totalPagar.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '(\$${montoRecarga.toStringAsFixed(2)} recarga + 11% comision)',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sube la foto de tu comprobante de pago y agrega una referencia.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color:
                            isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                          maxWidth: 1024,
                        );
                        if (file != null) {
                          setDialogState(() {
                            _pickedFile = file;
                            _pickedImageName = file.name;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkCard
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _pickedImageName != null
                                ? AppTheme.success
                                : (isDark
                                    ? AppTheme.darkBorder
                                    : Colors.grey[300]!),
                            width: _pickedImageName != null ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _pickedImageName != null
                                  ? Icons.check_circle
                                  : Icons.camera_alt_outlined,
                              color: _pickedImageName != null
                                  ? AppTheme.success
                                  : (isDark
                                      ? Colors.white38
                                      : Colors.grey[500]),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _pickedImageName ?? 'Subir comprobante',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _pickedImageName != null
                                      ? AppTheme.success
                                      : (isDark
                                          ? Colors.white54
                                          : Colors.grey[600]),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detalleController,
                      maxLines: 2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Referencia (ej: Transferencia #12345)',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white24
                              : Colors.grey[400],
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppTheme.darkCard
                            : Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppTheme.darkBorder
                                : Colors.grey[300]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppTheme.darkBorder
                                : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final detalle = detalleController.text.trim();
                    if (detalle.isEmpty && _pickedFile == null) return;
                    Navigator.pop(dialogContext);

                    String? imagenUrl;
                    if (_pickedFile != null) {
                      try {
                        final photoService = ProfilePhotoService();
                        final bytes =
                            await photoService.compress(_pickedFile!);
                        imagenUrl = await photoService.upload(
                          'verificacion_$transaccionId',
                          bytes,
                        );
                      } catch (_) {}
                    }

                    final success = await context
                        .read<WalletProvider>()
                        .uploadVerificacion(
                          transaccionId: transaccionId,
                          imagenUrl: imagenUrl,
                          detalleTexto:
                              detalle.isNotEmpty ? detalle : null,
                        );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Verificacion enviada. Tu recarga sera revisada.'
                                : 'Error al enviar verificacion.',
                          ),
                          backgroundColor: success
                              ? AppTheme.success
                              : AppTheme.error,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Enviar',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, List<WalletTransactionModel>> _groupTransactionsByDate(
      List<WalletTransactionModel> transactions) {
    final Map<String, List<WalletTransactionModel>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final tx in transactions) {
      String label;
      final txDate = tx.createdAt ?? DateTime.now();
      final txDay = DateTime(txDate.year, txDate.month, txDate.day);

      if (txDay == today) {
        label = 'Hoy';
      } else if (txDay == yesterday) {
        label = 'Ayer';
      } else {
        label = Helpers.formatDateTime(txDate).split(' ').first;
      }

      grouped.putIfAbsent(label, () => []);
      grouped[label]!.add(tx);
    }
    return grouped;
  }

  void _onNavTap(int index) {
    if (index == 2) return; // Already on wallet
    Navigator.pop(context);
    switch (index) {
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const IncomingRequestsScreen(),
          ),
        );
        break;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DriverProfileScreen(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final walletProvider = context.watch<WalletProvider>();
    final isDark = themeProvider.isDark;

    final groupedTransactions =
        _groupTransactionsByDate(walletProvider.transactions);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mi Billetera',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: walletProvider.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryColor,
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                _loadWalletData();
              },
              color: AppTheme.primaryColor,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                children: [
                  WalletBalanceCard(
                    balance: walletProvider.balance,
                    onAddFunds: _showAddFundsDialog,
                    onWithdraw: () {},
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Historial de Transacciones',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (walletProvider.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                AppTheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppTheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                walletProvider.error!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppTheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (walletProvider.transactions.isEmpty &&
                      walletProvider.error == null)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 56,
                            color: isDark
                                ? Colors.white24
                                : Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No hay transacciones aun',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Recarga tu billetera para empezar.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...groupedTransactions.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 8, bottom: 10),
                          child: Text(
                            entry.key,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                        ...entry.value.map((tx) {
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 8),
                            child: TransactionListItem(
                              transaction: tx,
                              onVerificar: tx.estado ==
                                          EstadoTransaccion
                                              .pendiente &&
                                      tx.id != null
                                  ? () =>
                                      _showVerificacionDialog(
                                          tx.id!, tx.monto ?? 0)
                                  : null,
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: isDark ? Colors.white54 : Colors.grey,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Viajes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Billetera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
