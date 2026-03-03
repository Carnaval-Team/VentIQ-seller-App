import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../models/wallet_transaction_model.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
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
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
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
                'Ingresa el monto a recargar. Se aplica una comisión del 11%.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                  hintText: '0.00',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white24 : Colors.grey[400],
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.darkCard : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? AppTheme.darkBorder : Colors.grey[300]!,
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 10, 20, 50].map((amount) {
                  return GestureDetector(
                    onTap: () {
                      amountController.text = amount.toString();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '\$$amount',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Builder(builder: (ctx) {
                final parsed = double.tryParse(amountController.text);
                if (parsed != null && parsed > 0) {
                  final net = parsed * 0.89;
                  return Text(
                    'Recibirás: \$${net.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.success,
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancelar',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount > 0) {
                  Navigator.pop(dialogContext);
                  final driverId = _driverId;
                  if (driverId != null) {
                    final success = await context
                        .read<WalletProvider>()
                        .addDriverFunds(driverId, amount);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Recarga exitosa. Se acreditaron \$${(amount * 0.89).toStringAsFixed(2)}'
                                : 'Error al recargar',
                          ),
                          backgroundColor:
                              success ? AppTheme.success : AppTheme.error,
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _showAddFundsDialog,
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(
                              'Recargar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: Icon(
                              Icons.arrow_upward,
                              size: 20,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            label: Text(
                              'Retirar',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isDark
                                    ? AppTheme.darkBorder
                                    : Colors.grey[400]!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                            color: AppTheme.error.withValues(alpha: 0.3),
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
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 56,
                            color: isDark ? Colors.white24 : Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No hay transacciones aun',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color:
                                  isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Recarga tu billetera para empezar.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color:
                                  isDark ? Colors.white38 : Colors.grey[500],
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
                          padding: const EdgeInsets.only(top: 8, bottom: 10),
                          child: Text(
                            entry.key,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                        ),
                        ...entry.value.map((tx) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TransactionListItem(transaction: tx),
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
