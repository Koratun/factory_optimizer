import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import 'string_utils.dart';
import 'item_recipe.dart';
import 'production_line.dart';

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

  void _load() {
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

  Iterable<Widget> itemList(
    BuildContext context, {
    bool returnSelection = false,
  }) {
    return itemAssets.entries.map(
      (e) => Center(
        child: SizedBox(
          width: 400,
          child: ListTile(
            onTap: () => returnSelection
                ? Navigator.pop(context, e.key)
                : Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChangeNotifierProvider.value(
                        value: this,
                        child: AssetDisplay(
                          isItem: true,
                          assetName: e.key,
                        ),
                      ),
                    ),
                  ),
            hoverColor: Colors.grey.shade700,
            leading: Image.file(e.value),
            title: Text(
              e.key,
              textWidthBasis: TextWidthBasis.longestLine,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }

  Iterable<Widget> buildingList(
    BuildContext context, {
    bool returnSelection = false,
  }) {
    return buildingAssets.values.map(
      (b) => Center(
        child: SizedBox(
          width: 400,
          child: ListTile(
            onTap: () => returnSelection
                ? Navigator.pop(context, b.name)
                : Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChangeNotifierProvider.value(
                        value: this,
                        child: AssetDisplay(
                          isItem: false,
                          assetName: b.name,
                        ),
                      ),
                    ),
                  ),
            hoverColor: Colors.grey.shade700,
            leading: Image.file(b.file),
            title: Text(
              b.name,
              textWidthBasis: TextWidthBasis.longestLine,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
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
            child: ListView(children: [
              Text(
                item ? "Select an Item" : "Select a Building",
                textAlign: TextAlign.center,
                textWidthBasis: TextWidthBasis.longestLine,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              for (var a in item
                  ? itemList(context, returnSelection: true)
                  : buildingList(context, returnSelection: true))
                a,
              Center(
                  child: item
                      ? newItemWidget(context, returnSelection: true)
                      : newBuildingWidget(context, returnSelection: true)),
            ]),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _cancelable(
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
        Positioned.directional(
          end: 0,
          width: 16,
          top: 0,
          height: 16,
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            onTap: () {
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
            child: const Icon(
              Icons.cancel,
              size: 16,
              color: Colors.red,
            ),
          ),
        )
      ],
    );
  }

  Widget _reagent(
    BuildContext context,
    void Function(void Function()) setState,
    String assetName, {
    required bool item,
    required bool outputIsItem,
    required bool input,
    required String outputName,
  }) {
    if (outputIsItem && !recipeFields.containsKey(assetName)) {
      recipeFields[assetName] = TextEditingController(text: "0");
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 8),
      child: item
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: _cancelable(
                    setState,
                    Image.file(itemAssets[assetName]!),
                    assetName,
                    item,
                    input,
                    outputName: outputName,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: 40,
                    height: 20,
                    child: TextField(
                      controller: recipeFields[assetName],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
                      ],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade800,
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (outputIsItem)
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
                    child: _cancelable(
                      setState,
                      Image.file(buildingAssets[assetName]!.file),
                      assetName,
                      item,
                      input,
                      outputName: outputName,
                    ),
                  ),
                ),
                if (outputIsItem)
                  SizedBox(
                    width: 60,
                    height: 20,
                    child: TextField(
                      controller: recipeFields[assetName],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r"\d+\.?\d*"))
                      ],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade800,
                        border: InputBorder.none,
                        isCollapsed: true,
                        suffixText: "/min",
                        suffixStyle: Theme.of(context).textTheme.labelSmall,
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
    bool outputIsItem,
  ) {
    var nameField = TextEditingController();
    newRecipe = ItemRecipe(
      [],
      [ItemAmount(outputName, outputIsItem ? 0 : 1)],
      0,
      null,
    );

    return StatefulBuilder(
      builder: (context, setState) => Dialog(
        alignment: Alignment.center,
        child: Container(
          color: Colors.grey.shade900,
          child: SizedBox(
            width: 800,
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
                                outputIsItem: outputIsItem,
                                outputName: outputName,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (outputIsItem)
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 32,
                              ),
                            if (outputIsItem && newRecipe!.building == null)
                              _addRecipeReagent(
                                context,
                                setState,
                                false,
                                true,
                                false,
                              ),
                            if (outputIsItem && newRecipe!.building != null)
                              _reagent(
                                context,
                                setState,
                                newRecipe!.building!,
                                item: false,
                                input: true,
                                outputIsItem: outputIsItem,
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
                                item: outputIsItem,
                                input: false,
                                outputIsItem: outputIsItem,
                                outputName: outputName,
                              ),
                            if (outputIsItem && newRecipe!.output.length <= 4)
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
                      if (outputIsItem && newRecipe!.building == null) {
                        _errorAlert(
                            context, "Must specify a building for the recipe.");
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
                        if ((int.tryParse(recipeFields[inp.name]!.text) ?? 0) <=
                            0) {
                          _errorAlert(context,
                              "${inp.name}: rate must be a whole number above 0.");
                          failed = true;
                        }
                      }
                      for (var o in newRecipe!.output) {
                        if ((int.tryParse(recipeFields[o.name]!.text) ?? 0) <=
                            0) {
                          _errorAlert(context,
                              "${o.name}: rate must be a whole number above 0.");
                          failed = true;
                        }
                      }
                      if (!failed) {
                        for (var inp in newRecipe!.input) {
                          inp.amount =
                              int.tryParse(recipeFields[inp.name]!.text)!;
                        }
                        for (var o in newRecipe!.output) {
                          o.amount = int.tryParse(recipeFields[o.name]!.text)!;
                        }
                        if (outputIsItem) {
                          newRecipe!.rate = double.tryParse(
                              recipeFields[newRecipe!.building!]!.text)!;
                        }
                        File("recipes/${nameField.text}.json")
                            .writeAsStringSync(
                                json.encode(newRecipe!.toJson()));
                        _registerRecipe(newRecipe!);
                        newRecipe = null;
                        recipeFields.clear();
                        Navigator.pop(context);
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
                        tempFile = null;
                        Navigator.pop(
                            context, tempFile!.path.basename.trimExtension);
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

    game._load();
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Text(
                            widget.isItem == null ? "Items" : "Recipes",
                            textAlign: TextAlign.center,
                            textWidthBasis: TextWidthBasis.longestLine,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (widget.isItem == null)
                            for (var item in game.itemList(context)) item,
                          if (widget.isItem != null &&
                              game.recipes.containsKey(widget.assetName))
                            for (var r in game.recipes[widget.assetName]!)
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: recipe(r, game),
                              ),
                          if (widget.isItem != null &&
                              (widget.isItem! ||
                                  // Buildings can only have one recipe
                                  (!widget.isItem! &&
                                      !game.recipes
                                          .containsKey(widget.assetName))))
                            newRecipeWidget(context),
                          if (widget.isItem == null)
                            Center(child: game.newItemWidget(context)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Text(
                            widget.isItem == null ? "Buildings" : "Uses",
                            textAlign: TextAlign.center,
                            textWidthBasis: TextWidthBasis.longestLine,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (widget.isItem == null)
                            for (var b in game.buildingList(context)) b,
                          if (widget.isItem != null &&
                              game.uses.containsKey(widget.assetName))
                            for (var r in game.uses[widget.assetName]!)
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: recipe(r, game),
                              ),
                          if (widget.isItem == null)
                            Center(child: game.newBuildingWidget(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
      width: 400,
      height: 150,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChangeNotifierProvider.value(
              value: game,
              child: FactoryOverview(
                [r],
                selectedRecipe: r,
                itemName: widget.assetName!,
              ),
            ),
          ),
        ),
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
                              inp.amount.toString(),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
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
                                o.amount.toString(),
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
      child: Container(
        color: Colors.grey.shade800,
        child: SizedBox(
          height: 150,
          width: 400,
          child: InkWell(
            onTap: () => showDialog(
              context: context,
              builder: (context) => game.newRecipeDialog(
                context,
                widget.assetName!,
                widget.isItem!,
              ),
            ),
            hoverColor: Colors.grey.shade700,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }
}
