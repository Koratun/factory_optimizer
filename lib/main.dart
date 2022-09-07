import 'dart:io';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';

late final String rootDir;

extension StringUtil on String {
  String basename() => substring(lastIndexOf('\\') + 1);

  String trimExtension() => substring(0, lastIndexOf('.'));

  String extension() => substring(lastIndexOf("."));
}

void main() {
  rootDir = Directory.current.path;
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final List<File> profileData = [];

  void loadProfiles() async {
    await for (FileSystemEntity d in Directory("data").list()) {
      if (d is Directory) {
        await for (FileSystemEntity f in d.list()) {
          if (f is File) {
            if (f.path.basename().trimExtension() == d.path.basename()) {
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Factory Optimizer",
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Text(
                  "Select Game Profile:",
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                for (File f in profileData)
                  SizedBox(
                    width: 400,
                    child: ListTile(
                      leading: Image.file(f),
                      title: Text(
                        f.path.basename().trimExtension(),
                        textWidthBasis: TextWidthBasis.longestLine,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                newProfileWidget(context),
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
        onTap: () async {
          String? name = await showDialog<String>(
            context: context,
            builder: (context) {
              return Dialog(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 200,
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Enter game name",
                      filled: true,
                      fillColor: Colors.grey.shade800,
                    ),
                    onSubmitted: (s) => Navigator.pop(context, s),
                  ),
                ),
              );
            },
          );

          if (name != null) {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ["exe", "png", "bmp", "jpeg", "svg"],
            );
            Directory.current = rootDir;
            if (result != null) {
              File file = File(result.files.first.path!);
              Directory("data\\$name").createSync(recursive: true);
              String ext = file.path.extension();
              String iconPath = "data\\$name\\$name$ext";
              File f;
              if (ext == ".exe") {
                var p = await Process.start(
                  ".venv\\Scripts\\python.exe",
                  [
                    "lib\\icon_extractor.py",
                    file.path,
                    iconPath.trimExtension()
                  ],
                );
                debugPrint("exe icon conversion "
                    "completion code: ${await p.exitCode}");
                f = File("${iconPath.trimExtension()}.png");
              } else {
                f = file.copySync(iconPath);
              }
              setState(() => profileData.add(f));
            }
          }
        },
      ),
    );
  }
}
