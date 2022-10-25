import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_model.dart';
import 'string_utils.dart';
import 'item_recipe.dart';
import 'production_line.dart';

class AssetDisplay extends StatefulWidget {
  final bool? isItem;
  final String? assetName;

  const AssetDisplay({
    this.isItem,
    this.assetName,
    super.key,
  });

  @override
  State<AssetDisplay> createState() => _AssetDisplayState();
}

class _AssetDisplayState extends State<AssetDisplay> {
  late final String rootDir;
  late final GameModel game;

  @override
  void initState() {
    super.initState();
    game = Provider.of<GameModel>(context, listen: false);
    if (Directory.current.path.basename != game.gameName) {
      Directory.current = "data/${game.gameName}";
    }
    rootDir = Directory.current.path;

    game.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Consumer<GameModel>(
            builder: (context, game, child) => Column(
              children: [
                Text(
                  widget.isItem == null ? game.gameName : widget.assetName!,
                  textAlign: TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                if (widget.isItem != null)
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Image.file(widget.isItem!
                        ? game.itemAssets[widget.assetName]!
                        : game.buildingAssets[widget.assetName]!.file),
                  ),
                SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height -
                      60 -
                      (widget.isItem != null ? 64 : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              widget.isItem == null ? "Items" : "Recipes",
                              textAlign: TextAlign.center,
                              textWidthBasis: TextWidthBasis.longestLine,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            if (widget.isItem == null)
                              ...game.itemList(context, setState),
                            if (widget.isItem != null &&
                                (widget.isItem! ||
                                    // Buildings can only have one recipe
                                    (!widget.isItem! &&
                                        !game.recipes
                                            .containsKey(widget.assetName))))
                              newRecipeWidget(context),
                            if (widget.isItem != null &&
                                game.recipes.containsKey(widget.assetName))
                              Expanded(
                                child: ListView(
                                  children: [
                                    for (var r
                                        in game.recipes[widget.assetName]!)
                                      Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: recipe(r, game),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              widget.isItem == null ? "Buildings" : "Uses",
                              textAlign: TextAlign.center,
                              textWidthBasis: TextWidthBasis.longestLine,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            if (widget.isItem == null)
                              ...game.buildingList(context, setState),
                            if (widget.isItem != null &&
                                game.uses.containsKey(widget.assetName))
                              Expanded(
                                child: ListView(
                                  children: [
                                    for (var r in game.uses[widget.assetName]!)
                                      Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: recipe(r, game),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 10,
            width: 64,
            top: 10,
            height: 64,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.popUntil(
                  context, (route) => route.settings.name == "home"),
              icon: Image.file(game.gameIcon),
            ),
          ),
          Positioned.directional(
            textDirection: TextDirection.ltr,
            start: 10,
            width: 64,
            top: 74,
            height: 64,
            child: TextButton(
              onPressed: () {
                if (widget.isItem == null) {
                  Directory.current = "..\\..";
                }
                Navigator.pop(context);
              },
              child: const Icon(Icons.arrow_back),
            ),
          ),
        ],
      ),
    );
  }

  Widget routeableAsset(Widget child, String assetName, bool item) {
    return IconButton(
      color: Colors.transparent,
      padding: EdgeInsets.zero,
      tooltip: assetName,
      hoverColor: Colors.white.withOpacity(0.25),
      onPressed: assetName == widget.assetName
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangeNotifierProvider.value(
                    value: game,
                    child: AssetDisplay(
                      isItem: item,
                      assetName: assetName,
                    ),
                  ),
                ),
              ),
      icon: child,
    );
  }

  Widget recipe(ItemRecipe r, GameModel game) {
    return SizedBox(
      width: MediaQuery.of(context).size.width / 2,
      height: 150,
      child: GestureDetector(
        onTap: r.building != null
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChangeNotifierProvider.value(
                      value: game,
                      child: FactoryOverview(
                        [r],
                        selectedRecipe: r,
                        itemName: r.output
                            .where((o) => !o.byproduct)
                            .map((o) => o.name)
                            .join("/"),
                      ),
                    ),
                  ),
                )
            : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade800,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var inp in r.input.reversed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: routeableAsset(
                                Image.file(game.itemAssets[inp.name]!),
                                inp.name,
                                true,
                              ),
                            ),
                            Text(
                              inp.amount.pretty,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: r.building != null ? 1 : 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (r.building != null)
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 32,
                      ),
                    if (r.building != null)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("${game.buildingAssets[r.building]!.cost} MW"),
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: routeableAsset(
                              Image.file(game.buildingAssets[r.building]!.file),
                              r.building!,
                              false,
                            ),
                          ),
                          Text("${r.rate.pretty}/min"),
                        ],
                      ),
                    const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 32,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    for (var o in r.output)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (game.buildingAssets.containsKey(o.name))
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: routeableAsset(
                                  Image.file(game.buildingAssets[o.name]!.file),
                                  o.name,
                                  false,
                                ),
                              ),
                            if (game.itemAssets.containsKey(o.name))
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: routeableAsset(
                                  Image.file(game.itemAssets[o.name]!),
                                  o.name,
                                  true,
                                ),
                              ),
                            if (!game.buildingAssets.containsKey(o.name))
                              Text(
                                o.amount.pretty,
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget newRecipeWidget(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 100,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              mouseCursor: game.recipes.containsKey(widget.assetName!)
                  ? SystemMouseCursors.click
                  : null,
              onTap: game.recipes.containsKey(widget.assetName!)
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChangeNotifierProvider.value(
                            value: game,
                            child: FactoryOverview(
                              game.recipes[widget.assetName]!,
                              itemName: widget.assetName!,
                            ),
                          ),
                        ),
                      )
                  : null,
              hoverColor: Colors.grey.shade700,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: game.recipes.containsKey(widget.assetName!)
                    ? Colors.grey.shade800
                    : Colors.grey.shade900,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.auto_graph,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "View all recipes",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall!
                          .copyWith(
                              color: game.recipes.containsKey(widget.assetName!)
                                  ? null
                                  : Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () async {
                game.newRecipe = ItemRecipe(
                  [],
                  [ItemAmount(widget.assetName!, 1)],
                  0,
                  null,
                );
                await showDialog(
                  context: context,
                  builder: (context) => game.newRecipeDialog(
                    context,
                    widget.assetName!,
                  ),
                );
                game.newRecipe = null;
              },
              hoverColor: Colors.grey.shade700,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade800,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.handyman,
                        size: 64,
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
          ],
        ),
      ),
    );
  }
}
