import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

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
      home: Center(
        child: ListView(
          children: [
            Text(
              "Factory Optimizer",
              style: Theme.of(context).textTheme.displayLarge,
            ),
            Text(
              "Select Game Profile:",
              style: Theme.of(context).textTheme.displaySmall,
            ),
            SizedBox(
              width: 400,
              height: 100,
              child: ListTile(
                leading: const Icon(
                  Icons.add,
                  color: Colors.white,
                ),
                title: Text(
                  "Add New Profile",
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                onTap: () async {
                  showDialog(context: context, builder: (context){
                    Dialog(alignment: Alignment.center, child: TextField(autofocus: true, ),)
                  });


                  FilePickerResult? result =
                      await FilePicker.platform.pickFiles(type: FileType.image);
                  if (result != null) {
                    File file = File(result.files.first.path!);

                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
