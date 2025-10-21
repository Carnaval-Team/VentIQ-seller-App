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
    this.scrollSpeed = 50.0, // pixels per second
    this.pauseDuration = const Duration(seconds: 1),
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateScrolling();
    });
  }

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

    _containerWidth = renderBox.size.width;

    // Calculate text width
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    _textWidth = textPainter.size.width;

    setState(() {
      _needsScrolling = _textWidth > _containerWidth;
    });

    if (_needsScrolling) {
      _startScrolling();
    }
  }

  void _startScrolling() {
    if (!mounted || !_needsScrolling) return;

    final double scrollDistance = _textWidth - _containerWidth + 50; // Extra padding
    final Duration scrollDuration = Duration(
      milliseconds: (scrollDistance / widget.scrollSpeed * 1000).round(),
    );

    _controller.duration = scrollDuration;
    _animation = Tween<double>(
      begin: 0.0,
      end: scrollDistance,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

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
