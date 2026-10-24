import 'package:flutter/material.dart';

class CheckoutAmountRow extends StatelessWidget {
  const CheckoutAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.labelStyle,
    this.amountStyle,
    this.isLoading = false,
  });

  final String label;
  final String amount;
  final TextStyle? labelStyle;
  final TextStyle? amountStyle;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(label, style: labelStyle);
    final amountContent =
        isLoading
            ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : Text(amount, style: amountStyle, textAlign: TextAlign.end);

    return LayoutBuilder(
      builder: (context, constraints) {
        final amountWidth =
            isLoading
                ? 16.0
                : _textWidth(
                  context,
                  amount,
                  amountStyle,
                  constraints.maxWidth,
                );
        final amountNeedsOwnLine = amountWidth > constraints.maxWidth * 0.55;

        if (amountNeedsOwnLine) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelText,
              const SizedBox(height: 2),
              Align(alignment: Alignment.centerRight, child: amountContent),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: labelText),
            const SizedBox(width: 8),
            amountContent,
          ],
        );
      },
    );
  }

  double _textWidth(
    BuildContext context,
    String text,
    TextStyle? style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.width;
  }
}
