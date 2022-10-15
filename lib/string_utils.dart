import 'dart:math' show pow;

extension StringUtil on String {
  String get basename => substring(lastIndexOf(RegExp(r'[\\/]')) + 1);
  String get trimExtension => substring(0, lastIndexOf('.'));
  String get extension => substring(lastIndexOf("."));
}

extension DoubleUtil on double {
  String get pretty => round() < this + 0.00001 && round() > this - 0.00001
      ? round().toString()
      : roundToPlace(4).toString();

  double roundToPlace(int p) =>
      (this * pow(10, p)).roundToDouble() / pow(10, p);
}
