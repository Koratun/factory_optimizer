import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile.dart';
import 'item_recipe.dart';

class ProductionLine extends StatefulWidget {
  final ItemRecipe rootRecipe;

  const ProductionLine(this.rootRecipe, {super.key});

  @override
  State<ProductionLine> createState() => _ProductionLineState();
}

class _RecipeNode {
  final ItemRecipe recipe;
  final int depth;
  bool selected = false;

  _RecipeNode(this.recipe, this.depth);
}

enum OptimizationStrategy {
  power,
  rawResources,
  resources,
}

class _ProductionLineState extends State<ProductionLine> {
  late final GameModel game;
  final Map<_RecipeNode, _RecipeNode> edges = {};
  final List<_RecipeNode> nodes = [];
  final List<_RecipeNode> leastResourceNodes = [];
  final List<_RecipeNode> leastRawResourceNodes = [];
  final List<_RecipeNode> leastPowerNodes = [];
  int depth = 0;
  int greatestDepth = 0;
  OptimizationStrategy strategy = OptimizationStrategy.rawResources;

  @override
  void initState() {
    super.initState();
    game = Provider.of<GameModel>(context, listen: false);
    nodes.add(_RecipeNode(widget.rootRecipe, 0));
    nodes.first.selected = true;
    leastResourceNodes.add(nodes.first);
    leastRawResourceNodes.add(nodes.first);
    leastPowerNodes.add(nodes.first);
    processRecipe(nodes.first);
    selectProductionLine(nodes.first);
  }

  _RecipeNode processRecipe(_RecipeNode node) {
    depth += 1;
    for (var i in node.recipe.input) {
      var subRecipes = game.recipes[i.name];
      if (subRecipes != null) {
        var newNodes =
            subRecipes.map((e) => processRecipe(_RecipeNode(e, depth)));
        nodes.addAll(newNodes);
        edges.addEntries(newNodes.map((e) => MapEntry(e, node)));
        if (depth > greatestDepth) {
          greatestDepth = depth;
        }
      }
    }
    depth -= 1;
    return node;
  }

  Iterable<_RecipeNode> downstreamNodes(_RecipeNode node) =>
      edges.entries.where((e) => e.value == node).map((e) => e.key);

  Iterable<_RecipeNode> getInternalSelectedNodes() =>
      nodes.where((e) => e.selected);

  bool validProductionLine(_RecipeNode node) {
    for (var i in node.recipe.input) {
      if (!game.recipes.containsKey(i.name)) {
        continue;
      }
      bool found = false;
      for (var n in downstreamNodes(node)) {
        if (n.selected && n.recipe.output.any((e) => e.name == i.name)) {
          found = true;
          if (!validProductionLine(n)) {
            return false;
          }
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  bool gathering = true;

  void selectProductionLine(_RecipeNode node) {
    var dnodes = downstreamNodes(node);
    for (var n in dnodes) {
      List<String> satisfiedInputs = [];
      for (var i in node.recipe.input) {
        if (satisfiedInputs.contains(i.name)) {
          continue;
        }
        if (n.recipe.output.any((e) => i.name == e.name)) {
          if (gathering) {
            n.selected = true;
            satisfiedInputs.add(i.name);
            leastPowerNodes.add(n);
            leastRawResourceNodes.add(n);
            selectProductionLine(n);
            if (validProductionLine(nodes.first)) {
              gathering = false;
            }
          } else {
            dnodes
                .firstWhere((e) =>
                    e.selected &&
                    e.recipe.output.any(
                      (o) => o.name == i.name,
                    ))
                .selected = false;
            n.selected = true;
            selectProductionLine(n);
            if (validProductionLine(nodes.first)) {}
          }
        }
      }
    }
  }

  double totalPower() {}

  double totalRawResources() {}

  // Computation methods /\

  // Displaying methods \/
  Iterable<ItemRecipe> nodesAtDepth(int d) =>
      leastRawResourceNodes.where((e) => e.depth == d).map((e) => e.recipe);

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
