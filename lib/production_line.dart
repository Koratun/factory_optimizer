import 'package:flutter/material.dart';

import 'item_recipe.dart';

class ProductionLine extends StatefulWidget {
  final ItemRecipe rootRecipe;

  const ProductionLine(this.rootRecipe, {super.key});

  @override
  State<ProductionLine> createState() => _ProductionLineState();
}

class _ProductionLineState extends State<ProductionLine> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
