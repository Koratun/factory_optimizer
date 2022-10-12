import 'dart:math';

import 'package:flutter/material.dart';
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
  ValueNotifier<bool> selected = ValueNotifier(false);
  late _OptimizerInfo myCost;

  _RecipeNode(this.recipe, this.depth) {
    myCost = _OptimizerInfo.zero(this);
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
          double oOpRate = incoming.recipe.operationalRate ?? 1;
          double iOpRate = outgoing.recipe.operationalRate ?? 1;
          recipeMultiplier = (iOpRate * i.amount) / (oOpRate * o.amount);
          if (upstreamEdge != null) {
            recipeMultiplier *= upstreamEdge!.recipeMultiplier;
          }
        }
      }
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

  double coalescedEfficiency;
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
    this.coalescedEfficiency,
    this.efficientNode,
  );

  _OptimizerInfo.zero(_RecipeNode self)
      : power = 0,
        speed = 0,
        rawResources = 0,
        coalescedEfficiency = 1,
        powerNode = self,
        speedNode = self,
        rawResourceNode = self,
        efficientNode = self;

  _OptimizerInfo operator +(_OptimizerInfo other) {
    power += other.power;
    speed += other.speed;
    rawResources += other.rawResources;
    subNodes += other.subNodes;
    coalescedEfficiency += other.coalescedEfficiency;
    return this;
  }

  double get efficiency => coalescedEfficiency / subNodes;

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
    coalescedEfficiency = o.coalescedEfficiency;
    subNodes = o.subNodes;
    efficientNode = o.efficientNode;
  }
}

class _ProductionGraph {
  final GameModel game;

  late final _OptimizerInfo optimizedData;
  final List<_RecipeEdge> edges = [];
  final List<_RecipeNode> nodes = [];
  final List<_RecipeNode> quickestNodes = [];
  final List<_RecipeNode> leastRawResourceNodes = [];
  final List<_RecipeNode> leastPowerNodes = [];
  final List<_RecipeNode> mostEfficientNodes = [];

  int depth = 0;
  int greatestDepth = 0;

  bool recalculate = true;

  _ProductionGraph(this.game, rootRecipe, {String? rootName}) {
    nodes.add(_RecipeNode(rootRecipe, 0));
    quickestNodes.add(nodes.first);
    leastRawResourceNodes.add(nodes.first);
    leastPowerNodes.add(nodes.first);
    mostEfficientNodes.add(nodes.first);
    processRecipe(nodes.first);
    optimizedData = scanGraph(nodes.first);
    if (rootName != null) {
      optimizedData.speed = nodes.first.recipe.output
              .firstWhere((o) => o.name == rootName)
              .amount *
          (nodes.first.recipe.operationalRate ?? 1);
    } else {
      optimizedData.speed = nodes.first.recipe.rate;
    }
  }

