import 'package:flutter/material.dart';

class ScrollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double maxWidth;
  final Duration scrollDuration;
  final Duration pauseDuration;

  const ScrollingText({
    Key? key,
    required this.text,
    this.style,
    required this.maxWidth,
    this.scrollDuration = const Duration(seconds: 3),
    this.pauseDuration = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late TextPainter _textPainter;
  bool _needsScrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.scrollDuration,
      vsync: this,
    );
    
    _setupTextPainter();
    _checkIfScrollingNeeded();
    
    if (_needsScrolling) {
      _startScrolling();
    }
  }

  void _setupTextPainter() {
    _textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: widget.style,
      ),
      textDirection: TextDirection.ltr,
    );
    _textPainter.layout();
  }

  void _checkIfScrollingNeeded() {
    _needsScrolling = _textPainter.width > widget.maxWidth;
    
    if (_needsScrolling) {
      // Calculate exact scroll distance to show the complete text
      final totalTextWidth = _textPainter.width;
      final availableWidth = widget.maxWidth;
      final scrollDistance = totalTextWidth - availableWidth + 50; // Extra padding to ensure full text visibility
      
      _animation = Tween<double>(
        begin: 0.0,
        end: -scrollDistance,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ));
      
      // Debug print to verify calculations
      print('Text: "${widget.text}"');
      print('Text width: $totalTextWidth, Available width: $availableWidth');
      print('Scroll distance: $scrollDistance');
    }
  }

  void _startScrolling() async {
    while (mounted && _needsScrolling) {
      await Future.delayed(widget.pauseDuration);
      if (mounted) {
        await _controller.forward();
      }
      await Future.delayed(widget.pauseDuration);
      if (mounted) {
        await _controller.reverse();
      }
    }
  }

  @override
  void didUpdateWidget(ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.maxWidth != widget.maxWidth) {
      _setupTextPainter();
      _checkIfScrollingNeeded();
      
      if (_needsScrolling && !_controller.isAnimating) {
        _startScrolling();
      } else if (!_needsScrolling) {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScrolling) {
      return SizedBox(
        width: widget.maxWidth,
        child: Text(
          widget.text,
          style: widget.style,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return SizedBox(
      width: widget.maxWidth,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: _textPainter.width + 50, // Ensure container is wide enough for full text
              child: Transform.translate(
                offset: Offset(_animation.value, 0),
                child: Text(
                  widget.text,
                  style: widget.style,
                  overflow: TextOverflow.visible,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
