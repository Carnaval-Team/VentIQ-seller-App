import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/home_catalog_service.dart';
import '../widgets/home_hero_header.dart';
import '../widgets/net_image.dart';
import '../widgets/notificaciones_bell.dart';
import 'local_servicio_detail_screen.dart';

class HomeClientScreen extends StatefulWidget {
  const HomeClientScreen({super.key});

  @override
  State<HomeClientScreen> createState() => HomeClientScreenState();
}

class HomeClientScreenState extends State<HomeClientScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _sponsoredController = PageController(viewportFraction: 0.86);
  final _searchFocusNode = FocusNode();

  final Set<int> _savedIds = <int>{9001, 9005};
  Timer? _countdownTimer;
  Timer? _searchDebounce;
  late final AnimationController _shineController;

  List<HomeCatalogItem> _items = const [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isMock = false;
  int _page = 1;
  int _sponsoredPage = 0;
  String _query = '';
  String _category = 'Todas';
  String _location = 'Santa Clara, Villa Clara';
  bool _nearMe = false;
  bool _openNow = false;
  bool _topRated = false;
  Duration _flashRemaining = const Duration(hours: 4, minutes: 12, seconds: 39);

  static const _categories = <_HomeCategory>[
    _HomeCategory('Todas', '▦', Icons.grid_view_rounded),
    _HomeCategory('Belleza', '✦', Icons.auto_awesome_rounded),
    _HomeCategory('Uñas', '✧', Icons.back_hand_rounded),
    _HomeCategory('Cejas & Pestañas', '◌', Icons.remove_red_eye_outlined),
    _HomeCategory('Transporte', '↗', Icons.directions_bus_filled_outlined),
    _HomeCategory('Salud', '+', Icons.medical_services_outlined),
    _HomeCategory('Hogar', '⌂', Icons.home_repair_service_outlined),
    _HomeCategory('Mascotas', '♡', Icons.pets_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final seconds = _flashRemaining.inSeconds - 1;
        _flashRemaining = Duration(seconds: seconds > 0 ? seconds : 0);
      });
    });
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sponsoredController.dispose();
    _countdownTimer?.cancel();
    _searchDebounce?.cancel();
    _shineController.dispose();
    super.dispose();
  }

  Future<void> reload() => _refresh();

  Future<void> _refresh() async {
    await HomeCatalogService.clearCache();
    if (!mounted) return;
    await _loadPage(reset: true);
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_isLoadingMore && !reset) return;
    if (!reset && !_hasMore) return;
    if (reset) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        _items = const [];
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final page = await HomeCatalogService.fetchPage(
        page: reset ? 1 : _page + 1,
        query: _query,
        category: _category,
        onlyOpen: _openNow,
        topRated: _topRated,
        nearMe: _nearMe,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _page = page.page;
        _hasMore = page.hasMore;
        _isMock = page.isMock;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
      _showToast(
        'No pudimos actualizar el catálogo.',
        actionLabel: 'Reintentar',
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 520) {
      _loadPage();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _query = value);
      _loadPage(reset: true);
    });
  }

  void _selectCategory(String category) {
    if (_category == category) return;
    setState(() => _category = category);
    _loadPage(reset: true);
  }

  void _toggleSaved(HomeCatalogItem item) {
    setState(() {
      if (!_savedIds.add(item.id)) _savedIds.remove(item.id);
    });
    _showToast(
      _savedIds.contains(item.id)
          ? '${item.title} guardado en Mis Listas.'
          : '${item.title} eliminado de Mis Listas.',
      actionLabel: 'Ver listas',
    );
  }

  void _openItem(HomeCatalogItem item) {
    final localServicio = item.localServicio;
    if (localServicio == null) {
      _showToast('Esta tarjeta es una vista previa. Pronto podrás reservarla.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalServicioDetailScreen(localServicio: localServicio),
      ),
    );
  }

  void _showToast(String message, {String? actionLabel}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: AppTheme.accent,
                  onPressed: () {
                    if (actionLabel == 'Reintentar') {
                      _refresh();
                    } else {
                      _showToast('Abre Mis Listas desde la barra inferior.');
                    }
                  },
                ),
        ),
      );
  }

  Future<void> _showLocationPicker() async {
    final options = ['Santa Clara, Villa Clara', 'Centro', 'Cerca de mí'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elige tu ubicación', style: _SectionTitleStyle()),
              const SizedBox(height: 6),
              const Text(
                'Veremos servicios y disponibilidad cerca de ti.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ...options.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    option == 'Cerca de mí'
                        ? Icons.my_location_outlined
                        : Icons.location_on_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(option),
                  trailing: option == _location
                      ? const Icon(Icons.check_circle, color: AppTheme.accent)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _location = selected == 'Cerca de mí' ? 'Cerca de mí' : selected;
      _nearMe = selected == 'Cerca de mí';
    });
    _showToast('Ubicación actualizada.');
  }

  Future<void> _showAdvancedFilters() async {
    var nearMe = _nearMe;
    var openNow = _openNow;
    var topRated = _topRated;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filtros avanzados', style: _SectionTitleStyle()),
                const SizedBox(height: 4),
                const Text(
                  'Ajusta el resultado sin salir del Home.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: nearMe,
                  onChanged: (value) => setSheetState(() => nearMe = value),
                  title: const Text('Cerca de mí'),
                  secondary: const Icon(Icons.near_me_outlined),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: openNow,
                  onChanged: (value) => setSheetState(() => openNow = value),
                  title: const Text('Abierto ahora'),
                  secondary: const Icon(Icons.schedule_outlined),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: topRated,
                  onChanged: (value) => setSheetState(() => topRated = value),
                  title: const Text('Mejor valorados'),
                  secondary: const Icon(Icons.star_outline_rounded),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Aplicar filtros'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _nearMe = nearMe;
      _openNow = openNow;
      _topRated = topRated;
      if (_nearMe) _location = 'Cerca de mí';
    });
    _loadPage(reset: true);
    _showToast('Filtros aplicados a tu exploración.');
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().perfil;
    final firstName = profile?.nombre.trim().isNotEmpty == true
        ? profile!.nombre.trim().split(' ').first
        : 'María';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: HomeHeroHeader(
                topBar: _buildTopBar(firstName),
                searchCard: _buildSearchHero(),
              ),
            ),
            SliverToBoxAdapter(child: _buildCategories()),
            SliverToBoxAdapter(child: _buildCollections()),
            SliverToBoxAdapter(child: _buildSponsoredCarousel()),
            SliverToBoxAdapter(child: _buildFlashOffers()),
            SliverToBoxAdapter(child: _buildRecommended()),
            SliverToBoxAdapter(child: _buildPopularPlaces()),
            SliverToBoxAdapter(child: _buildWeeklyPopular()),
            SliverToBoxAdapter(child: _buildReviewOfDay()),
            SliverToBoxAdapter(child: _buildLoyaltyBanner()),
            SliverToBoxAdapter(child: _buildHowItWorks()),
            SliverToBoxAdapter(child: _buildFeedHeader()),
            if (_isLoading && _items.isEmpty)
              const SliverToBoxAdapter(child: _LoadingBlock()),
            if (!_isLoading && _items.isEmpty)
              SliverToBoxAdapter(child: _buildNoResults()),
            if (_items.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, index) => _FeedServiceCard(
                    item: _items[index],
                    saved: _savedIds.contains(_items[index].id),
                    onTap: () => _openItem(_items[index]),
                    onSave: () => _toggleSaved(_items[index]),
                  ),
                  childCount: _items.length,
                ),
              ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(child: _LoadingMoreBlock()),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(String firstName) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3654), Color(0xFF3E4E80)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPLORA',
                          style: TextStyle(
                            color: AppTheme.accent.withValues(alpha: 0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Hola, $firstName 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Encuentra tu próximo servicio sin filas.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const NotificacionesBell(color: Colors.white),
                  const SizedBox(width: 8),
                  _StatusAvatar(
                    initial: firstName.substring(0, 1).toUpperCase(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _showLocationPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _location,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHero() {
    // La cabecera pinta el fondo índigo detrás de los primeros 26 px de la
    // tarjeta. Todo el buscador queda dentro del área del mismo sliver.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar servicio, local o categoría…',
                  hintStyle: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primary,
                    size: 21,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Buscar por voz',
                        onPressed: () => _showToast(
                          'La búsqueda por voz estará disponible pronto.',
                        ),
                        icon: const Icon(
                          Icons.mic_none_rounded,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                      Container(width: 1, height: 20, color: AppTheme.border),
                      IconButton(
                        tooltip: 'Filtros avanzados',
                        onPressed: _showAdvancedFilters,
                        icon: const Icon(
                          Icons.tune_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _QuickChip(
                    label: 'Cerca de mí',
                    icon: Icons.location_on_outlined,
                    selected: _nearMe,
                    onTap: () {
                      setState(() {
                        _nearMe = !_nearMe;
                        if (_nearMe) _location = 'Cerca de mí';
                      });
                      _loadPage(reset: true);
                    },
                  ),
                  _QuickChip(
                    label: 'Abierto ahora',
                    live: true,
                    selected: _openNow,
                    onTap: () {
                      setState(() => _openNow = !_openNow);
                      _loadPage(reset: true);
                    },
                  ),
                  _QuickChip(
                    label: 'Mejor valorados',
                    icon: Icons.star_rounded,
                    selected: _topRated,
                    onTap: () {
                      setState(() => _topRated = !_topRated);
                      _loadPage(reset: true);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Categorías principales', trailing: 'Desliza →'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final category = _categories[index];
                final selected = category.name == _category;
                return GestureDetector(
                  onTap: () => _selectCategory(category.name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: selected ? AppTheme.primary : AppTheme.border,
                      ),
                      boxShadow: selected
                          ? const []
                          : const [
                              BoxShadow(
                                color: Color(0x0D2B3A67),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        Text(
                          category.emoji,
                          style: TextStyle(
                            color: selected
                                ? AppTheme.accent
                                : AppTheme.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          category.name,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollections() {
    const collections = [
      _Collection('Pack Novia', '12 servicios', '💍', [
        Color(0xFF8C5B72),
        Color(0xFFC98CA4),
      ]),
      _Collection('Self-care Sunday', '8 servicios', '🧖‍♀️', [
        Color(0xFF1C7C7A),
        Color(0xFF64B6AC),
      ]),
      _Collection('Ruta & Transporte', '5 opciones', '🚌', [
        Color(0xFF395B91),
        Color(0xFF6D9DD1),
      ]),
      _Collection('Ofertas del día', 'Hasta 20% menos', '⚡', [
        Color(0xFF2C3654),
        Color(0xFF1FA8B8),
      ]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Colecciones destacadas', trailing: 'Explorar'),
          const SizedBox(height: 4),
          const Text(
            'Experiencias curadas para ti',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 11),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: collections.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 112,
            ),
            itemBuilder: (_, index) => _CollectionCard(
              collection: collections[index],
              onTap: () {
                final category = index == 2
                    ? 'Transporte'
                    : index == 3
                    ? 'Todas'
                    : 'Belleza';
                _selectCategory(category);
                _showToast('Explorando ${collections[index].title}.');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsoredCarousel() {
    const sponsored = [
      _Sponsored('Luna Studio', 'Tu momento empieza aquí', Icons.spa_outlined, [
        Color(0xFF6D547D),
        Color(0xFFC795B0),
      ]),
      _Sponsored(
        'Casa Aura',
        'Reserva en menos de un minuto',
        Icons.face_retouching_natural_outlined,
        [Color(0xFF275B68), Color(0xFF45A2A1)],
      ),
      _Sponsored(
        'Moverte',
        'Llega a tiempo, sin esperas',
        Icons.directions_car_filled_outlined,
        [Color(0xFF324B78), Color(0xFF5D83C1)],
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Espacio patrocinado', trailing: 'Ver todo'),
          const SizedBox(height: 10),
          SizedBox(
            height: 166,
            child: PageView.builder(
              controller: _sponsoredController,
              itemCount: sponsored.length,
              onPageChanged: (index) => setState(() => _sponsoredPage = index),
              itemBuilder: (_, index) {
                final item = sponsored[index];
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 16 : 5,
                    right: index == sponsored.length - 1 ? 16 : 5,
                  ),
                  child: _SponsoredCard(
                    sponsored: item,
                    onTap: () =>
                        _showToast('Abriendo el perfil de ${item.name}.'),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              sponsored.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _sponsoredPage ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _sponsoredPage
                      ? AppTheme.primary
                      : AppTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashOffers() {
    final offers = _items.where((item) => item.discount > 0).take(4).toList();
    final displayOffers = offers.isEmpty
        ? const [
            HomeCatalogItem(
              id: 9991,
              title: 'Masaje relajante',
              venue: 'Alma Spa',
              category: 'Belleza',
              price: 30,
              originalPrice: 38,
              discount: 20,
              durationMinutes: 60,
              distance: '2.3 km',
              rating: 4.9,
              reviews: 142,
            ),
            HomeCatalogItem(
              id: 9992,
              title: 'Diseño de uñas gel',
              venue: 'Luna Studio',
              category: 'Uñas',
              price: 18,
              originalPrice: 24,
              discount: 25,
              durationMinutes: 60,
              distance: '0.8 km',
              rating: 4.9,
              reviews: 128,
            ),
          ]
        : offers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(child: _SectionTitle('Ofertas relámpago')),
                _CountdownPill(remaining: _flashRemaining),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Cupos limitados por tiempo',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 186,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: displayOffers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _FlashOfferCard(
                item: displayOffers[index],
                onTap: () => _openItem(displayOffers[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommended() {
    final recommendations = _items.take(6).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Recomendado para ti', trailing: 'Ver todo'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Basado en tus preferencias y ubicación',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 224,
            child: recommendations.isEmpty
                ? const _HorizontalLoading()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: recommendations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) {
                      final item = recommendations[index];
                      return _RecommendedCard(
                        item: item,
                        saved: _savedIds.contains(item.id),
                        onTap: () => _openItem(item),
                        onSave: () => _toggleSaved(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularPlaces() {
    final places = <String, HomeCatalogItem>{};
    for (final item in _items) {
      places.putIfAbsent(item.venue, () => item);
    }
    final values = places.values.take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Establecimientos populares', trailing: 'Ver todos'),
          const SizedBox(height: 10),
          SizedBox(
            height: 270,
            child: values.isEmpty
                ? const _HorizontalLoading()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => _PopularPlaceCard(
                      item: values[index],
                      onTap: () => _openItem(values[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyPopular() {
    final weekly = _items.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            'Servicios populares de la semana',
            trailing: 'Ranking',
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: _cardDecoration(),
              child: Column(
                children: weekly.isEmpty
                    ? const [_LoadingBlock(compact: true)]
                    : List.generate(
                        weekly.length,
                        (index) => _WeeklyServiceRow(
                          rank: index + 1,
                          item: weekly[index],
                          onTap: () => _openItem(weekly[index]),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewOfDay() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 22),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF2FB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE3F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  color: AppTheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Reseña del día', style: _SectionTitleStyle()),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: AppTheme.accent,
                        size: 13,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Verificada',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 17),
                Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 17),
                Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 17),
                Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 17),
                Icon(Icons.star_rounded, color: Color(0xFFF5A623), size: 17),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '“Llegué, reservé y me atendieron a la hora exacta. La experiencia fue muy tranquila.”',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 11),
            GestureDetector(
              onTap: () => _showToast('Abriendo el perfil de Luna Studio.'),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Ana R. · Luna Studio',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.primary,
                    size: 17,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoyaltyBanner() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Container(
          height: 142,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C3654), Color(0xFF1FA8B8)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: -28,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              AnimatedBuilder(
                animation: _shineController,
                builder: (_, __) => Positioned(
                  left: -80 + (_shineController.value * 420),
                  top: -30,
                  bottom: -30,
                  width: 62,
                  child: Transform.rotate(
                    angle: -0.25,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BENEFICIO DE BIENVENIDA',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '20% de descuento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Actívalo en tu primera reserva.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 32,
                            child: FilledButton(
                              onPressed: () => _showToast(
                                'Beneficio listo para usar en tu próxima reserva.',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              child: const Text(
                                'Activar beneficio',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '✦',
                      style: TextStyle(fontSize: 44, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    const steps = [
      _HowStep(
        '1',
        'Elige',
        'Descubre un servicio cerca de ti.',
        Icons.search_rounded,
      ),
      _HowStep(
        '2',
        'Reserva',
        'Selecciona el horario que prefieras.',
        Icons.event_available_outlined,
      ),
      _HowStep(
        '3',
        'Llega sin filas',
        'Te atendemos cuando corresponde.',
        Icons.directions_walk_outlined,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Cómo funciona', trailing: null),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: steps
                .map((step) => Expanded(child: _HowStepCard(step: step)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text('Más servicios para ti', style: _SectionTitleStyle()),
          ),
          if (_isMock)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Vista previa',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: AppTheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            const Text(
              'No encontramos resultados',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 5),
            const Text(
              'Prueba otra categoría o cambia la búsqueda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _category = 'Todas';
                });
                _loadPage(reset: true);
              },
              child: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 112),
      child: Column(
        children: [
          const Divider(color: AppTheme.border),
          const SizedBox(height: 13),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '¿Tienes un negocio?',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    _showToast('Te ayudaremos a publicar tu negocio.'),
                icon: const Icon(Icons.storefront_outlined, size: 16),
                label: const Text('Publica tu negocio'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Explora con confianza · Reserva cuando quieras',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const _SectionTitleStyle())),
          if (trailing != null)
            TextButton(
              onPressed: () => _showToast('Desliza para ver más opciones.'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                trailing,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppTheme.border),
    boxShadow: const [
      BoxShadow(color: Color(0x0D2B3A67), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );
}

class _StatusAvatar extends StatelessWidget {
  final String initial;
  const _StatusAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent,
          ),
          child: CircleAvatar(
            backgroundColor: const Color(0xFFBFD7E9),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3E4E80), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool live;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    this.icon,
    this.selected = false,
    this.live = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = live ? AppTheme.success : AppTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.10)
                : (live
                      ? AppTheme.success.withValues(alpha: 0.08)
                      : AppTheme.surface),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : (live
                        ? AppTheme.success.withValues(alpha: 0.22)
                        : AppTheme.border),
            ),
          ),
          child: Row(
            children: [
              if (live)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                  ),
                ),
              if (icon != null)
                Icon(
                  icon,
                  size: 13,
                  color: selected ? AppTheme.primary : foreground,
                ),
              if (icon != null) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primary : foreground,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final _Collection collection;
  final VoidCallback onTap;
  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: collection.colors,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 10,
              top: 6,
              child: Text(
                collection.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.44),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 7,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    collection.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SponsoredCard extends StatelessWidget {
  final _Sponsored sponsored;
  final VoidCallback onTap;
  const _SponsoredCard({required this.sponsored, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: sponsored.colors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 18,
              top: 14,
              child: Icon(
                sponsored.icon,
                color: Colors.white.withValues(alpha: 0.25),
                size: 86,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.17),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PATROCINADO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Verificado',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sponsored.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sponsored.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Ver local  →',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownPill extends StatelessWidget {
  final Duration remaining;
  const _CountdownPill({required this.remaining});

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    final text =
        '${two(remaining.inHours)}:${two(remaining.inMinutes.remainder(60))}:${two(remaining.inSeconds.remainder(60))}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: AppTheme.error, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.error,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlashOfferCard extends StatelessWidget {
  final HomeCatalogItem item;
  final VoidCallback onTap;
  const _FlashOfferCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final original = item.originalPrice ?? (item.price * 1.2);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 194,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '-${item.discount == 0 ? 20 : item.discount}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.bolt_rounded,
                  color: AppTheme.warning,
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              item.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  item.priceLabel,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${original.toStringAsFixed(0)} ${item.currency}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: const LinearProgressIndicator(
                      value: 0.72,
                      minHeight: 5,
                      backgroundColor: Color(0xFFEFF1F5),
                      color: AppTheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  '3 cupos',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final HomeCatalogItem item;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;
  const _RecommendedCard({
    required this.item,
    required this.saved,
    required this.onTap,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 188,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  _MediaPreview(item: item, radius: 13),
                  Positioned(
                    top: 7,
                    left: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PARA TI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: onSave,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.90),
                      ),
                      icon: Icon(
                        saved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 17,
                        color: saved ? AppTheme.error : AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppTheme.warning,
                  size: 14,
                ),
                const SizedBox(width: 3),
                Text(
                  item.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  item.priceLabel,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularPlaceCard extends StatelessWidget {
  final HomeCatalogItem item;
  final VoidCallback onTap;

  const _PopularPlaceCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = item.venue.trim().isEmpty ? '?' : item.venue.trim()[0];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 285,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 126,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _MediaPreview(item: item, radius: 0),
                  Positioned(
                    left: 12,
                    bottom: -20,
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        backgroundColor: const Color(0xFFDDE8F0),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 11,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: AppTheme.accent,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            item.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 24, 13, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppTheme.accent,
                        size: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.category} · ${item.distance}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: item.tags
                        .take(3)
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Ver servicios',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyServiceRow extends StatelessWidget {
  final int rank;
  final HomeCatalogItem item;
  final VoidCallback onTap;

  const _WeeklyServiceRow({
    required this.rank,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank == 1 ? const Color(0xFFFFF2D6) : AppTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank == 1 ? AppTheme.warning : AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              height: 46,
              child: _MediaPreview(item: item, radius: 9),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.durationMinutes} min · ${item.distance}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.circle,
                        color: AppTheme.success,
                        size: 7,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.availableNow ? 'Disponible ahora' : 'Próximamente',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedServiceCard extends StatelessWidget {
  final HomeCatalogItem item;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  const _FeedServiceCard({
    required this.item,
    required this.saved,
    required this.onTap,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: _MediaPreview(item: item, radius: 12),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onSave,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 26,
                            height: 26,
                          ),
                          icon: Icon(
                            saved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: saved ? AppTheme.error : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      item.venue,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppTheme.warning,
                          size: 14,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          item.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${item.durationMinutes} min · ${item.distance}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item.priceLabel,
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final HomeCatalogItem item;
  final double radius;
  const _MediaPreview({required this.item, required this.radius});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientFor(item.category),
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          _emojiFor(item.category),
          style: const TextStyle(fontSize: 31),
        ),
      ),
    );
    if (item.imageUrl == null || item.imageUrl!.trim().isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: NetImage(
        url: item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: () => fallback,
      ),
    );
  }

  static List<Color> _gradientFor(String category) => switch (category) {
    'Uñas' => const [Color(0xFF8D667F), Color(0xFFE5ACBF)],
    'Cejas & Pestañas' => const [Color(0xFF63758D), Color(0xFFA8BED2)],
    'Transporte' => const [Color(0xFF385582), Color(0xFF7BA6D3)],
    'Salud' => const [Color(0xFF2D7573), Color(0xFF71BCB4)],
    'Hogar' => const [Color(0xFF8A7355), Color(0xFFCBB58B)],
    'Mascotas' => const [Color(0xFF8D6C47), Color(0xFFD7AC70)],
    _ => const [Color(0xFF70537C), Color(0xFFC69CC4)],
  };

  static String _emojiFor(String category) => switch (category) {
    'Uñas' => '💅',
    'Cejas & Pestañas' => '✨',
    'Transporte' => '🚌',
    'Salud' => '🩺',
    'Hogar' => '⌂',
    'Mascotas' => '🐾',
    _ => '✦',
  };
}

class _HowStepCard extends StatelessWidget {
  final _HowStep step;
  const _HowStepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, color: AppTheme.primary, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  final bool compact;
  const _LoadingBlock({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 18 : 24,
      ),
      child: Center(
        child: compact
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Column(
                children: [
                  SizedBox(
                    height: 15,
                    width: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Cargando servicios…',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LoadingMoreBlock extends StatelessWidget {
  const _LoadingMoreBlock();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(18),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _HorizontalLoading extends StatelessWidget {
  const _HorizontalLoading();
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _SectionTitleStyle extends TextStyle {
  const _SectionTitleStyle()
    : super(
        color: AppTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const _SectionTitleStyle());
}

class _HomeCategory {
  final String name;
  final String emoji;
  final IconData icon;
  const _HomeCategory(this.name, this.emoji, this.icon);
}

class _Collection {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> colors;
  const _Collection(this.title, this.subtitle, this.emoji, this.colors);
}

class _Sponsored {
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  const _Sponsored(this.name, this.subtitle, this.icon, this.colors);
}

class _HowStep {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  const _HowStep(this.number, this.title, this.description, this.icon);
}
