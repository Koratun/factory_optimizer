import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:boxy/boxy.dart';

import 'profile.dart';
import 'item_recipe.dart';
import 'string_utils.dart';
import 'delta_text.dart';

class FactoryOverview extends StatefulWidget {
  final List<ItemRecipe> rootRecipes;
  final ItemRecipe? selectedRecipe;
  final String itemName;

  const FactoryOverview(this.rootRecipes,
      {this.selectedRecipe, required this.itemName, super.key});

  @override
  State<FactoryOverview> createState() => _FactoryOverviewState();
}

class _RecipeNode {
  final ItemRecipe recipe;
  final int depth;
  final _ProductionGraph graph;
  ValueNotifier<bool> selected = ValueNotifier(false);
  late _OptimizerInfo myCost;
  final List<String> prebuilt = [];

  _RecipeNode(this.recipe, this.depth, this.graph) {
    myCost = _OptimizerInfo.zero(this);
  }

  _RecipeEdge? get upEdge {
    try {
      return graph.edges.firstWhere((e) => e.incoming == this);
    } on StateError {
      return null;
    }
  }

  void adjustRate(ItemAmount item, double targetRate) {
    double old = 1;
    if (upEdge != null) {
      old = upEdge!.recipeMultiplier;
    } else {
      old = graph.rootMultiplier;
    }
    var currentRate = item.amount * (recipe.operationalRate ?? 1) * old;
    var multiplier = targetRate / currentRate;
    if (upEdge != null) {
      upEdge!.recipeMultiplier *= multiplier;
    } else {
      graph.rootMultiplier *= multiplier;
    }
    propogateRate(old);
  }

  void propogateRate(
    double oldMultiplier, {
    _RecipeNode? entryNode,
    bool? fromUpstream,
  }) {
    graph.recalculate = true;
    double? old;
    if (entryNode != null) {
      if (fromUpstream!) {
        upEdge!.recalculateMultiplier();
      } else {
        var change = entryNode.upEdge!.recipeMultiplier / oldMultiplier;
        if (upEdge != null) {
          old = upEdge!.recipeMultiplier;
          upEdge!.recipeMultiplier *= change;
        } else {
          graph.rootMultiplier *= change;
        }
      }
    }
    for (var n in graph.nodes
        .where((n) => n.upEdge?.outgoing == this && n != entryNode)) {
      n.propogateRate(old ?? oldMultiplier,
          entryNode: this, fromUpstream: true);
    }
    if (fromUpstream != true && upEdge != null) {
      upEdge!.outgoing.propogateRate(old ?? oldMultiplier,
          entryNode: this, fromUpstream: false);
    }
  }

  _RecipeNode addChild(ItemRecipe r) {
    var child = _RecipeNode(r, depth + 1, graph)
      ..selected.addListener(() => graph.recalculate = true);
    var edge = _RecipeEdge(child, this, upEdge, graph);
    graph.nodes.add(child);
    graph.edges.add(edge);
    graph.depth = depth;
    graph.processRecipe(child, upstreamEdge: edge);
    graph.depth = 0;
    graph.resetGraphData();
    return child;
  }

  List<_RecipeNode> get descendants {
    var descs = graph.nodes.where((n) => n.upEdge?.outgoing == this).toList();
    for (var n in graph.nodes.where((n) => n.upEdge?.outgoing == this)) {
      descs.addAll(n.descendants);
    }
    return descs;
  }

  void setInputPrebuilt(String name) {
    upEdge!.outgoing.prebuilt.add(name);
    for (var n in descendants) {
      n.selected.value = false;
    }
    selected.value = false;
  }

  void unsetInputPrebuilt(String name, OptimizationStrategy strat) {
    prebuilt.remove(name);
    selectChildrenWithStrategy(strat, selectItem: name);
  }

  void select() {
    var sibling = graph.nodes.firstWhere((n) =>
        n.selected.value &&
        n.upEdge?.outgoing == upEdge?.outgoing &&
        n.upEdge?.connectingName == upEdge?.connectingName);
    if (depth == 0) {
      graph.rootMultiplier = 1;
      propogateRate(1);
    }
    for (var n in sibling.descendants) {
      n.selected.value = false;
    }
    sibling.selected.value = false;
    selected.value = true;
  }

  void selectChildrenWithStrategy(
    OptimizationStrategy strat, {
    String? selectItem,
  }) {
    selected.value = true;
    for (var i in recipe.input) {
      if (prebuilt.contains(i.name) ||
          (selectItem != null && i.name != selectItem)) {
        continue;
      }
      _RecipeNode? bestNode;
      for (var e in graph.edges
          .where((e) => e.outgoing == this && e.connectingName == i.name)) {
        if (bestNode == null) {
          bestNode = e.incoming;
          continue;
        }
        switch (strat) {
          case OptimizationStrategy.power:
            if (e.incoming.myCost.power < bestNode.myCost.power) {
              bestNode = e.incoming;
            }
            break;
          case OptimizationStrategy.speed:
            if (e.incoming.myCost.speed > bestNode.myCost.speed) {
              bestNode = e.incoming;
            }
            break;
          case OptimizationStrategy.rawResources:
            if (e.incoming.myCost.rawResources < bestNode.myCost.rawResources) {
              bestNode = e.incoming;
            }
            break;
          case OptimizationStrategy.efficiency:
            if (e.incoming.myCost.efficiency > bestNode.myCost.efficiency) {
              bestNode = e.incoming;
            }
            break;
        }
      }
      if (bestNode != null) {
        bestNode.selectChildrenWithStrategy(strat);
      }
    }
  }
}

