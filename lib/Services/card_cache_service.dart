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
  }
}