  void processRecipe(_RecipeNode node, {_RecipeEdge? upstreamEdge}) {
    depth += 1;
    for (var i in node.recipe.input) {
      var subRecipes = game.recipes[i.name];
      if (subRecipes != null) {
        var newNodes = subRecipes
            .map((r) => _RecipeNode(r, depth)
              ..selected.addListener(() => recalculate = true))
            .toList();
        nodes.addAll(newNodes);
        var newEdges =
            newNodes.map((n) => _RecipeEdge(n, node, upstreamEdge)).toList();
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
      node.myCost.coalescedEfficiency =
          _calculateEfficiency(upEdge.recipeMultiplier);
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
          inputCost.setBetter(cost);
        }
      }
      if (inputCost != null) {
        leastPowerNodes.add(inputCost.powerNode);
        quickestNodes.add(inputCost.speedNode);
        leastRawResourceNodes.add(inputCost.rawResourceNode);
        mostEfficientNodes.add(inputCost.efficientNode);
        node.myCost += inputCost;
      } else {
        node.myCost.rawResources += i.amount *
            (node.recipe.operationalRate ?? 1) *
            (upEdge?.recipeMultiplier ?? 1);
      }
    }
    if (upEdge != null) {
      node.myCost.speed = node.recipe.output
              .firstWhere((o) => o.name == upEdge!.connectingName)
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
    node ??= nodes.first;
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    double efficiency = upEdge?.recipeMultiplier ?? 1;
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
    node ??= nodes.first;
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
                    (upEdge?.recipeMultiplier ?? 1)
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
    if (game.recipes.containsKey(node.recipe.building)) {
      int buildingsRequired = upEdge?.recipeMultiplier.ceil() ?? 1;
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
    node ??= nodes.first;
    double power = 0;
    _RecipeEdge? upEdge;
    try {
      upEdge = edges.where((e) => e.incoming == node).single;
      // ignore: empty_catches
    } on StateError {}
    int buildingsRequired = upEdge?.recipeMultiplier.ceil() ?? 1;
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
  late List<_ProductionGraph> productionGraphs;
  _ProductionGraph? graphToDisplay;

  @override
  void initState() {
    super.initState();
    game = Provider.of<GameModel>(context, listen: false);
    rebuildGraphs();
  }

  void rebuildGraphs() {
    productionGraphs = widget.rootRecipes
        .map((r) => _ProductionGraph(game, r,
            rootName: widget.itemName.contains("/") ? null : widget.itemName))
        .toList();
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
            p.optimizedData.rawResources <= p2.optimizedData.rawResources
                ? p
                : p2);
        selectList(graphToDisplay!.leastRawResourceNodes);
        break;
      case OptimizationStrategy.speed:
        graphToDisplay ??= productionGraphs.reduce((p, p2) =>
            p.optimizedData.speed >= p2.optimizedData.speed ? p : p2);
        selectList(graphToDisplay!.quickestNodes);
        break;
      case OptimizationStrategy.power:
        graphToDisplay ??= productionGraphs.reduce((p, p2) =>
            p.optimizedData.power <= p2.optimizedData.power ? p : p2);
        selectList(graphToDisplay!.leastPowerNodes);
        break;
      case OptimizationStrategy.efficiency:
        graphToDisplay ??= productionGraphs.reduce((p, p2) =>
            p.optimizedData.efficiency >= p2.optimizedData.efficiency ? p : p2);
        selectList(graphToDisplay!.mostEfficientNodes);
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
                      _markDirty,
                      graphToDisplay!.nodes.first,
                      subDelegates:
                          _getSubdelegates(graphToDisplay!.nodes.first),
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
            start: MediaQuery.of(context).size.width * 0.4,
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
            start: 150,
            end: MediaQuery.of(context).size.width * 0.6,
            top: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            end: MediaQuery.of(context).size.width * .6,
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
                              for (var e
                                  in graphToDisplay!.rawResources.entries)
                                itemAmount(e.key, e.value),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: DeltaText(
                                  graphToDisplay!.powerConsumption * 60,
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
                                      graphToDisplay!.graphEfficiency * 100,
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
            start: MediaQuery.of(context).size.width * .4,
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
                              for (var e
                                  in graphToDisplay!.oneTimeResources.entries)
                                itemAmount(e.key, e.value),
                              if (graphToDisplay!.oneTimeResources.isEmpty)
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

  void _markDirty() => setState(() => rebuildGraphs());

  List<_FactoryDelegate> _getSubdelegates(_RecipeNode node) {
    return [
      for (var e in graphToDisplay!.edges
          .where((e) => e.outgoing == node && e.incoming.selected.value))
        _FactoryDelegate(
          context,
          game,
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
    this.markDirty,
    this.node, {
    this.upEdge,
    required this.subDelegates,
  }) {
    var rawResources = node.recipe.input
        .where((i) => !game.recipes.containsKey(i.name))
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
                  upEdge?.recipeMultiplier ?? 1,
                  raw: true,
                ),
            ],
          ),
        ),
        for (var i
            in node.recipe.input.where((i) => game.recipes.containsKey(i.name)))
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
                color: game.recipes.containsKey(i.name)
                    ? Colors.greenAccent.withOpacity(0.4)
                    : Colors.brown.shade900.withOpacity(0.7),
                child: Image.file(game.itemAssets[i.name]!),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: raw ? 34 : 0,
            child: Text(
              "${(i.amount * opRate * multiplier).pretty} / min",
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (recipeChangeable(i))
            IconButton(
              padding: EdgeInsets.zero,
              onPressed: game.recipes.containsKey(i.name) &&
                      game.recipes[i.name]!.length > 1
                  ? () {}
                  : () async {
                      game.newRecipe = ItemRecipe(
                        [],
                        [ItemAmount(i.name, 1)],
                        0,
                        null,
                      );
                      if (null !=
                          await showDialog(
                            context: context,
                            builder: (context) => game.newRecipeDialog(
                              context,
                              i.name,
                            ),
                          )) {
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
        ],
      ),
    );
  }

  bool recipeChangeable(ItemAmount i) =>
      upEdge == null ||
      i.name == upEdge!.connectingName ||
      !game.recipes.containsKey(i.name);

  Widget factorySegment(BuildContext context) {
    var outputs = [
      for (var o in node.recipe.output)
        itemAmount(
          context,
          o,
          node.recipe.operationalRate ?? 1,
          upEdge?.recipeMultiplier ?? 1,
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
          child: Text(
            "${(upEdge?.recipeMultiplier ?? 1).pretty}x",
            style: Theme.of(context).textTheme.labelLarge,
            textWidthBasis: TextWidthBasis.longestLine,
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
                "${(game.buildingAssets[node.recipe.building!]!.cost * (upEdge?.recipeMultiplier.ceil() ?? 1)).pretty} MW / sec",
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
        .where((e) => !game.recipes.containsKey(e.name))
        .toList();
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