class _RecipeEdge {
  final _RecipeNode incoming;
  final _RecipeNode outgoing;
  final _RecipeEdge? upstreamEdge;
  final _ProductionGraph graph;
  late final String connectingName;
  double recipeMultiplier = 1;

  _RecipeEdge(this.incoming, this.outgoing, this.upstreamEdge, this.graph) {
    for (var o in incoming.recipe.output) {
      for (var i in outgoing.recipe.input) {
        if (o.name == i.name) {
          connectingName = o.name;
          double oOpRate = incoming.recipe.operationalRate ?? 1;
          double iOpRate = outgoing.recipe.operationalRate ?? 1;
          recipeMultiplier = (iOpRate * i.amount) / (oOpRate * o.amount);
          if (upstreamEdge != null) {
            recipeMultiplier *= upstreamEdge!.recipeMultiplier;
          } else {
            recipeMultiplier *= graph.rootMultiplier;
          }
        }
      }
    }
  }

  // Can only be called when going downstream
  void recalculateMultiplier() {
    var i = outgoing.recipe.input.firstWhere((e) => e.name == connectingName);
    var o = incoming.recipe.output.firstWhere((e) => e.name == connectingName);
    double oOpRate = incoming.recipe.operationalRate ?? 1;
    double iOpRate = outgoing.recipe.operationalRate ?? 1;
    recipeMultiplier = (iOpRate * i.amount) / (oOpRate * o.amount);
    if (upstreamEdge != null) {
      recipeMultiplier *= upstreamEdge!.recipeMultiplier;
    } else {
      recipeMultiplier *= graph.rootMultiplier;
    }
  }
}

enum OptimizationStrategy {
  power,
  rawResources,
  speed,
  efficiency,
}

class _OptimizerInfo {
  double power;
  _RecipeNode powerNode;
  double speed;
  _RecipeNode speedNode;
  double rawResources;
  _RecipeNode rawResourceNode;

  double aggregatedEfficiency;
  // Required for efficiency calculations
  int subNodes = 1;
  _RecipeNode efficientNode;

  _OptimizerInfo(
    this.power,
    this.powerNode,
    this.speed,
    this.speedNode,
    this.rawResources,
    this.rawResourceNode,
    this.aggregatedEfficiency,
    this.efficientNode,
  );

  _OptimizerInfo.zero(_RecipeNode self)
      : power = 0,
        speed = 0,
        rawResources = 0,
        aggregatedEfficiency = 1,
        powerNode = self,
        speedNode = self,
        rawResourceNode = self,
        efficientNode = self;

  _OptimizerInfo operator +(_OptimizerInfo other) {
    power += other.power;
    speed += other.speed;
    rawResources += other.rawResources;
    subNodes += other.subNodes;
    aggregatedEfficiency += other.aggregatedEfficiency;
    return this;
  }

  _OptimizerInfo copy() => _OptimizerInfo(power, powerNode, speed, speedNode,
      rawResources, rawResourceNode, aggregatedEfficiency, efficientNode);

  double get efficiency => aggregatedEfficiency / subNodes;

  void setBetter(_OptimizerInfo o) {
    if (o.power < power) {
      setPower(o);
    }
    if (o.speed > speed) {
      setSpeed(o);
    }
    if (o.rawResources < rawResources) {
      setRawResources(o);
    }
    if (o.efficiency > efficiency) {
      setEfficiency(o);
    }
  }

  void setPower(_OptimizerInfo o) {
    power = o.power;
    powerNode = o.powerNode;
  }

  void setSpeed(_OptimizerInfo o) {
    speed = o.speed;
    speedNode = o.speedNode;
  }

  void setRawResources(_OptimizerInfo o) {
    rawResources = o.rawResources;
    rawResourceNode = o.rawResourceNode;
  }

  void setEfficiency(_OptimizerInfo o) {
    aggregatedEfficiency = o.aggregatedEfficiency;
    subNodes = o.subNodes;
    efficientNode = o.efficientNode;
  }
}

class _ProductionGraph {
  final GameModel game;
  final String? rootName;

  late _OptimizerInfo optimizedData;
  final List<_RecipeEdge> edges = [];
  final List<_RecipeNode> nodes = [];
  final List<_RecipeNode> quickestNodes = [];
  final List<_RecipeNode> leastRawResourceNodes = [];
  final List<_RecipeNode> leastPowerNodes = [];
  final List<_RecipeNode> mostEfficientNodes = [];

  final List<_RecipeNode> rootNodes = [];
  double rootMultiplier = 1;

  int depth = 0;
  int greatestDepth = 0;

  bool recalculate = true;

  _ProductionGraph(this.game, List<ItemRecipe> rootRecipes, {this.rootName}) {
    nodes.addAll(rootRecipes.map((r) => _RecipeNode(r, 0, this)));
    rootNodes.addAll(nodes);
    for (var n in rootNodes) {
      processRecipe(n);
    }
    populateGraphData();
  }

