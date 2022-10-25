import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import 'string_utils.dart';
import 'profile.dart';
import 'item_recipe.dart';

// Building files must have following format:
// Name-PowerConsumption.extension
class BuildingData {
  final File file;
  late final String name;
  late final double cost;

  BuildingData(this.file) {
    name = file.path.basename.substring(0, file.path.basename.lastIndexOf('-'));
    cost = double.parse(file.path.basename
        .substring(file.path.basename.lastIndexOf('-') + 1)
        .trimExtension);
  }
}

class GameModel extends ChangeNotifier {
  final String gameName;
  final File gameIcon;
  final String rootDir;

  GameModel(this.gameName, this.gameIcon) : rootDir = Directory.current.path;

  final Map<String, File> itemAssets = {};
  final Map<String, BuildingData> buildingAssets = {};
  final Map<String, List<ItemRecipe>> recipes = {};
  final Map<String, List<ItemRecipe>> uses = {};

  bool get loaded => itemAssets.isNotEmpty;

  void load() {
    if (!loaded) {
      if (Directory("assets").existsSync()) {
        Directory("assets\\items").list().forEach(
            (f) => itemAssets[f.path.basename.trimExtension] = (f as File));
        Directory("assets\\buildings")
            .list()
            .map((f) => BuildingData(f as File))
            .forEach((b) => buildingAssets[b.name] = b);
      } else {
        Directory("assets\\items").createSync(recursive: true);
        Directory("assets\\buildings").createSync();
      }
      if (Directory("recipes").existsSync()) {
        Directory("recipes")
            .list()
            .map((f) => ItemRecipe.fromJson(
                json.decode((f as File).readAsStringSync())))
            .forEach((r) => _registerRecipe(r));
      } else {
        Directory("recipes").createSync();
      }
    }
  }

  void _registerRecipe(ItemRecipe r) {
    for (var o in r.output) {
      if (o.byproduct) {
        continue;
      }
      if (recipes.containsKey(o.name)) {
        recipes[o.name]!.add(r);
      } else {
        recipes[o.name] = [r];
      }
    }
    for (var inp in r.input) {
      if (uses.containsKey(inp.name)) {
        uses[inp.name]!.add(r);
      } else {
        uses[inp.name] = [r];
      }
    }
    if (r.building != null) {
      if (uses.containsKey(r.building)) {
        uses[r.building]!.add(r);
      } else {
        uses[r.building!] = [r];
      }
    }
    notifyListeners();
  }

  TextEditingController itemSearch = TextEditingController();

  void refreshSearch() => itemSearch.text = "";

