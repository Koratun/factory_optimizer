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
          double oOpRate = outgoing.recipe.operationalRate ?? 1;
          double iOpRate = incoming.recipe.operationalRate ?? 1;
          recipeMultiplier = (oOpRate * o.amount) / (iOpRate * i.amount);
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

  _OptimizerInfo.zero(_RecipeNode self)
      : power = 0,
        resources = 0,
        rawResources = 0,
        powerNode = self,
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

  bool recalculate = true;

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
    if (!game.recipes.containsKey(node.recipe.building)) {
      return resources;
    }
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
        subResources = _getOneTimeResourceCost(node: e.incoming);
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
                        child: ConstrainedBox(
                          constraints: BoxConstraints.loose(Size(
                            MediaQuery.of(context).size.width / 3,
                            double.infinity,
                          )),
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
          Positioned.fill(
            top: 200,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _FactoryDelegate(
                context,
                game,
                graphToDisplay!.nodes.first,
                subDelegates: _getSubdelegates(graphToDisplay!.nodes.first),
              ).boxy,
            ),
          ),
        ],
      ),
    );
  }

  List<_FactoryDelegate> _getSubdelegates(_RecipeNode node) {
    return [
      for (var e in graphToDisplay!.edges
          .where((e) => e.outgoing == node && e.incoming.selected.value))
        _FactoryDelegate(
          context,
          game,
          e.incoming,
          subDelegates: _getSubdelegates(e.incoming),
          upEdge: e,
        )
    ];
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
}

class _FactoryDelegate extends BoxyDelegate {
  final GameModel game;
  final _RecipeNode node;
  final _RecipeEdge? upEdge;
  final List<_FactoryDelegate> subDelegates;
  late final Widget boxy;
  late final double outputHeight;
  final Map<String, double> outputLocations = {};

