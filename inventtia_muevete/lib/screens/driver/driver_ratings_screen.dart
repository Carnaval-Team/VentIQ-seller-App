import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/valoracion_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/driver_service.dart';

class DriverRatingsScreen extends StatefulWidget {
  const DriverRatingsScreen({super.key});

  @override
  State<DriverRatingsScreen> createState() => _DriverRatingsScreenState();
}

class _DriverRatingsScreenState extends State<DriverRatingsScreen> {
  final DriverService _driverService = DriverService();
  List<ValoracionModel>? _ratings;
  double? _averageRating;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    final driverId =
        context.read<AuthProvider>().driverProfile?['id'] as int?;
    if (driverId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final ratings = await _driverService.getDriverRatings(driverId);
      final avg = await _driverService.getDriverAverageRating(driverId);
      if (mounted) {
        setState(() {
          _ratings = ratings;
          _averageRating = avg;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Mis Valoraciones',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ratings == null || _ratings!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded,
                          size: 64,
                          color: isDark ? Colors.white24 : Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'Aún no tienes valoraciones',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          color: isDark ? Colors.white54 : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRatings,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Header card with average
                      _buildAverageHeader(isDark),
                      const SizedBox(height: 20),
                      // List of ratings
                      ...(_ratings!.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildRatingCard(r, isDark),
                          ))),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAverageHeader(bool isDark) {
    final total = _ratings?.length ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            _averageRating?.toStringAsFixed(1) ?? '—',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              final avg = _averageRating ?? 0;
              return Icon(
                starNum <= avg.round()
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: AppTheme.warning,
                size: 24,
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '$total ${total == 1 ? 'valoración' : 'valoraciones'}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: isDark ? Colors.white54 : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingCard(ValoracionModel rating, bool isDark) {
    final dateStr = _formatDate(rating.createdAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Stars
              ...List.generate(5, (i) {
                return Icon(
                  i < rating.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: AppTheme.warning,
                  size: 18,
                );
              }),
              const Spacer(),
              Text(
                dateStr,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ],
          ),
          if (rating.comentario != null &&
              rating.comentario!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              rating.comentario!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
          if (rating.userName != null) ...[
            const SizedBox(height: 8),
            Text(
              rating.userName!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }
}
