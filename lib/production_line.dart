import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:boxy/boxy.dart';

import 'profile.dart';
import 'item_recipe.dart';
import 'string_utils.dart';

class FactoryOverview extends StatefulWidget {
  final List<ItemRecipe> rootRecipes;
  final ItemRecipe? selectedRecipe;
  final String item;

  const FactoryOverview(this.rootRecipes,
      {this.selectedRecipe, required this.item, super.key});

  @override
  State<FactoryOverview> createState() => _FactoryOverviewState();
}

class _RecipeNode {
  final ItemRecipe recipe;
  final int depth;
  ValueNotifier<bool> selected = ValueNotifier(false);
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

  bool recalculate = false;

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
        var newNodes = subRecipes.map((r) => _RecipeNode(r, depth)
          ..selected.addListener(() => recalculate = true));
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
      for (var e in edges
          .where((e) => e.outgoing == node && e.connectingName == i.name)) {
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

  Map<String, double> _rawResources = {};

  Map<String, double> get rawResources {
    if (recalculate) {
      recalculate = false;
      _rawResources = _getRawResourceCost();
      oneTimeResources = _getOneTimeResourceCost();
    }
    return _rawResources;
  }

  Map<String, double> _getRawResourceCost({_RecipeNode? node}) {
    node ??= nodes.first;
    Map<String, double> resources = {};
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    for (var i in node.recipe.input) {
      Map<String, double>? subResources;
      for (var e in edges
          .where((e) => e.outgoing == node && e.connectingName == i.name)) {
        subResources = _getRawResourceCost(node: e.incoming);
        for (var entry in subResources.entries) {
          resources[entry.key] = (resources[entry.key] ?? 0) + entry.value;
        }
      }
      if (subResources == null) {
        resources[i.name] = (resources[i.name] ?? 0) +
            (node.selected.value
                ? i.amount * (upEdge?.recipeMultiplier ?? 1)
                : 0);
      }
    }
    return resources;
  }

  Map<String, double> oneTimeResources = {};

  Map<String, double> _getOneTimeResourceCost({_RecipeNode? node}) {
    node ??= nodes.first;
    Map<String, double> resources = {};
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    int buildingsRequired = upEdge?.recipeMultiplier.ceil() ?? 1;
    for (var i in game.recipes[node.recipe.building]![0].input) {
      resources[i.name] = (resources[i.name] ?? 0) +
          (node.selected.value ? i.amount * buildingsRequired : 0);
    }
    for (var i in game.recipes[node.recipe.building]![0].input) {
      Map<String, double>? subResources;
      for (var e in edges
          .where((e) => e.outgoing == node && e.connectingName == i.name)) {
        subResources = _getRawResourceCost(node: e.incoming);
        for (var entry in subResources.entries) {
          resources[entry.key] = (resources[entry.key] ?? 0) + entry.value;
        }
      }
    }
    return resources;
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
        n.selected.value = true;
      } else {
        n.selected.value = false;
      }
    }
  }

  // Computation methods  /\
  //                      ||
  // Displaying methods   \/

  Iterable<ItemRecipe> nodesAtDepth(int d) => graphToDisplay!.nodes
      .where((e) => e.selected.value && e.depth == d)
      .map((e) => e.recipe);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.directional(
            textDirection: TextDirection.ltr,
            top: 0,
            height: 60,
            child: Text(
              "${widget.item} Factory",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall!
                  .copyWith(color: Colors.amber.shade300),
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 8,
            width: 92,
            bottom: 186,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.rawResources
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.rawResources;
                            selectForStrategy();
                          }),
                  child: const Text("Raw Resources"),
                ),
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.power
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.power;
                            selectForStrategy();
                          }),
                  child: const Text("Power"),
                ),
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.resources
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.resources;
                            selectForStrategy();
                          }),
                  child: const Text("Resources"),
                ),
              ],
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            top: 60,
            height: 200,
            start: 100,
            end: MediaQuery.of(context).size.width / 3,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Card(
                color: Colors.grey.shade900,
                elevation: 2,
                child: Column(
                  children: [
                    Text(
                      "Total Cost per Minute",
                      textAlign: TextAlign.center,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall!
                          .copyWith(color: Colors.white),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Card(
                        color: Colors.brown.shade900.withOpacity(0.1),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var e
                                  in graphToDisplay!.rawResources.entries)
                                itemAmount(e.key, e.value),
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 24, right: 8),
                                child: Text(
                                  "${graphToDisplay!.totalCost.power.pretty} MW",
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            bottom: 186,
            start: MediaQuery.of(context).size.width / 3 * 2,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Card(
                color: Colors.grey.shade900,
                elevation: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "One Time Resources",
                      textAlign: TextAlign.center,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall!
                          .copyWith(color: Colors.white),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Card(
                        color: Colors.lightBlueAccent.withOpacity(0.1),
                        elevation: 1,
                        child: GridView.count(
                          crossAxisCount: 1 +
                              sqrt(graphToDisplay!.oneTimeResources.length)
                                  .round(),
                          shrinkWrap: true,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          children: [
                            for (var e
                                in graphToDisplay!.oneTimeResources.entries)
                              itemAmount(e.key, e.value),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            top: 200,
            child: CustomBoxy(
              delegate: FactoryDelegate(),
              children: [
                for (var n
                    in graphToDisplay!.nodes.where((n) => n.selected.value))
                  BoxyId(id: n, child: factorySegment(n))
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget itemAmount(String name, double amount) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Tooltip(
              message: name,
              verticalOffset: 4,
              child: Image.file(game.itemAssets[name]!),
            ),
          ),
          Text(
            amount.pretty,
            style: Theme.of(context).textTheme.labelSmall,
            textWidthBasis: TextWidthBasis.longestLine,
          )
        ],
      ),
    );
  }

  Widget factorySegment(_RecipeNode n) {}
}

class FactoryDelegate extends BoxyDelegate {
  @override
  Size layout() {}
}
