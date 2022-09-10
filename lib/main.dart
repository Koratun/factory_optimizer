import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import 'string_utils.dart';
import 'profile.dart';

late final String rootDir;

void main() {
  if (Directory.current.parent.parent.path.basename == "factory_optimizer") {
    Directory.current = Directory.current.parent.parent;
  }
  rootDir = Directory.current.path;
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _formKey = GlobalKey<FormState>();

  final List<File> profileData = [];
  File? tempFile;

  void loadProfiles() async {
    await for (FileSystemEntity d in Directory("data").list()) {
      if (d is Directory) {
        await for (FileSystemEntity f in d.list()) {
          if (f is File) {
            if (f.path.basename.trimExtension == d.path.basename) {
              setState(() => profileData.add(f));
              break;
            }
          }
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (Directory("data").existsSync()) {
      loadProfiles();
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Factory Optimizer',
      theme: ThemeData(
        canvasColor: Colors.black,
        textTheme: Typography.whiteRedmond,
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ListView(
              children: [
                Text(
                  "Factory Optimizer",
                  textAlign: TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(
                  "Select Game Profile:",
                  textAlign: TextAlign.center,
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                for (File f in profileData)
                  Center(
                    child: SizedBox(
                      width: 400,
                      child: ListTile(
                        hoverColor: Colors.grey.shade900,
                        leading: Image.file(f),
                        title: Text(
                          f.path.basename.trimExtension,
                          textWidthBasis: TextWidthBasis.longestLine,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                GameProfile(f.path.basename.trimExtension, f),
                          ),
                        ),
                      ),
                    ),
                  ),
                Center(child: newProfileWidget(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _newProfileDialog(BuildContext context) {
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
                    hintText: "Enter game name",
                    filled: true,
                    fillColor: Colors.grey.shade800,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Value needed";
                    }
                    if (profileData
                        .map((e) => value == e.path.basename.trimExtension)
                        .contains(true)) {
                      return "Name taken";
                    }
                    Directory("data\\$value").createSync();
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
                        if (!Directory("data\\$t").existsSync()) {
                          return null;
                        }
                        var f = tempFile!.copySync(
                            "data\\$t\\$t${tempFile!.path.extension}");
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
                        if (Directory("data\\$t").existsSync() &&
                            !File("data\\$t\\$t${tempFile!.path.extension}")
                                .existsSync()) {
                          var f = tempFile!.copySync(
                              "data\\$t\\$t${tempFile!.path.extension}");
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
                        FilePickerResult? result =
                            await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: [
                            "exe",
                            "png",
                            "bmp",
                            "jpeg",
                            "svg"
                          ],
                        );
                        Directory.current = rootDir;
                        if (result != null) {
                          tempFile = File(result.files.first.path!);
                          filePickerController.text = result.files.first.path!;
                          String ext = tempFile!.path.extension;
                          String iconPath = "data\\temp";
                          if (ext == ".exe") {
                            var p = await Process.start(
                              ".venv\\Scripts\\python.exe",
                              [
                                "lib\\icon_extractor.py",
                                tempFile!.path,
                                iconPath
                              ],
                            );
                            debugPrint("exe icon conversion "
                                "completion code: ${await p.exitCode}");
                            tempFile = File("$iconPath.png");
                          } else {
                            tempFile = tempFile!.copySync("$iconPath$ext");
                          }
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

                            File file = File("data\\temp");
                            await file.writeAsBytes(bytes);
                            String? mime = lookupMimeType(
                              "data\\temp",
                              headerBytes: bytes.take(2).toList(),
                            );
                            if (mime == null) {
                              tempFile = null;
                              filePickerController.text =
                                  "Could not verify file extension";
                              file.deleteSync();
                              return;
                            }
                            tempFile =
                                file.renameSync("data\\temp.${mime.basename}");
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
                        setState(() => profileData.add(tempFile!));
                        tempFile = null;
                        nameController.dispose();
                        filePickerController.dispose();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile added!')),
                        );
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

  Widget newProfileWidget(BuildContext context) {
    return SizedBox(
      width: 400,
      child: ListTile(
        hoverColor: Colors.grey.shade900,
        leading: const Icon(
          Icons.add,
          color: Colors.white,
        ),
        title: Text(
          "Add New Profile",
          textWidthBasis: TextWidthBasis.longestLine,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        onTap: () {
          showDialog<String>(
            context: context,
            builder: (context) => _newProfileDialog(context),
          );
          tempFile = null;
        },
      ),
    );
  }
}
