import 'dart:io';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart';

const String rootDir = "./Factory Optimizer";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

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
                        fillColor: Colors.grey.shade700,
                      ),
                      onSubmitted: (s) => Navigator.pop(context, s),
                    ),
                  ),
                );
              });

          if (name != null) {
            FilePickerResult? result =
                await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null) {
              File file = File(result.files.first.path!);
              Directory("$rootDir/$name").createSync(recursive: true);
              file.copySync("$rootDir/$name/profile${extension(file.path)}");
            }
          }
        },
      ),
    );
  }
}
