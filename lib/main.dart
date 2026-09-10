import 'package:doc_parser/slice1.dart';
import 'package:doc_parser/slice2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      home: BlocProvider(
        create: (context) => AiCubit(),
        // child: const MyHomePage(title: 'Flutter Demo Home Page'),
        child: const Slice2Home(title: 'Flutter Demo Home Page'),
      ),
    );
  }
}
