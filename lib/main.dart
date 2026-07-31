import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/storage_persist_stub.dart'
    if (dart.library.js_interop) 'package:draft_sim/Services/storage_persist_web.dart';
import 'package:draft_sim/UI/draft_screen.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opens the local stores before anything reads a downloaded set
  await CardCacheService.init();
  // On web, asks the browser to keep downloads instead of clearing them
  await requestPersistentStorage();
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