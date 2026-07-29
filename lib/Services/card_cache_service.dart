import 'dart:convert';
import 'dart:typed_data';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:hive_ce_flutter/adapters.dart';


class CachedSet {
  final String setCode;
  final String eventType;
  final int cardCount;
  final DateTime downloaded;

  const CachedSet(this.setCode, this.eventType, this.cardCount, this.downloaded);
}

// Stores downloaded sets in Hive, which is files on desktop and IndexedDB on web
class CardCacheService {
  static const _setsBox = 'sets';
  static const _imagesBox = 'images';
  static const _metaBox = 'meta';

  // Call once at startup before any cache use
  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<String>(_setsBox),
      Hive.openBox<Uint8List>(_imagesBox),
      Hive.openBox<String>(_metaBox),
    ]);
  }

  Box<String> get _sets => Hive.box<String>(_setsBox);
  Box<Uint8List> get _images => Hive.box<Uint8List>(_imagesBox);
  Box<String> get _meta => Hive.box<String>(_metaBox);

  String _key(String setCode, String eventType, {bool lands = false}) {
    return '${setCode.toUpperCase()}_$eventType${lands ? '_lands' : ''}';
  }

  // Image key from the card name, so it survives Scryfall changing its urls
  // Names are unique enough across sets, and reprints share the same art anyway
  String imageKey(String cardName) {
    return cardName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> save(String setCode, String eventType, List<CardRating> cards, {bool lands = false}) async {
    await _sets.put(_key(setCode, eventType, lands: lands), jsonEncode([for (final c in cards) c.toCache()]));
    if (!lands) {
      await _meta.put(_key(setCode, eventType), DateTime.now().toIso8601String());
    }
  }

  Future<List<CardRating>?> load(String setCode, String eventType, {bool lands = false}) async {
    final raw = _sets.get(_key(setCode, eventType, lands: lands));
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return [for (final e in list) CardRating.fromCache(e as Map<String, dynamic>)];
    } catch (_) {
      return null;
    }
  }

  // Everything downloaded so far, for the start screen list
  Future<List<CachedSet>> listCached() async {
    final result = <CachedSet>[];
    for (final key in _sets.keys.cast<String>()) {
      if (key.endsWith('_lands')) continue;
      final parts = key.split('_');
      if (parts.length < 2) continue;
      var count = 0;
      try {
        count = (jsonDecode(_sets.get(key)!) as List).length;
      } catch (_) {
        continue;
      }
      final when = DateTime.tryParse(_meta.get(key) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      result.add(CachedSet(parts[0], parts[1], count, when));
    }
    result.sort((a, b) => b.downloaded.compareTo(a.downloaded));
    return result;
  }

  // Removes the set and the art of the cards it contains
  Future<void> delete(String setCode, String eventType) async {
    final cards = await load(setCode, eventType) ?? const <CardRating>[];
    final lands = await load(setCode, eventType, lands: true) ?? const <CardRating>[];
    await _images.deleteAll([for (final c in [...cards, ...lands]) imageKey(c.name)]);
    await _sets.delete(_key(setCode, eventType));
    await _sets.delete(_key(setCode, eventType, lands: true));
    await _meta.delete(_key(setCode, eventType));
  }

  bool hasImage(String cardName) => _images.containsKey(imageKey(cardName));

  Uint8List? image(String cardName) => _images.get(imageKey(cardName));

  Future<void> saveImage(String cardName, Uint8List bytes) async {
    await _images.put(imageKey(cardName), bytes);
  }
}