import 'package:flutter/material.dart';

import 'string_utils.dart';

class DeltaText extends StatefulWidget {
  final double n;
  final String suffix;
  final TextStyle style;
  final bool inverted;

  const DeltaText(
    this.n,
    this.suffix,
    this.style, {
    this.inverted = false,
    super.key,
  });

  @override
  State<DeltaText> createState() => _DeltaTextState();
}

class _DeltaTextState extends State<DeltaText> {
  Color color = Colors.white;

  late final Color better = widget.inverted ? Colors.red : Colors.green;
  late final Color worse = widget.inverted ? Colors.green : Colors.red;

  @override
  void didUpdateWidget(covariant DeltaText oldWidget) {
    if (widget.n > oldWidget.n) {
      color = worse;
    } else if (widget.n < oldWidget.n) {
      color = better;
    } else {
      color = Colors.white;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.n.pretty + widget.suffix,
      style: widget.style.copyWith(color: color),
      textWidthBasis: TextWidthBasis.longestLine,
    );
  }
}
