import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile.dart';
import 'item_recipe.dart';

class FactoryOverview extends StatefulWidget {
  final List<ItemRecipe> rootRecipes;
  final ItemRecipe? selectedRecipe;

  const FactoryOverview(this.rootRecipes, {this.selectedRecipe, super.key});

  @override
  State<FactoryOverview> createState() => _FactoryOverviewState();
}

class _RecipeNode {
  final ItemRecipe recipe;
  final int depth;
  bool selected = false;
  late final _OptimizerInfo myCost;

  _RecipeNode(this.recipe, this.depth) {
    myCost = _OptimizerInfo.self(0, 0, 0, this);
  }
}

class _RecipeEdge {
  final _RecipeNode incoming;
  final _RecipeNode outgoing;
  final _RecipeEdge? upstreamEdge;
  late final String connectingName;
  double recipeMultiplier = 1;

  _RecipeEdge(this.incoming, this.outgoing, this.upstreamEdge) {
    for (var o in incoming.recipe.output) {
      for (var i in outgoing.recipe.input) {
        if (o.name == i.name) {
          connectingName = o.name;
          double opRate = outgoing.recipe.operationalRate ?? 1;
          if (upstreamEdge != null) {
            opRate *= upstreamEdge!.recipeMultiplier;
          }
          recipeMultiplier = o.amount / i.amount * opRate;
        }
      }
    }
  }
}

enum OptimizationStrategy {
  power,
  rawResources,
  resources,
}

class _OptimizerInfo {
  double power;
  _RecipeNode powerNode;
  double resources;
  _RecipeNode resourceNode;
  double rawResources;
  _RecipeNode rawResourceNode;

  _OptimizerInfo(
    this.power,
    this.powerNode,
    this.resources,
    this.resourceNode,
    this.rawResources,
    this.rawResourceNode,
  );

  _OptimizerInfo.self(
    this.power,
    this.resources,
    this.rawResources,
    _RecipeNode self,
  )   : powerNode = self,
        resourceNode = self,
        rawResourceNode = self;

  _OptimizerInfo operator +(_OptimizerInfo other) {
    power += other.power;
    resources += other.resources;
    rawResources += other.rawResources;
    return this;
  }

  void setLower(_OptimizerInfo o) {
    if (o.power < power) {
      setPower(o);
    }
    if (o.resources < resources) {
      setResources(o);
    }
    if (o.rawResources < rawResources) {
      setRawResources(o);
    }
  }

  void setPower(_OptimizerInfo o) {
    power = o.power;
    powerNode = o.powerNode;
  }

  void setResources(_OptimizerInfo o) {
    resources = o.resources;
    resourceNode = o.resourceNode;
  }

  void setRawResources(_OptimizerInfo o) {
    rawResources = o.rawResources;
    rawResourceNode = o.rawResourceNode;
  }
}

class _ProductionGraph {
  final GameModel game;

  late final _OptimizerInfo totalCost;
  final List<_RecipeEdge> edges = [];
  final List<_RecipeNode> nodes = [];
  final List<_RecipeNode> leastResourceNodes = [];
  final List<_RecipeNode> leastRawResourceNodes = [];
  final List<_RecipeNode> leastPowerNodes = [];

  int depth = 0;
  int greatestDepth = 0;

  _ProductionGraph(this.game, rootRecipe) {
    nodes.add(_RecipeNode(rootRecipe, 0));
    leastResourceNodes.add(nodes.first);
    leastRawResourceNodes.add(nodes.first);
    leastPowerNodes.add(nodes.first);
    processRecipe(nodes.first);
    totalCost = scanGraph(nodes.first);
  }

  void processRecipe(_RecipeNode node, {_RecipeEdge? upstreamEdge}) {
    depth += 1;
    for (var i in node.recipe.input) {
      var subRecipes = game.recipes[i.name];
      if (subRecipes != null) {
        var newNodes = subRecipes.map((r) => _RecipeNode(r, depth));
        nodes.addAll(newNodes);
        var newEdges = newNodes.map((n) => _RecipeEdge(n, node, upstreamEdge));
        edges.addAll(newEdges);
        for (var e in newEdges) {
          processRecipe(e.incoming, upstreamEdge: e);
        }
        if (depth > greatestDepth) {
          greatestDepth = depth;
        }
      }
    }
    depth -= 1;
  }

  _OptimizerInfo scanGraph(_RecipeNode node) {
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    int buildingsRequired = upEdge?.recipeMultiplier.ceil() ?? 1;
    node.myCost.power +=
        game.buildingAssets[node.recipe.building!]!.cost * buildingsRequired;
    for (var i in node.recipe.input) {
      _OptimizerInfo? inputCost;
      for (var e in edges.where((e) =>
          e.outgoing == node &&
          e.incoming.recipe.output.any((o) => o.name == i.name))) {
        var cost = scanGraph(e.incoming);
        if (inputCost == null) {
          inputCost = cost;
        } else {
          inputCost.setLower(cost);
        }
      }
      if (inputCost != null) {
        leastPowerNodes.add(inputCost.powerNode);
        leastResourceNodes.add(inputCost.resourceNode);
        leastRawResourceNodes.add(inputCost.rawResourceNode);
        node.myCost += inputCost;
      } else {
        node.myCost.rawResources += i.amount * (upEdge?.recipeMultiplier ?? 1);
      }
      node.myCost.resources += i.amount * (upEdge?.recipeMultiplier ?? 1);
    }
    return node.myCost;
  }
}

class _FactoryOverviewState extends State<FactoryOverview> {
  late final GameModel game;

  OptimizationStrategy strategy = OptimizationStrategy.rawResources;
  late final List<_ProductionGraph> productionGraphs;
  _ProductionGraph? graphToDisplay;

  @override
  void initState() {
    super.initState();
    game = Provider.of<GameModel>(context, listen: false);
    productionGraphs =
        widget.rootRecipes.map((r) => _ProductionGraph(game, r)).toList();
    selectForStrategy();
  }

  void selectForStrategy() {
    if (widget.selectedRecipe != null) {
      graphToDisplay = productionGraphs
          .firstWhere((p) => p.nodes.first.recipe == widget.selectedRecipe);
    }
    switch (strategy) {
      case OptimizationStrategy.rawResources:
        graphToDisplay ??= productionGraphs.reduce((p, p2) =>
            p.totalCost.rawResources <= p2.totalCost.rawResources ? p : p2);
        selectList(graphToDisplay!.leastRawResourceNodes);
        break;
      case OptimizationStrategy.resources:
        graphToDisplay ??= productionGraphs.reduce((p, p2) =>
            p.totalCost.resources <= p2.totalCost.resources ? p : p2);
        selectList(graphToDisplay!.leastResourceNodes);
        break;
      case OptimizationStrategy.power:
        graphToDisplay ??= productionGraphs.reduce(
            (p, p2) => p.totalCost.power <= p2.totalCost.power ? p : p2);
        selectList(graphToDisplay!.leastPowerNodes);
        break;
      default:
    }
  }

  void selectList(List<_RecipeNode> selectedNodes) {
    for (var n in graphToDisplay!.nodes) {
      if (selectedNodes.contains(n)) {
        n.selected = true;
      } else {
        n.selected = false;
      }
    }
  }

  // Computation methods  /\
  //                      ||
  // Displaying methods   \/

  Iterable<ItemRecipe> nodesAtDepth(int d) => graphToDisplay!.nodes
      .where((e) => e.selected && e.depth == d)
      .map((e) => e.recipe);

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
