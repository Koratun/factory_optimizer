extension StringUtil on String {
  String get basename => substring(lastIndexOf(RegExp(r'[\\/]')) + 1);
  String get trimExtension => substring(0, lastIndexOf('.'));
  String get extension => substring(lastIndexOf("."));
}
