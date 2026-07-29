import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/UI/draft_screen.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opens the local stores before anything reads a downloaded set
  await CardCacheService.init();
  runApp(const DraftSimApp());
}

class DraftSimApp extends StatelessWidget {
  const DraftSimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '17lands Draft Sim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark),
      home: const DraftScreen(),
    );
  }
}