  _FactoryDelegate(
    BuildContext context,
    this.game,
    this.node, {
    this.upEdge,
    required this.subDelegates,
  }) {
    boxy = CustomBoxy(
      delegate: this,
      children: [
        for (var d in subDelegates) BoxyId(id: d.node, child: d.boxy),
        BoxyId(id: node, child: factorySegment(context)),
        for (var i in node.recipe.input)
          BoxyId(
            id: i,
            child: Container(
              width: 114 - 82.5,
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
      BuildContext context, ItemAmount i, double opRate, double multiplier) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Tooltip(
              message: i.name,
              verticalOffset: 4,
              child: Card(
                elevation: 1,
                color: game.recipes.containsKey(i.name)
                    ? Colors.greenAccent.withOpacity(0.1)
                    : Colors.brown.shade900.withOpacity(0.1),
                child: Image.file(game.itemAssets[i.name]!),
              ),
            ),
          ),
          Text(
            "${(i.amount * opRate * multiplier).pretty} / min",
            style: Theme.of(context).textTheme.labelSmall,
            textWidthBasis: TextWidthBasis.longestLine,
          ),
          if (recipeChangeable(i))
            Positioned(
              top: 0,
              left: 0,
              width: 16,
              height: 16,
              child: IconButton(
                onPressed: () {},
                icon: Icon(
                  game.recipes.containsKey(i.name)
                      ? Icons.change_circle
                      : Icons.add_circle,
                  size: 16,
                  color: Colors.green,
                ),
                tooltip: game.recipes.containsKey(i.name)
                    ? "Change recipe"
                    : "Add recipe",
              ),
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

    outputHeight = 64 + 48 * outputs.length + 70 * (outputs.length - 1);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 32,
          bottom: 32,
          right: 0,
          width: 48,
          child: Column(
            children: outputs.expand((i) sync* {
              yield i;
              if (outputs.indexOf(i) != outputs.length - 1) {
                yield Expanded(
                  child: Container(
                    width: 4,
                    color: Colors.lightBlueAccent,
                  ),
                );
              }
            }).toList(),
          ),
        ),
        Positioned(
          height: 4,
          width: outputs.length % 2 == 0 ? 90 : 63,
          right: outputs.length % 2 == 0 ? 24 : 51,
          child: Container(color: Colors.lightBlueAccent),
        ),
        for (var i in node.recipe.input
            .where((i) => !game.recipes.containsKey(i.name))
            .toList()
            .asMap()
            .entries)
          Positioned(
            top: 24 + (i.key * 112), // 8 + 48 + 32 + 32 - 8
            height: 56,
            left: 0,
            width: 56,
            child: itemAmount(
              context,
              i.value,
              node.recipe.operationalRate ?? 1,
              upEdge?.recipeMultiplier ?? 1,
            ),
          ),
        Positioned(
          top: 0,
          left: 40,
          right: 0,
          height: 28,
          child: CustomPaint(painter: ExtendedCurvedCorner(true)),
        ),
        Positioned(
          bottom: 0,
          left: 40,
          right: 0,
          height: 28,
          child: CustomPaint(painter: ExtendedCurvedCorner(false)),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Text(
            "${(upEdge?.recipeMultiplier ?? 1).pretty}x",
            style: Theme.of(context).textTheme.labelSmall,
            textWidthBasis: TextWidthBasis.longestLine,
          ),
        ),
        Positioned(
          height: 4,
          left: 82.5,
          right: 114,
          child: Container(color: Colors.lightBlueAccent),
        ),
        Positioned(
          height: 112,
          width: 64,
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
                width: 64,
                height: 64,
                child: Card(
                  elevation: 1,
                  color: game.recipes.containsKey(node.recipe.building!)
                      ? Colors.lightBlueAccent.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  child: Image.file(
                      game.buildingAssets[node.recipe.building!]!.file),
                ),
              ),
              Text(
                "${game.buildingAssets[node.recipe.building!]!.cost.pretty} MW / building / min\n"
                "${(game.buildingAssets[node.recipe.building!]!.cost * (upEdge?.recipeMultiplier.ceil() ?? 1)).pretty} MW / min",
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

  @override
  Size layout() {
    double greatestWidth = 0;
    double inputHeight = 0;

    //Size children of this recipe
    var recipeChildren = Map.fromEntries(
      subDelegates.map((d) => MapEntry(d, getChild(d.node))),
    );
    for (var sub in recipeChildren.values) {
      var size = sub.layout(constraints);
      inputHeight += size.height + 6;
      if (size.width - 48 > greatestWidth) {
        greatestWidth = size.width - 48;
      }
    }

    var rawResources = node.recipe.input
        .where((e) => !game.recipes.containsKey(e.name))
        .toList();
    double rawResourceHeight = 0;
    if (rawResources.isNotEmpty) {
      rawResourceHeight =
          64 + rawResources.length * 48 + (rawResources.length - 1) * 70;
    }
    inputHeight += rawResourceHeight;

    Offset? firstLine;
    Offset lastLine = Offset.zero;

    //Place lines for raw resources
    for (var e in rawResources.asMap().entries) {
      var rawLine = getChild(e.value);
      rawLine.layout(constraints);
      rawLine.position(Offset(greatestWidth + 51, 24 + (e.key * 112)));
      firstLine ??= rawLine.offset;
      lastLine = rawLine.offset;
    }

    final totalHeight = max(inputHeight, outputHeight);

    //Place recipe children and their lines
    double lastHeight = rawResourceHeight;
    for (var e in recipeChildren.entries) {
      e.value.position(Offset(
        greatestWidth + 48 - e.value.size.width,
        lastHeight + 3,
      ));

      var inputPos = e.key.node.recipe.output
          .indexWhere((o) => o.name == e.key.upEdge!.connectingName);

      var childSegment = e.key.getChild(e.key.node);

      var childLine = getChild(e.key.upEdge!.connectingName);
      childLine.layout(constraints);
      if (inputPos == 0) {
        childLine.position(Offset(
          greatestWidth + 51,
          lastHeight + 32 + 24 + childSegment.offset.dy,
        ));
      } else {
        childLine.position(Offset(
            greatestWidth + 51,
            (lastHeight + 56 + childSegment.offset.dy) +
                (childSegment.size.height - 64 - 48) /
                    (e.key.node.recipe.output.length - 1) *
                    inputPos));
      }
      firstLine ??= childLine.offset;
      lastLine = childLine.offset;

      lastHeight += e.value.size.height + 6;
    }

    var tallLine = getChild(node.recipe);
    tallLine.layout(BoxConstraints.tightForFinite(
      width: 4,
      height: lastLine.dy - firstLine!.dy,
    ));
    tallLine.position(Offset(
      greatestWidth + 82.5,
      firstLine.dy,
    ));

    //Place this recipe
    final segment = getChild(node);
    segment.layout(BoxConstraints.tightForFinite(
      width: 298,
      height: tallLine.size.height + 64 + 48,
    ));
    segment.position(Offset(
      greatestWidth,
      tallLine.offset.dy - 24 - 32,
    ));

    return Size(298 + greatestWidth, totalHeight);
  }
}

class ExtendedCurvedCorner extends CustomPainter {
  final bool top;
  final Paint linePaint = Paint()
    ..color = Colors.lightBlueAccent
    ..strokeWidth = 2;

  ExtendedCurvedCorner(this.top);

  @override
  void paint(Canvas canvas, Size size) {
    if (top) {
      canvas.drawLine(
        Offset.zero,
        Offset(size.width - 24, 0),
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width - 12, 12), radius: 12),
        pi * 1.5,
        pi / 2,
        true,
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width, 24),
        Offset(size.width, size.height),
        linePaint,
      );
    } else {
      canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width - 24, size.height),
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width - 12, size.height - 12),
          radius: 12,
        ),
        0,
        pi / 2,
        true,
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width, size.height - 24),
        Offset(size.width, 0),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(ExtendedCurvedCorner oldDelegate) => false;
}
