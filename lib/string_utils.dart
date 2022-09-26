extension StringUtil on String {
  String get basename => substring(lastIndexOf(RegExp(r'[\\/]')) + 1);
  String get trimExtension => substring(0, lastIndexOf('.'));
  String get extension => substring(lastIndexOf("."));
}

extension DoubleUtil on double {
  String get pretty => toInt() == this ? toInt().toString() : toString();
}