  void processRecipe(_RecipeNode node, {_RecipeEdge? upstreamEdge}) {
    depth += 1;
    for (var i in node.recipe.input) {
      var subRecipes = game.recipes[i.name];
      if (subRecipes != null) {
        var newNodes = subRecipes
            .map((r) => _RecipeNode(r, depth, this)
              ..selected.addListener(() => recalculate = true))
            .toList();
        nodes.addAll(newNodes);
        var newEdges = newNodes
            .map((n) => _RecipeEdge(n, node, upstreamEdge, this))
            .toList();
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

  _RecipeNode addRoot(ItemRecipe r) {
    var child = _RecipeNode(r, 0, this)
      ..selected.addListener(() => recalculate = true);
    nodes.add(child);
    rootNodes.add(child);
    processRecipe(child);
    resetGraphData();
    return child;
  }

  void resetGraphData() {
    for (var n in nodes) {
      n.myCost = _OptimizerInfo.zero(n);
    }
    quickestNodes.clear();
    leastRawResourceNodes.clear();
    leastPowerNodes.clear();
    mostEfficientNodes.clear();
    populateGraphData();
  }

  void populateGraphData() {
    for (var n in rootNodes) {
      scanGraph(n);
    }

    optimizedData = rootNodes.first.myCost.copy();
    if (rootNodes.length != 1) {
      for (var n in rootNodes) {
        optimizedData.setBetter(n.myCost);
      }
    }
    seedStrategyData();
  }

  void seedStrategyData() {
    _seedStrategyData(
      optimizedData.rawResourceNode,
      OptimizationStrategy.rawResources,
    );
    _seedStrategyData(
      optimizedData.powerNode,
      OptimizationStrategy.power,
    );
    _seedStrategyData(
      optimizedData.speedNode,
      OptimizationStrategy.speed,
    );
    _seedStrategyData(
      optimizedData.efficientNode,
      OptimizationStrategy.efficiency,
    );
  }

  void _seedStrategyData(_RecipeNode node, OptimizationStrategy strat) {
    switch (strat) {
      case OptimizationStrategy.power:
        leastPowerNodes.add(node);
        for (var i in node.recipe.input) {
          if (node.prebuilt.contains(i.name)) {
            continue;
          }
          _RecipeNode? bestNode;
          for (var e in edges
              .where((e) => e.outgoing == node && e.connectingName == i.name)) {
            if (bestNode == null) {
              bestNode = e.incoming;
              continue;
            }
            if (e.incoming.myCost.power < bestNode.myCost.power) {
              bestNode = e.incoming;
            }
          }
          if (bestNode != null) {
            _seedStrategyData(bestNode, strat);
          }
        }
        break;
      case OptimizationStrategy.speed:
        quickestNodes.add(node);
        for (var i in node.recipe.input) {
          if (node.prebuilt.contains(i.name)) {
            continue;
          }
          _RecipeNode? bestNode;
          for (var e in edges
              .where((e) => e.outgoing == node && e.connectingName == i.name)) {
            if (bestNode == null) {
              bestNode = e.incoming;
              continue;
            }
            if (e.incoming.myCost.speed > bestNode.myCost.speed) {
              bestNode = e.incoming;
            }
          }
          if (bestNode != null) {
            _seedStrategyData(bestNode, strat);
          }
        }
        break;
      case OptimizationStrategy.rawResources:
        leastRawResourceNodes.add(node);
        for (var i in node.recipe.input) {
          if (node.prebuilt.contains(i.name)) {
            continue;
          }
          _RecipeNode? bestNode;
          for (var e in edges
              .where((e) => e.outgoing == node && e.connectingName == i.name)) {
            if (bestNode == null) {
              bestNode = e.incoming;
              continue;
            }
            if (e.incoming.myCost.rawResources < bestNode.myCost.rawResources) {
              bestNode = e.incoming;
            }
          }
          if (bestNode != null) {
            _seedStrategyData(bestNode, strat);
          }
        }
        break;
      case OptimizationStrategy.efficiency:
        mostEfficientNodes.add(node);
        for (var i in node.recipe.input) {
          if (node.prebuilt.contains(i.name)) {
            continue;
          }
          _RecipeNode? bestNode;
          for (var e in edges
              .where((e) => e.outgoing == node && e.connectingName == i.name)) {
            if (bestNode == null) {
              bestNode = e.incoming;
              continue;
            }
            if (e.incoming.myCost.efficiency > bestNode.myCost.efficiency) {
              bestNode = e.incoming;
            }
          }
          if (bestNode != null) {
            _seedStrategyData(bestNode, strat);
          }
        }
        break;
    }
  }

  _OptimizerInfo scanGraph(_RecipeNode node) {
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    node.myCost.aggregatedEfficiency =
        _calculateEfficiency(upEdge?.recipeMultiplier ?? rootMultiplier);
    int buildingsRequired =
        upEdge?.recipeMultiplier.ceil() ?? rootMultiplier.ceil();
    node.myCost.power =
        game.buildingAssets[node.recipe.building!]!.cost * buildingsRequired;
    for (var i in node.recipe.input) {
      _OptimizerInfo? inputCost;
      for (var e in edges
          .where((e) => e.outgoing == node && e.connectingName == i.name)) {
        var cost = scanGraph(e.incoming);
        if (inputCost == null) {
          inputCost = cost.copy();
        } else {
          inputCost.setBetter(cost);
        }
      }
      if (inputCost != null) {
        node.myCost += inputCost;
      } else {
        node.myCost.rawResources += i.amount *
            (node.recipe.operationalRate ?? 1) *
            (upEdge?.recipeMultiplier ?? rootMultiplier);
      }
    }
    if (rootNodes.contains(node)) {
      node.myCost.speed = node.recipe.rate;
    } else {
      node.myCost.speed = node.recipe.output
              .firstWhere((o) => o.name == upEdge?.connectingName)
              .amount *
          (node.recipe.operationalRate ?? 1);
    }
    return node.myCost;
  }

  double _calculateEfficiency(double recipeMultiplier) {
    if (recipeMultiplier.round() == 0) {
      return recipeMultiplier;
    } else {
      var v = recipeMultiplier.round() - recipeMultiplier;
      //Weight recipes not requiring overclocking to be more efficient
      if (v > 0) {
        v /= 3;
      }
      return 1 - v.abs();
    }
  }

  Map<String, double> _rawResources = {};

  Map<String, double> get rawResources {
    if (recalculate) {
      recalculate = false;
      _rawResources = _getRawResourceCost();
      powerConsumption = _getPowerConsumption();
      oneTimeResources = _getOneTimeResourceCost();
      graphEfficiency = _getGraphEfficiency();
    }
    return _rawResources;
  }

  double graphEfficiency = 1;

  double _getGraphEfficiency({_RecipeNode? node}) {
    node ??= rootNodes.firstWhere((n) => n.selected.value);
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    double efficiency =
        upEdge == null ? 1 : _calculateEfficiency(upEdge.recipeMultiplier);
    for (var i in node.recipe.input) {
      for (var e in edges.where((e) =>
          e.outgoing == node &&
          e.connectingName == i.name &&
          e.incoming.selected.value)) {
        efficiency += _getGraphEfficiency(node: e.incoming);
      }
    }
    if (upEdge == null) {
      // Total efficiency of all nodes / Perfect efficiency of all children
      // (sum(node_efficiency%)) / (number of nodes * 100% or * 1)
      return efficiency / nodes.where((e) => e.selected.value).length;
    }
    return efficiency;
  }

  Map<String, double> _getRawResourceCost({_RecipeNode? node}) {
    node ??= rootNodes.firstWhere((n) => n.selected.value);
    Map<String, double> resources = {};
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    for (var i in node.recipe.input) {
      Map<String, double>? subResources;
      for (var e in edges.where((e) =>
          e.outgoing == node &&
          e.connectingName == i.name &&
          e.incoming.selected.value)) {
        subResources = _getRawResourceCost(node: e.incoming);
        for (var entry in subResources.entries) {
          resources[entry.key] = (resources[entry.key] ?? 0) + entry.value;
        }
      }
      if (subResources == null) {
        resources[i.name] = (resources[i.name] ?? 0) +
            (node.selected.value
                ? i.amount *
                    (node.recipe.operationalRate ?? 1) *
                    (upEdge?.recipeMultiplier ?? rootMultiplier)
                : 0);
      }
    }
    return resources;
  }

  Map<String, double> oneTimeResources = {};

  Map<String, double> _getOneTimeResourceCost({_RecipeNode? node}) {
    node ??= rootNodes.firstWhere((n) => n.selected.value);
    Map<String, double> resources = {};
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    if (game.recipes.containsKey(node.recipe.building)) {
      int buildingsRequired =
          upEdge?.recipeMultiplier.ceil() ?? rootMultiplier.ceil();
      for (var i in game.recipes[node.recipe.building]![0].input) {
        resources[i.name] = (resources[i.name] ?? 0) +
            (node.selected.value ? i.amount * buildingsRequired : 0);
      }
    }
    for (var i in node.recipe.input) {
      Map<String, double>? subResources;
      for (var e in edges.where((e) =>
          e.outgoing == node &&
          e.connectingName == i.name &&
          e.incoming.selected.value)) {
        subResources = _getOneTimeResourceCost(node: e.incoming);
        for (var entry in subResources.entries) {
          resources[entry.key] = (resources[entry.key] ?? 0) + entry.value;
        }
      }
    }
    return resources;
  }

  double powerConsumption = 0;

  double _getPowerConsumption({_RecipeNode? node}) {
    node ??= rootNodes.firstWhere((n) => n.selected.value);
    double power = 0;
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    int buildingsRequired =
        upEdge?.recipeMultiplier.ceil() ?? rootMultiplier.ceil();
    power =
        game.buildingAssets[node.recipe.building!]!.cost * buildingsRequired;

    for (var i in node.recipe.input) {
      for (var e in edges.where((e) =>
          e.outgoing == node &&
          e.connectingName == i.name &&
          e.incoming.selected.value)) {
        power += _getPowerConsumption(node: e.incoming);
      }
    }
    return power;
  }
}

class _FactoryOverviewState extends State<FactoryOverview> {
  late final GameModel game;

  OptimizationStrategy strategy = OptimizationStrategy.rawResources;
  late final _ProductionGraph graph;

  @override
  void initState() {
    super.initState();
    game = Provider.of<GameModel>(context, listen: false);
    graph = _ProductionGraph(game, widget.rootRecipes,
        rootName: widget.itemName.contains("/") ? null : widget.itemName);
    selectForStrategy();
  }

  void selectForStrategy() {
    switch (strategy) {
      case OptimizationStrategy.rawResources:
        selectList(graph.leastRawResourceNodes);
        break;
      case OptimizationStrategy.speed:
        selectList(graph.quickestNodes);
        break;
      case OptimizationStrategy.power:
        selectList(graph.leastPowerNodes);
        break;
      case OptimizationStrategy.efficiency:
        selectList(graph.mostEfficientNodes);
        break;
      default:
    }
  }

  void selectList(List<_RecipeNode> selectedNodes) {
    for (var n in graph.nodes) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 200,
            child: InteractiveViewer(
                maxScale: 1.0,
                minScale: 0.1,
                clipBehavior: Clip.none,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width,
                    minHeight: MediaQuery.of(context).size.height - 200,
                  ),
                  child: Center(
                    child: _FactoryDelegate(
                      context,
                      game,
                      graph,
                      strategy,
                      _markDirty,
                      graph.rootNodes.firstWhere((n) => n.selected.value),
                      subDelegates: _getSubdelegates(
                          graph.rootNodes.firstWhere((n) => n.selected.value)),
                    ).boxy,
                  ),
                )),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 10,
            width: 64,
            top: 10,
            height: 64,
            child: Image.file(game.gameIcon),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 10,
            width: 64,
            top: 74,
            height: 64,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back),
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            top: 0,
            height: 60,
            start: MediaQuery.of(context).size.width * 0.5,
            end: 0,
            child: Text(
              "${widget.itemName} Factory",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall!
                  .copyWith(color: Colors.amber.shade300),
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 60,
            end: MediaQuery.of(context).size.width * 0.5,
            top: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.rawResources
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.rawResources;
                            selectForStrategy();
                          }),
                  style: strategy == OptimizationStrategy.rawResources
                      ? ButtonStyle(
                          backgroundColor: MaterialStatePropertyAll(
                              Colors.lightBlue.shade200))
                      : null,
                  child: const Text(
                    "Raw Resources",
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.power
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.power;
                            selectForStrategy();
                          }),
                  style: strategy == OptimizationStrategy.power
                      ? ButtonStyle(
                          backgroundColor: MaterialStatePropertyAll(
                              Colors.lightBlue.shade200))
                      : null,
                  child: const Text(
                    "Power",
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.speed
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.speed;
                            selectForStrategy();
                          }),
                  style: strategy == OptimizationStrategy.speed
                      ? ButtonStyle(
                          backgroundColor: MaterialStatePropertyAll(
                              Colors.lightBlue.shade200))
                      : null,
                  child: const Text(
                    "Speed",
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: strategy == OptimizationStrategy.efficiency
                      ? null
                      : () => setState(() {
                            strategy = OptimizationStrategy.efficiency;
                            selectForStrategy();
                          }),
                  style: strategy == OptimizationStrategy.efficiency
                      ? ButtonStyle(
                          backgroundColor: MaterialStatePropertyAll(
                              Colors.lightBlue.shade200))
                      : null,
                  child: const Text(
                    "Efficiency",
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            top: 60,
            height: 140,
            start: 100,
            end: MediaQuery.of(context).size.width * .5,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Card(
                color: Colors.grey.shade900,
                elevation: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      "Total Cost per Minute",
                      textAlign: TextAlign.center,
                      textWidthBasis: TextWidthBasis.longestLine,
                      style: Theme.of(context)
                          .textTheme
                          .subtitle2!
                          .copyWith(color: Colors.white),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Card(
                        color: Colors.brown.shade900.withOpacity(0.7),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var e in graph.rawResources.entries)
                                itemAmount(e.key, e.value),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: DeltaText(
                                  graph.powerConsumption * 60,
                                  " MW",
                                  Theme.of(context).textTheme.labelMedium!,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        "Efficiency",
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                    ),
                                    DeltaText(
                                      graph.graphEfficiency * 100,
                                      "%",
                                      Theme.of(context).textTheme.labelMedium!,
                                      inverted: true,
                                    ),
                                  ],
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
            top: 60,
            height: 140,
            start: MediaQuery.of(context).size.width * .5,
            end: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Card(
                color: Colors.grey.shade900,
                elevation: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        "One Time Resources",
                        textAlign: TextAlign.center,
                        textWidthBasis: TextWidthBasis.longestLine,
                        style: Theme.of(context)
                            .textTheme
                            .subtitle2!
                            .copyWith(color: Colors.white),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Card(
                        color: Colors.lightBlueAccent.withOpacity(0.3),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var e in graph.oneTimeResources.entries)
                                itemAmount(e.key, e.value),
                              if (graph.oneTimeResources.isEmpty)
                                const Icon(
                                  Icons.warning,
                                  size: 56,
                                  color: Colors.red,
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
        ],
      ),
    );
  }

  void _markDirty() => setState(() {});

  List<_FactoryDelegate> _getSubdelegates(_RecipeNode node) {
    return [
      for (var e in graph.edges
          .where((e) => e.outgoing == node && e.incoming.selected.value))
        _FactoryDelegate(
          context,
          game,
          graph,
          strategy,
          _markDirty,
          e.incoming,
          subDelegates: _getSubdelegates(e.incoming),
          upEdge: e,
        )
    ];
  }

  Widget itemAmount(String name, double amount) {
    return SizedBox(
      key: ValueKey(name),
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Tooltip(
              message: name,
              verticalOffset: 32,
              child: Image.file(game.itemAssets[name]!),
            ),
          ),
          DeltaText(
            amount,
            "",
            Theme.of(context).textTheme.labelSmall!,
          )
        ],
      ),
    );
  }
}

