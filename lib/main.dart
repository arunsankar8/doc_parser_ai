import 'package:doc_parser/slice2/slice2.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      // Slice2Home provides its own DocumentCubit internally — no
      // BlocProvider needed here.
      home: const Slice2Home(title: 'Flutter Demo Home Page'),
    );
  }
}
