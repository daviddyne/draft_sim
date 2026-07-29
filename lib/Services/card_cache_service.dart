import 'dart:convert';
import 'dart:io';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:path_provider/path_provider.dart';

class CachedSet {
  final String setCode;
  final String eventType;
  final int cardCount;
  final DateTime downloaded;

  const CachedSet(this.setCode, this.eventType, this.cardCount, this.downloaded);
}

class CardCacheService {
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sets');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  String _fileName(String setCode, String eventType, {bool lands = false}) {
    return '${setCode.toUpperCase()}_$eventType${lands ? '_lands' : ''}.json';
  }

  Future<void> save(String setCode, String eventType, List<CardRating> cards, {bool lands = false}) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${_fileName(setCode, eventType, lands: lands)}');
    await file.writeAsString(jsonEncode([for (final c in cards) c.toCache()]));
  }

  Future<List<CardRating>?> load(String setCode, String eventType, {bool lands = false}) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${_fileName(setCode, eventType, lands: lands)}');
      if (!file.existsSync()) return null;
      final list = jsonDecode(await file.readAsString()) as List;
      return [for (final e in list) CardRating.fromCache(e as Map<String, dynamic>)];
    } catch (_) {
      return null;
    }
  }

  // Everything downloaded so far, for the start screen list
  Future<List<CachedSet>> listCached() async {
    final dir = await _cacheDir();
    final result = <CachedSet>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json') || name.contains('_lands')) continue;
      final parts = name.replaceAll('.json', '').split('_');
      if (parts.length < 2) continue;
      var count = 0;
      try {
        count = (jsonDecode(f.readAsStringSync()) as List).length;
      } catch (_) {
        continue;
      }
      result.add(CachedSet(parts[0], parts[1], count, f.lastModifiedSync()));
    }
    result.sort((a, b) => b.downloaded.compareTo(a.downloaded));
    return result;
  }

  Future<void> delete(String setCode, String eventType) async {
    final dir = await _cacheDir();
    for (final lands in [false, true]) {
      final file = File('${dir.path}/${_fileName(setCode, eventType, lands: lands)}');
      if (file.existsSync()) await file.delete();
    }
    final images = Directory('${dir.path}/images/${setCode.toUpperCase()}');
    if (images.existsSync()) await images.delete(recursive: true);
  }

  Future<Directory> _imageDir(String setCode) async {
    final dir = await _cacheDir();
    final images = Directory('${dir.path}/images/${setCode.toUpperCase()}');
    if (!images.existsSync()) images.createSync(recursive: true);
    return images;
  }

  // File name from the card name, so it survives Scryfall changing its urls
  String _imageName(String cardName) {
    return '${cardName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.jpg';
  }

  Future<String> imagePath(String setCode, String cardName) async {
    final dir = await _imageDir(setCode);
    return '${dir.path}/${_imageName(cardName)}';
  }

  Future<void> saveImage(String setCode, String cardName, List<int> bytes) async {
    final path = await imagePath(setCode, cardName);
    await File(path).writeAsBytes(bytes);
  }

  // Points cards at downloaded art where it exists, leaves the url otherwise
  Future<List<CardRating>> applyLocalImages(String setCode, List<CardRating> cards) async {
    final dir = Directory('${(await _cacheDir()).path}/images/${setCode.toUpperCase()}');
    if (!dir.existsSync()) return cards;
    final present = {for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last};
    return [
      for (final c in cards)
        if (present.contains(_imageName(c.name))) c.withLocalImage('${dir.path}/${_imageName(c.name)}') else c,
    ];
  }

  Future<int> imageCount(String setCode) async {
    final dir = Directory('${(await _cacheDir()).path}/images/${setCode.toUpperCase()}');
    if (!dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().length;
  }
}