class _FactoryDelegate extends BoxyDelegate {
  final GameModel game;
  final _ProductionGraph graph;
  final OptimizationStrategy strat;
  final void Function() markDirty;
  final _RecipeNode node;
  final _RecipeEdge? upEdge;
  final List<_FactoryDelegate> subDelegates;
  late final Widget boxy;
  late final double outputHeight;
  final Map<String, double> outputLocations = {};

  _FactoryDelegate(
    BuildContext context,
    this.game,
    this.graph,
    this.strat,
    this.markDirty,
    this.node, {
    this.upEdge,
    required this.subDelegates,
  }) {
    var rawResources = node.recipe.input
        .where((i) =>
            !game.recipes.containsKey(i.name) || node.prebuilt.contains(i.name))
        .toList();

    boxy = CustomBoxy(
      key: UniqueKey(),
      delegate: this,
      children: [
        for (var d in subDelegates) BoxyId(id: d.node, child: d.boxy),
        BoxyId(id: node, child: factorySegment(context)),
        BoxyId(
          id: node.recipe.input,
          child: Column(
            mainAxisAlignment: rawResources.length <= 1
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              for (var i in rawResources)
                itemAmount(
                  context,
                  i,
                  node.recipe.operationalRate ?? 1,
                  upEdge?.recipeMultiplier ?? graph.rootMultiplier,
                  raw: true,
                ),
            ],
          ),
        ),
        for (var i in node.recipe.input.where((i) =>
            game.recipes.containsKey(i.name) &&
            !node.prebuilt.contains(i.name)))
          BoxyId(
            id: i.name,
            child: Container(
              width: 44,
              height: 4,
              color: Colors.lightBlueAccent,
            ),
          ),
        BoxyId(
          id: node.recipe,
          child: Container(
            width: 4,
            color: Colors.lightBlueAccent,
          ),
        ),
      ],
    );
  }

  Widget _changeRecipeDialog(BuildContext context, String item) {
    return Dialog(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.grey.shade900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r in game.recipes[item]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _miniRecipe(context, r, selected: node.recipe == r),
              ),
            SizedBox(
              width: 76 + 64 + 76,
              height: 76,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () async {
                  game.newRecipe = ItemRecipe(
                    [],
                    [ItemAmount(item, 1)],
                    0,
                    null,
                  );
                  bool success = null !=
                      await showDialog(
                        context: context,
                        builder: (context) => game.newRecipeDialog(
                          context,
                          item,
                        ),
                      );
                  if (success) {
                    _RecipeNode child;
                    if (node.upEdge == null) {
                      child = graph.addRoot(game.newRecipe!);
                    } else {
                      child = node.upEdge!.outgoing.addChild(game.newRecipe!);
                    }
                    child.select();
                    child.selectChildrenWithStrategy(strat);
                    game.newRecipe = null;
                    markDirty();
                  }
                },
                child: Container(
                  color: Colors.grey.shade800,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.handyman,
                          size: 45,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Add recipe",
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniRecipe(
    BuildContext context,
    ItemRecipe r, {
    bool selected = false,
  }) {
    return SizedBox(
      width: 76 + 64 + 76,
      height: 76,
      child: InkWell(
        mouseCursor: selected ? null : SystemMouseCursors.click,
        onTap: selected
            ? null
            : () {
                var sib = graph.nodes.firstWhere((n) =>
                    n.recipe == r &&
                    n.upEdge?.outgoing == node.upEdge?.outgoing &&
                    n.upEdge?.connectingName == node.upEdge?.connectingName);
                sib.select();
                sib.selectChildrenWithStrategy(strat);
                markDirty();
                Navigator.pop(context);
              },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.grey.shade800,
              ),
            ),
            for (var e in r.input.asMap().entries)
              Positioned.fromRect(
                rect: _miniItemPos(e.key, true),
                child: _miniItemAmount(context, e.value),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 76,
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${game.buildingAssets[r.building]!.cost.pretty} MW",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Tooltip(
                    message: r.building,
                    child: Image.file(
                      game.buildingAssets[r.building]!.file,
                      width: 45,
                      height: 45,
                    ),
                  ),
                  Text(
                    "${r.rate.roundToPlace(2).pretty}/min",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            for (var e in r.output.asMap().entries)
              Positioned.fromRect(
                rect: _miniItemPos(e.key, false),
                child: _miniItemAmount(context, e.value),
              ),
            if (selected)
              Positioned.fill(
                child: Container(color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }

  Rect _miniItemPos(int index, bool input) {
    var start = Offset(input ? 40 : 76 + 64 + 4, 40);
    if (index % 2 == 1) {
      start -= const Offset(0, 36);
    }
    // Not built for more than 4 ingredients
    if (index ~/ 2 == 1) {
      start += const Offset(36, 0) * (input ? -1 : 1);
    }
    return start & const Size(36, 36);
  }

  Widget _miniItemAmount(BuildContext context, ItemAmount i) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Positioned.fill(
          right: 4,
          bottom: 4,
          child: Tooltip(
            message: i.name,
            child: Image.file(game.itemAssets[i.name]!),
          ),
        ),
        Text(
          i.amount.toString(),
          textWidthBasis: TextWidthBasis.longestLine,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget itemAmount(
    BuildContext context,
    ItemAmount i,
    double opRate,
    double multiplier, {
    bool raw = false,
  }) {
    return SizedBox(
      width: raw ? 146 : 112,
      height: 112,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          if (raw)
            Positioned(
              width: 47,
              height: 4,
              top: 54,
              right: 0,
              child: Container(color: Colors.lightBlueAccent),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Tooltip(
              message: i.name,
              verticalOffset: -70,
              child: Card(
                elevation: 1,
                color: node.prebuilt.contains(i.name)
                    ? Colors.amber.withOpacity(0.5)
                    : game.recipes.containsKey(i.name)
                        ? Colors.greenAccent.withOpacity(0.4)
                        : Colors.brown.shade900.withOpacity(0.7),
                child: Image.file(game.itemAssets[i.name]!),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 0,
            right: raw ? 34 : 0,
            child: TextField(
              enabled: graph.rootNodes.contains(node) ||
                  node.prebuilt.contains(i.name) ||
                  recipeChangeable(i),
              scrollPadding: EdgeInsets.zero,
              textAlign: TextAlign.right,
              controller: TextEditingController(
                  text: (i.amount * opRate * multiplier).pretty),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
              ],
              decoration: InputDecoration(
                isCollapsed: true,
                filled: true,
                focusedBorder: InputBorder.none,
                focusColor: Colors.grey.shade700,
                suffixText: "/ min",
                suffixStyle: Theme.of(context).textTheme.labelMedium,
              ),
              style: Theme.of(context).textTheme.labelMedium,
              onSubmitted: (value) {
                node.adjustRate(i, double.parse(value));
                markDirty();
              },
            ),
          ),
          if ((i.name == upEdge?.connectingName &&
                  upEdge != null &&
                  game.recipes.containsKey(i.name)) ||
              node.prebuilt.contains(i.name))
            Positioned(
              top: 0,
              right: raw ? 34 : 0,
              width: 32,
              height: 32,
              child: IconButton(
                icon: Icon(
                  Icons.factory,
                  size: 32,
                  color: Colors.amber.shade700,
                ),
                tooltip: node.prebuilt.contains(i.name)
                    ? "Unset prebuilt portion"
                    : "Assume portion already built",
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (node.prebuilt.contains(i.name)) {
                    node.unsetInputPrebuilt(i.name, strat);
                  } else {
                    node.setInputPrebuilt(i.name);
                  }
                  markDirty();
                },
              ),
            ),
          if (recipeChangeable(i))
            Positioned(
              top: -4,
              left: -4,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: game.recipes.containsKey(i.name) &&
                        game.recipes[i.name]!.length > 1
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) =>
                              _changeRecipeDialog(context, i.name),
                        );
                      }
                    : () async {
                        game.newRecipe = ItemRecipe(
                          [],
                          [ItemAmount(i.name, 1)],
                          0,
                          null,
                        );
                        bool success = null !=
                            await showDialog(
                              context: context,
                              builder: (context) => game.newRecipeDialog(
                                context,
                                i.name,
                              ),
                            );
                        if (success) {
                          game.newRecipe = null;
                          markDirty();
                        }
                      },
                icon: Icon(
                  game.recipes.containsKey(i.name) &&
                          game.recipes[i.name]!.length > 1
                      ? Icons.change_circle
                      : Icons.add_circle,
                  size: 32,
                  color: Colors.green,
                ),
                tooltip: game.recipes.containsKey(i.name) &&
                        game.recipes[i.name]!.length > 1
                    ? "Change recipe"
                    : "Add recipe",
              ),
            ),
        ],
      ),
    );
  }

  bool recipeChangeable(ItemAmount i) =>
      ((upEdge == null && graph.rootNodes.length > 1) ||
          i.name == upEdge?.connectingName ||
          !game.recipes.containsKey(i.name)) &&
      !node.prebuilt.contains(i.name) &&
      !i.byproduct;

  Widget factorySegment(BuildContext context) {
    var outputs = [
      for (var o in node.recipe.output)
        itemAmount(
          context,
          o,
          node.recipe.operationalRate ?? 1,
          upEdge?.recipeMultiplier ?? graph.rootMultiplier,
        ),
    ];

    outputHeight = 128 + 112 * outputs.length + 128 * (outputs.length - 1);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 64,
          bottom: 64,
          right: 0,
          width: 112,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: outputs.expand((i) sync* {
              yield i;
              if (outputs.indexOf(i) != outputs.length - 1) {
                yield Container(
                  height: 128,
                  width: 4,
                  color: Colors.lightBlueAccent,
                );
              }
            }).toList(),
          ),
        ),
        Positioned(
          height: 4,
          width: outputs.length % 2 == 0 ? 135 : 90,
          right: outputs.length % 2 == 0 ? 56 : 100,
          child: Container(color: Colors.lightBlueAccent),
        ),
        Positioned(
          top: 0,
          left: 80,
          right: 56,
          height: 56,
          child: CustomPaint(painter: ExtendedCurvedCorner(true)),
        ),
        Positioned(
          bottom: 0,
          left: 80,
          right: 56,
          height: 56,
          child: CustomPaint(painter: ExtendedCurvedCorner(false)),
        ),
        Positioned(
          top: 6,
          right: 80,
          width: 100,
          child: TextField(
            scrollPadding: EdgeInsets.zero,
            textAlign: TextAlign.right,
            controller: TextEditingController(
                text:
                    (upEdge?.recipeMultiplier ?? graph.rootMultiplier).pretty),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
            ],
            decoration: InputDecoration(
              isCollapsed: true,
              filled: true,
              focusedBorder: InputBorder.none,
              focusColor: Colors.grey.shade700,
              suffixText: "x",
              suffixStyle: Theme.of(context).textTheme.labelLarge,
            ),
            style: Theme.of(context).textTheme.labelLarge,
            onSubmitted: (value) {
              double old = 1;
              if (upEdge != null) {
                old = upEdge!.recipeMultiplier;
                upEdge!.recipeMultiplier = double.parse(value);
              } else {
                graph.rootMultiplier = double.parse(value);
              }
              node.propogateRate(old);
              markDirty();
            },
          ),
        ),
        Positioned(
          height: 4,
          left: 146,
          width: 44,
          child: Container(color: Colors.lightBlueAccent),
        ),
        Positioned(
          height: 200,
          width: 128,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                node.recipe.building!,
                style: Theme.of(context).textTheme.labelLarge,
                textAlign: TextAlign.center,
                textWidthBasis: TextWidthBasis.longestLine,
              ),
              SizedBox(
                width: 128,
                height: 128,
                child: _wrapBuilding(
                  context,
                  Card(
                    elevation: 1,
                    color: game.recipes.containsKey(node.recipe.building!)
                        ? Colors.lightBlueAccent.withOpacity(0.3)
                        : Colors.redAccent.shade400.withOpacity(0.3),
                    child: Image.file(
                        game.buildingAssets[node.recipe.building!]!.file),
                  ),
                ),
              ),
              Text(
                "${game.buildingAssets[node.recipe.building!]!.cost.pretty} MW / building / sec\n"
                "${(game.buildingAssets[node.recipe.building!]!.cost * (upEdge?.recipeMultiplier.ceil() ?? graph.rootMultiplier.ceil())).pretty} MW / sec",
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
                textWidthBasis: TextWidthBasis.longestLine,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wrapBuilding(BuildContext context, Widget child) {
    if (game.recipes.containsKey(node.recipe.building!)) {
      return child;
    }
    return GestureDetector(
      onTap: () async {
        game.newRecipe = ItemRecipe(
          [],
          [ItemAmount(node.recipe.building!, 1)],
          0,
          null,
        );
        if (await showDialog(
              context: context,
              builder: (context) => game.newRecipeDialog(
                context,
                node.recipe.building!,
              ),
            ) !=
            null) {
          graph.recalculate = true;
          game.newRecipe = null;
          markDirty();
        }
      },
      child: Tooltip(
        message: "Add Recipe",
        verticalOffset: -70,
        child: child,
      ),
    );
  }

  late Offset segmentOffset;
  late Size segmentSize;

  @override
  Size layout() {
    double greatestWidth = 0;
    double inputHeight = 0;

    //Size children of this recipe
    var recipeChildren = Map.fromEntries(
      subDelegates.map((d) => MapEntry(d, getChild(d.node))),
    );
    for (var sub in recipeChildren.entries) {
      var size = sub.value.layout(constraints);
      inputHeight += size.height + 12;
      if (size.width - 96 > greatestWidth) {
        greatestWidth = size.width - 96;
      }
    }

    var rawResources = node.recipe.input
        .where((e) =>
            !game.recipes.containsKey(e.name) || node.prebuilt.contains(e.name))
        .toList();
    assert(rawResources.isNotEmpty || subDelegates.isNotEmpty);
    double rawResourceHeight = 0;
    if (rawResources.isNotEmpty) {
      rawResourceHeight =
          128 + rawResources.length * 112 + (rawResources.length - 1) * 128;
    }
    inputHeight += rawResourceHeight;

    Offset? firstLine;
    Offset lastLine = Offset.zero;

    //Estimate raw resource height
    for (var index in rawResources.asMap().keys) {
      var theoreticalOffset = Offset(greatestWidth + 100, 120 + (index * 240));
      firstLine ??= theoreticalOffset;
      lastLine = theoreticalOffset;
    }

    //Place recipe children and their lines
    double lastHeight = rawResourceHeight;
    for (var e in recipeChildren.entries) {
      e.value.position(Offset(
        greatestWidth + 114 - e.value.size.width,
        lastHeight == 0 ? 2 : lastHeight + 4,
      ));

      var inputPos = e.key.node.recipe.output
          .indexWhere((o) => o.name == e.key.upEdge!.connectingName);

      var childLine = getChild(e.key.upEdge!.connectingName);
      childLine.layout(constraints);
      if (inputPos == 0 && e.key.node.recipe.output.length == 1) {
        childLine.position(Offset(
          greatestWidth + 102,
          lastHeight + e.key.segmentOffset.dy + e.key.segmentSize.height / 2,
        ));
      } else {
        childLine.position(Offset(
            greatestWidth + 102,
            (lastHeight + e.key.segmentOffset.dy) +
                (e.key.segmentSize.height / 2 -
                    (e.key.node.recipe.output.length * 112 +
                            (e.key.node.recipe.output.length - 1) * 128) /
                        2 +
                    56) +
                240 * inputPos));
      }
      firstLine ??= childLine.offset;
      lastLine = childLine.offset;

      if (lastHeight == 0) {
        lastHeight = 2;
      }
      lastHeight += e.value.size.height + 12;
    }

    final segmentHeight =
        max(lastLine.dy - firstLine!.dy + 128 + 112, outputHeight);

    var tallLine = getChild(node.recipe);
    tallLine.layout(BoxConstraints.tightForFinite(
      width: 4,
      height: lastLine == firstLine ? 0 : lastLine.dy - firstLine.dy + 4,
    ));
    tallLine.position(Offset(
      greatestWidth + 146,
      firstLine.dy,
    ));

    //Place this recipe
    final segment = getChild(node);
    segment.layout(BoxConstraints.tightForFinite(
      width: 500,
      height: segmentHeight,
    ));
    segment.position(Offset(
      greatestWidth,
      tallLine.offset.dy - 56 - 64 + 2,
    ));
    segmentOffset = segment.offset;
    segmentSize = segment.size;

    var totalHeight = max(inputHeight, segmentHeight);

    //Place raw resource column
    var rawCol = getChild(node.recipe.input);
    rawCol.layout(BoxConstraints.tightForFinite(
      width: 146,
      height: totalHeight -
          (inputHeight - rawResourceHeight) -
          (rawResourceHeight > 0 ? 128 : 0),
    ));
    rawCol.position(Offset(
      greatestWidth,
      segmentOffset.dy + 64,
    ));

    return Size(500 + greatestWidth, totalHeight);
  }
}

class ExtendedCurvedCorner extends CustomPainter {
  final bool top;
  final Paint linePaint = Paint()
    ..color = Colors.blue.shade800
    ..strokeWidth = 4;

  ExtendedCurvedCorner(this.top);

  @override
  void paint(Canvas canvas, Size size) {
    if (top) {
      canvas.drawPath(
        Path()
          ..lineTo(size.width - 48, 0)
          ..addArc(
            Rect.fromCircle(
              center: Offset(size.width - 48, 48),
              radius: 48,
            ),
            pi * 1.5,
            pi / 2,
          )
          ..moveTo(size.width, size.height - 8)
          ..lineTo(size.width, size.height),
        linePaint..style = PaintingStyle.stroke,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width - 48, size.height)
          ..addArc(
            Rect.fromCircle(
              center: Offset(size.width - 48, size.height - 48),
              radius: 48,
            ),
            0,
            pi / 2,
          )
          ..moveTo(size.width, 8)
          ..lineTo(size.width, 0),
        linePaint..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(ExtendedCurvedCorner oldDelegate) => false;
}