  Iterable<Widget> itemList(
    BuildContext context,
    void Function(void Function()) setState, {
    bool returnSelection = false,
  }) {
    return [
      newItemWidget(context, returnSelection: true),
      Container(
        // height: 48,
        width: 400,
        padding: const EdgeInsets.all(8),
        color: Colors.grey.shade900,
        child: TextField(
          controller: itemSearch,
          decoration: InputDecoration(
              // filled: true,
              // fillColor: Colors.lightBlue.shade900,
              icon: const Icon(
                Icons.search,
                color: Colors.lightBlueAccent,
                size: 48,
              ),
              hintText: "Search",
              hintStyle: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: Colors.white)),
          onChanged: (value) => setState(() {}),
        ),
      ),
      Expanded(
        child: ListView(
          children: itemAssets.entries
              .where((e) =>
                  e.key.toLowerCase().contains(itemSearch.text.toLowerCase()))
              .map(
                (e) => Center(
                  child: SizedBox(
                    width: 400,
                    child: ListTile(
                      onTap: returnSelection
                          ? () => Navigator.pop(context, e.key)
                          : () async {
                              refreshSearch();
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ChangeNotifierProvider.value(
                                    value: this,
                                    child: AssetDisplay(
                                      isItem: true,
                                      assetName: e.key,
                                    ),
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                      hoverColor: Colors.grey.shade900,
                      leading: Image.file(e.value),
                      title: Text(
                        e.key,
                        textWidthBasis: TextWidthBasis.longestLine,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ];
  }

  Iterable<Widget> buildingList(
    BuildContext context,
    void Function(void Function()) setState, {
    bool returnSelection = false,
  }) {
    return [
      newBuildingWidget(context, returnSelection: true),
      Expanded(
        child: ListView(
          children: buildingAssets.values
              .map(
                (b) => Center(
                  child: SizedBox(
                    width: 400,
                    child: ListTile(
                      onTap: returnSelection
                          ? () => Navigator.pop(context, b.name)
                          : () async {
                              refreshSearch();
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ChangeNotifierProvider.value(
                                    value: this,
                                    child: AssetDisplay(
                                      isItem: false,
                                      assetName: b.name,
                                    ),
                                  ),
                                ),
                              );
                              setState(() {});
                            },
                      hoverColor: Colors.grey.shade900,
                      leading: Image.file(b.file),
                      visualDensity: const VisualDensity(vertical: 4),
                      title: Text(
                        b.name,
                        textWidthBasis: TextWidthBasis.longestLine,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ];
  }

  final _formKey = GlobalKey<FormState>();
  File? tempFile;

  ItemRecipe? newRecipe;

  Widget _reagentSelectDialog(BuildContext context, bool item) {
    return Dialog(
      alignment: Alignment.center,
      child: Container(
        color: Colors.grey.shade800,
        child: SizedBox(
          width: 800,
          height: 1000,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  Text(
                    item ? "Select an Item" : "Select a Building",
                    textAlign: TextAlign.center,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  ...(item
                      ? itemList(context, setState, returnSelection: true)
                      : buildingList(context, setState, returnSelection: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addRecipeReagent(
    BuildContext context,
    void Function(void Function()) setState,
    bool item,
    bool required,
    bool input,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Card(
              color: Colors.grey.shade700,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: required ? Colors.white : Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: GestureDetector(
                onTap: () async {
                  String? reagent = await showDialog<String>(
                    context: context,
                    builder: (context) => _reagentSelectDialog(context, item),
                  );
                  if (reagent != null) {
                    setState(() {
                      if (item) {
                        if (input) {
                          newRecipe!.input.add(ItemAmount(reagent, 0));
                        } else {
                          newRecipe!.output.add(ItemAmount(reagent, 0));
                        }
                      } else {
                        newRecipe!.building = reagent;
                      }
                    });
                  }
                },
                child: const Center(
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item ? "Item" : "Building",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          )
        ],
      ),
    );
  }

  final Map<String, TextEditingController> recipeFields = {};

  Widget _floatingButtons(
    void Function(void Function()) setState,
    Widget child,
    String assetName,
    bool item,
    bool input, {
    required String outputName,
  }) {
    if (assetName == outputName && !input) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          width: 16,
          top: 0,
          height: 16,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              recipeFields.remove(assetName);
              setState(() {
                if (item) {
                  if (input) {
                    newRecipe!.input.removeWhere((e) => e.name == assetName);
                  } else {
                    newRecipe!.output.removeWhere((e) => e.name == assetName);
                  }
                } else {
                  newRecipe!.building = null;
                  newRecipe!.rate = 0;
                }
              });
            },
            icon: const Icon(
              Icons.cancel,
              size: 16,
              color: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _reagent(
    BuildContext context,
    void Function(void Function()) setState,
    String assetName, {
    required bool item,
    required bool input,
    required String outputName,
  }) {
    if (!recipeFields.containsKey(assetName)) {
      recipeFields[assetName] = TextEditingController(text: "0");
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 10),
      child: item
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _floatingButtons(
                      setState,
                      Image.file(itemAssets[assetName]!),
                      assetName,
                      item,
                      input,
                      outputName: outputName,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(top: 4),
                  width: 60,
                  height: 20,
                  color: Colors.grey.shade700,
                  child: TextField(
                    controller: recipeFields[assetName],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
                    ],
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.grey.shade700,
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "${buildingAssets[assetName]!.cost.pretty} MW",
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _floatingButtons(
                      setState,
                      Image.file(buildingAssets[assetName]!.file),
                      assetName,
                      item,
                      input,
                      outputName: outputName,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(top: 4, right: 2),
                  width: 60,
                  height: 20,
                  color: Colors.grey.shade700,
                  child: TextField(
                    controller: recipeFields[assetName],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
                    ],
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.grey.shade700,
                      border: InputBorder.none,
                      isCollapsed: true,
                      suffixText: input ? "/min" : null,
                      suffixStyle: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget newRecipeDialog(
    BuildContext context,
    String outputName,
  ) {
    var nameField = TextEditingController();

    return StatefulBuilder(
      builder: (context, setState) => Dialog(
        alignment: Alignment.center,
        child: Container(
          color: Colors.grey.shade900,
          child: SizedBox(
            width: 1050,
            height: 220,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade800,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: nameField,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"\w"))
                    ],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade400,
                      hintText: "Filename for recipe without the extension",
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (newRecipe!.input.length <= 4)
                              _addRecipeReagent(
                                context,
                                setState,
                                true,
                                newRecipe!.input.isEmpty,
                                true,
                              ),
                            for (var inp in newRecipe!.input.reversed)
                              _reagent(
                                context,
                                setState,
                                inp.name,
                                item: true,
                                input: true,
                                outputName: outputName,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 32,
                            ),
                            if (newRecipe!.building == null)
                              _addRecipeReagent(
                                context,
                                setState,
                                false,
                                false,
                                false,
                              ),
                            if (newRecipe!.building != null)
                              _reagent(
                                context,
                                setState,
                                newRecipe!.building!,
                                item: false,
                                input: true,
                                outputName: outputName,
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
                            for (var o in newRecipe!.output)
                              _reagent(
                                context,
                                setState,
                                o.name,
                                item: itemAssets.containsKey(o.name),
                                input: false,
                                outputName: outputName,
                              ),
                            if (newRecipe!.output.length <= 4)
                              _addRecipeReagent(
                                context,
                                setState,
                                true,
                                false,
                                false,
                              ),
                          ],
                        ),
                      )
                    ],
                  ),
                  TextButton(
                    onPressed: () {
                      var failed = false;
                      if (nameField.text.isEmpty) {
                        _errorAlert(
                            context, "The filename can be anything A-z.");
                        failed = true;
                      }
                      if (newRecipe!.input.isEmpty) {
                        _errorAlert(
                            context, "Recipe must have at least one input.");
                        failed = true;
                      }
                      if (newRecipe!.building != null &&
                          (double.tryParse(recipeFields[newRecipe!.building!]!
                                      .text) ??
                                  0) <=
                              0) {
                        _errorAlert(context, "Recipe rate must be above 0.");
                        failed = true;
                      }
                      for (var inp in newRecipe!.input) {
                        if ((double.tryParse(recipeFields[inp.name]!.text) ??
                                0) <=
                            0) {
                          _errorAlert(
                              context, "${inp.name}: rate must be above 0.");
                          failed = true;
                        }
                      }
                      for (var o in newRecipe!.output) {
                        if ((double.tryParse(recipeFields[o.name]!.text) ??
                                0) <=
                            0) {
                          _errorAlert(
                              context, "${o.name}: rate must be above 0.");
                          failed = true;
                        }
                      }
                      if (!failed) {
                        for (var inp in newRecipe!.input) {
                          inp.amount =
                              double.tryParse(recipeFields[inp.name]!.text)!;
                        }
                        for (var o in newRecipe!.output) {
                          o.amount =
                              double.tryParse(recipeFields[o.name]!.text)!;
                        }
                        if (newRecipe!.building != null) {
                          newRecipe!.rate = double.tryParse(
                              recipeFields[newRecipe!.building!]!.text)!;
                        }
                        var infinite = _checkForInfiniteRecursion(newRecipe!);
                        if (infinite != null) {
                          newRecipe!.output
                              .firstWhere((e) => e.name == infinite)
                              .byproduct = true;
                        }
                        File("recipes/${nameField.text}.json")
                            .writeAsStringSync(
                                json.encode(newRecipe!.toJson()));
                        _registerRecipe(newRecipe!);
                        recipeFields.clear();
                        Navigator.pop(context, true);
                      }
                    },
                    child: const Text("Add Recipe"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _checkForInfiniteRecursion(
    ItemRecipe recipe, {
    List<String>? toCheck,
  }) {
    toCheck ??= recipe.output.map((e) => e.name).toList();
    for (var i in recipe.input) {
      if (toCheck.contains(i.name)) {
        return i.name;
      }
      if (recipes.containsKey(i.name)) {
        for (var r in recipes[i.name]!) {
          var response = _checkForInfiniteRecursion(r, toCheck: toCheck);
          if (response != null) {
            return response;
          }
        }
      }
    }
    return null;
  }

  void _errorAlert(BuildContext context, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade700,
        title: const Text("Error"),
        content: Text(content),
      ),
    );
  }

  Widget newItemWidget(
    BuildContext context, {
    bool returnSelection = false,
  }) {
    return SizedBox(
      width: 400,
      child: ListTile(
        hoverColor: Colors.grey.shade900,
        leading: const Icon(
          Icons.add,
          color: Colors.white,
        ),
        title: Text(
          "New Item",
          textWidthBasis: TextWidthBasis.longestLine,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        onTap: () async {
          String? newItem = await showDialog<String>(
            context: context,
            builder: newItemDialog,
          );
          if (returnSelection && newItem != null) {
            // ignore: use_build_context_synchronously
            Navigator.pop(context, newItem);
          }
        },
      ),
    );
  }

  Widget newBuildingWidget(
    BuildContext context, {
    bool returnSelection = false,
  }) {
    return SizedBox(
      width: 400,
      child: ListTile(
        hoverColor: Colors.grey.shade900,
        leading: const Icon(
          Icons.add,
          color: Colors.white,
        ),
        title: Text(
          "New Building",
          textWidthBasis: TextWidthBasis.longestLine,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        onTap: () async {
          String? newBuilding = await showDialog<String>(
            context: context,
            builder: newBuildingDialog,
          );
          if (returnSelection && newBuilding != null) {
            // ignore: use_build_context_synchronously
            Navigator.pop(context, newBuilding);
          }
        },
      ),
    );
  }

  Widget newItemDialog(BuildContext context) {
    TextEditingController nameController = TextEditingController();
    TextEditingController filePickerController = TextEditingController();

    return Dialog(
      alignment: Alignment.center,
      child: Container(
        color: Colors.grey.shade900,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextFormField(
                  autofocus: true,
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: "Enter item name",
                    filled: true,
                    fillColor: Colors.grey.shade800,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Value needed";
                    }
                    if (itemAssets.containsKey(value)) {
                      return "Name taken";
                    }
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: TextFormField(
                    enabled: false,
                    controller: filePickerController,
                    decoration: InputDecoration(
                      hintText: "Icon path",
                      filled: true,
                      fillColor: Colors.grey.shade800,
                    ),
                    validator: (value) {
                      if (value == null) {
                        return "Must contain a file path or URL";
                      }
                      if (value.startsWith("https")) {
                        var t = nameController.text;
                        var f = tempFile!.copySync(
                            "assets\\items\\$t${tempFile!.path.extension}");
                        tempFile!.deleteSync();
                        tempFile = f;
                        return null;
                      } else {
                        // Attempt to read file location locally
                        if (tempFile == null) {
                          return "No file found";
                        }
                        if (!tempFile!.existsSync()) {
                          return "Unable to access file";
                        }
                        var t = nameController.text;
                        if (!File(
                                "assets\\items\\$t${tempFile!.path.extension}")
                            .existsSync()) {
                          var f = tempFile!.copySync(
                              "assets\\items\\$t${tempFile!.path.extension}");
                          tempFile!.deleteSync();
                          tempFile = f;
                        }
                        return null;
                      }
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(type: FileType.image);
                        Directory.current = rootDir;
                        if (result != null) {
                          tempFile = File(result.files.first.path!);
                          filePickerController.text = result.files.first.path!;
                          String ext = tempFile!.path.extension;
                          tempFile =
                              tempFile!.copySync("assets\\items\\temp$ext");
                        }
                      },
                      child: const Text("Browse local files"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        var data =
                            await Clipboard.getData(Clipboard.kTextPlain);

                        if (data == null) {
                          tempFile = null;
                          filePickerController.text = "Empty clipboard";
                          return;
                        }

                        if (data.text == null) {
                          tempFile = null;
                          filePickerController.text =
                              "Clipboard did not contain text";
                        } else {
                          String url = data.text!;
                          if (!url.startsWith("https")) {
                            tempFile = null;
                            filePickerController.text = "Must use https!";
                            return;
                          }

                          var httpClient = HttpClient();
                          try {
                            var request =
                                await httpClient.getUrl(Uri.parse(url));
                            var response = await request.close();
                            var bytes =
                                await consolidateHttpClientResponseBytes(
                                    response);

                            File file = File("assets\\items\\temp");
                            await file.writeAsBytes(bytes);
                            String? mime = lookupMimeType(
                              "assets\\items\\temp",
                              headerBytes: bytes.take(16).toList(),
                            );
                            if (mime == null) {
                              tempFile = null;
                              filePickerController.text =
                                  "Could not verify file extension";
                              file.deleteSync();
                              return;
                            }
                            tempFile = file.renameSync(
                                "assets\\items\\temp.${mime.basename}");
                            filePickerController.text = url;
                          } catch (error) {
                            tempFile = null;
                            filePickerController.text =
                                'Download error: $error';
                          }
                        }
                      },
                      child: const Text("Read Web URL from clipboard"),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        itemAssets[tempFile!.path.basename.trimExtension] =
                            tempFile!;
                        Navigator.pop(
                            context, tempFile!.path.basename.trimExtension);
                        tempFile = null;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Item added!')),
                        );
                        notifyListeners();
                      }
                    },
                    child: const Text("Submit"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget newBuildingDialog(BuildContext context) {
    TextEditingController nameController = TextEditingController();
    TextEditingController filePickerController = TextEditingController();
    TextEditingController powerController = TextEditingController();

    return Dialog(
      alignment: Alignment.center,
      child: Container(
        color: Colors.grey.shade900,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextFormField(
                  autofocus: true,
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: "Enter building name",
                    filled: true,
                    fillColor: Colors.grey.shade800,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Value needed";
                    }
                    if (buildingAssets.containsKey(value)) {
                      return "Name taken";
                    }
                    return null;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: TextFormField(
                    enabled: false,
                    controller: filePickerController,
                    decoration: InputDecoration(
                      hintText: "Icon path",
                      filled: true,
                      fillColor: Colors.grey.shade800,
                    ),
                    validator: (value) {
                      if (value == null) {
                        return "Must contain a file path or URL";
                      }
                      if (value.startsWith("https")) {
                        var t = nameController.text;
                        var f = tempFile!.copySync(
                            "assets\\buildings\\$t${tempFile!.path.extension}");
                        tempFile!.deleteSync();
                        tempFile = f;
                        return null;
                      } else {
                        // Attempt to read file location locally
                        if (tempFile == null) {
                          return "No file found";
                        }
                        if (!tempFile!.existsSync()) {
                          return "Unable to access file";
                        }
                        var t = nameController.text;
                        if (!File(
                                "assets\\buildings\\$t${tempFile!.path.extension}")
                            .existsSync()) {
                          var f = tempFile!.copySync(
                              "assets\\buildings\\$t${tempFile!.path.extension}");
                          tempFile!.deleteSync();
                          tempFile = f;
                        }
                        return null;
                      }
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(type: FileType.image);
                        Directory.current = rootDir;
                        if (result != null) {
                          tempFile = File(result.files.first.path!);
                          filePickerController.text = result.files.first.path!;
                          String ext = tempFile!.path.extension;
                          tempFile =
                              tempFile!.copySync("assets\\buildings\\temp$ext");
                        }
                      },
                      child: const Text("Browse local files"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        var data =
                            await Clipboard.getData(Clipboard.kTextPlain);

                        if (data == null) {
                          tempFile = null;
                          filePickerController.text = "Empty clipboard";
                          return;
                        }

                        if (data.text == null) {
                          tempFile = null;
                          filePickerController.text =
                              "Clipboard did not contain text";
                        } else {
                          String url = data.text!;
                          if (!url.startsWith("https")) {
                            tempFile = null;
                            filePickerController.text = "Must use https!";
                            return;
                          }

                          var httpClient = HttpClient();
                          try {
                            var request =
                                await httpClient.getUrl(Uri.parse(url));
                            var response = await request.close();
                            var bytes =
                                await consolidateHttpClientResponseBytes(
                                    response);

                            File file = File("assets\\buildings\\temp");
                            await file.writeAsBytes(bytes);
                            String? mime = lookupMimeType(
                              "assets\\buildings\\temp",
                              headerBytes: bytes.take(16).toList(),
                            );
                            if (mime == null) {
                              tempFile = null;
                              filePickerController.text =
                                  "Could not verify file extension";
                              file.deleteSync();
                              return;
                            }
                            tempFile = file.renameSync(
                                "assets\\buildings\\temp.${mime.basename}");
                            filePickerController.text = url;
                          } catch (error) {
                            tempFile = null;
                            filePickerController.text =
                                'Download error: $error';
                          }
                        }
                      },
                      child: const Text("Read Web URL from clipboard"),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: TextFormField(
                    controller: powerController,
                    decoration: InputDecoration(
                      hintText: "Power consumption",
                      filled: true,
                      fillColor: Colors.grey.shade800,
                    ),
                    validator: (value) {
                      if (value == null) {
                        return "Value needed";
                      }
                      if (double.tryParse(value) == null) {
                        return "Expected only decimal number ex. 10.5 or 70";
                      }
                      return null;
                    },
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      tempFile = tempFile!.renameSync(
                          "${tempFile!.path.trimExtension}-"
                          "${powerController.text}${tempFile!.path.extension}");
                      var b = BuildingData(tempFile!);
                      buildingAssets[b.name] = b;
                      tempFile = null;
                      Navigator.pop(context, b.name);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Building added!')),
                      );
                    }
                  },
                  child: const Text("Submit"),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
