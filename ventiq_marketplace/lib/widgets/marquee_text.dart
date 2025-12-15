import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double scrollSpeed;
  final Duration pauseDuration;
  final int maxLines;

  const MarqueeText({
    Key? key,
    required this.text,
    this.style,
    this.scrollSpeed =
        40.0, // pixels per second - Reducido para mejor rendimiento
    this.pauseDuration = const Duration(
      seconds: 2,
    ), // Pausa más larga para menos animaciones
    this.maxLines = 1,
  }) : super(key: key);

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late ScrollController _scrollController;
  bool _needsScrolling = false;
  // ignore: prefer_final_fields
  bool _isStaticTextEnabled =
      false; // Default to false as service is not available
  double _textWidth = 0;
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(
      duration: Duration.zero, // Will be calculated based on text length
      vsync: this,
    );

    // _loadStaticTextSetting(); // Removed as service is not available

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateScrolling();
    });
  }

  /*
  Future<void> _loadStaticTextSetting() async {
    final isStaticEnabled = await _userPreferencesService.isStaticTextEnabled();
    if (mounted) {
      setState(() {
        _isStaticTextEnabled = isStaticEnabled;
      });
    }
  }
  */

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _calculateScrolling() {
    if (!mounted) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final newContainerWidth = renderBox.size.width;

    // Solo recalcular si el ancho cambió significativamente (optimización)
    if ((newContainerWidth - _containerWidth).abs() < 5.0 &&
        _containerWidth > 0) {
      return;
    }

    _containerWidth = newContainerWidth;

    // Calculate text width
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    _textWidth = textPainter.size.width;

    setState(() {
      // Si los textos estáticos están habilitados, nunca hacer scroll
      _needsScrolling =
          !_isStaticTextEnabled &&
          (_textWidth > _containerWidth + 10); // Margen de tolerancia
    });

    if (_needsScrolling) {
      _startScrolling();
    }
  }

  void _startScrolling() {
    if (!mounted || !_needsScrolling) return;

    final double scrollDistance =
        _textWidth - _containerWidth + 30; // Menos padding para menos scroll
    final Duration scrollDuration = Duration(
      milliseconds: (scrollDistance / widget.scrollSpeed * 1000).round(),
    );

    _controller.duration = scrollDuration;
    _animation = Tween<double>(begin: 0.0, end: scrollDistance).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut, // Curva más suave para mejor rendimiento
      ),
    );

    _animation.addListener(() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_animation.value);
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(widget.pauseDuration, () {
          if (mounted) {
            _controller.reset();
            Future.delayed(widget.pauseDuration, () {
              if (mounted) {
                _controller.forward();
              }
            });
          }
        });
      }
    });

    // Start after initial pause
    Future.delayed(widget.pauseDuration, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_containerWidth != constraints.maxWidth) {
            _calculateScrolling();
          }
        });

        if (!_needsScrolling) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          );
        }

        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: widget.maxLines,
          ),
        );
      },
    );
  }
}
