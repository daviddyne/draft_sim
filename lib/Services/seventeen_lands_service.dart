import 'dart:convert';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/scryfall_service.dart';
import 'package:http/http.dart' as http;

class SetOption {
  final String code;
  final String name;

  const SetOption(this.code, this.name);
}

class SeventeenLandsService {
  static const _base = 'https://www.17lands.com/api/card_data';
  static const _timeout = Duration(seconds: 20);
  final ScryfallService _scryfall = ScryfallService();
  final CardCacheService cache = CardCacheService();

  // Uses the network when it can, falls back to a downloaded copy when offline
  Future<List<CardRating>> fetchRatings(
    String setCode,
    {String eventType = 'PremierDraft',
    String timePeriod = 'ALL_TIME',
    bool save = false}) async {
    try {
      final cards = await _fetchOnline(setCode, eventType, timePeriod);
      if (save) await cache.save(setCode, eventType, cards);
      return cards;
    } catch (e) {
      final cached = await cache.load(setCode, eventType);
      if (cached != null && cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<CardRating>> _fetchOnline(String setCode, String eventType, String timePeriod) async {
    final uri = Uri.parse('$_base?expansion=${setCode.toUpperCase()}&event_type=$eventType&time_period=$timePeriod');
    final response = await http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('17lands request failed (${response.statusCode}) for $setCode');
    }
    final body = jsonDecode(response.body);
    // Response is wrapped in a "data" field
    final list = (body is Map ? body['data'] : body) as List?;
    if (list == null || list.isEmpty) {
      throw Exception('No card data for $setCode / $eventType');
    }
    final cards = list.map((e) => CardRating.fromJson(e as Map<String, dynamic>)).toList();
    // Merge in cost and type so the pool can be laid out as a curve
    final info = await _scryfall.fetchSetInfo(setCode);
    final merged = [
      for (final c in cards)
        if ((info[c.name] ?? info[c.name.toLowerCase()]) case final i?) c.withInfo(i.$1, i.$2, i.$3, i.$4, i.$5) else c,
    ];
    // Cards without an image can't be shown in the pack grid
    return merged.where((c) => c.imageUrl.isNotEmpty).toList();
  }

  // Basic lands as rating-less cards, so pack land slots can be shown
  Future<List<CardRating>> fetchBasicLands(String setCode, {String eventType = 'PremierDraft', bool save = false}) async {
    try {
      final lands = await _scryfall.fetchBasicLands(setCode);
      final cards = [
        for (final (name, img, id) in lands)
          CardRating(
            name: name,
            color: '',
            rarity: 'basic',
            imageUrl: img,
            typeLine: 'Basic Land',
            arenaId: id,
          ),
      ];
      if (save) await cache.save(setCode, eventType, cards, lands: true);
      return cards;
    } catch (e) {
      final cached = await cache.load(setCode, eventType, lands: true);
      if (cached != null) return cached;
      rethrow;
    }
  }

  // Downloads a set for offline use, returns how many cards were stored
  Future<int> downloadSet(String setCode, String eventType) async {
    final cards = await _fetchOnline(setCode, eventType, 'ALL_TIME');
    await cache.save(setCode, eventType, cards);
    try {
      await fetchBasicLands(setCode, eventType: eventType, save: true);
    } catch (_) {
      // Lands are optional, the set itself is what matters
    }
    return cards.length;
  }

  // Set list for the start screen dropdown, full names come from Scryfall
  Future<List<SetOption>> fetchSets() async {
    final response = await http.get(Uri.parse('https://www.17lands.com/data/expansions')).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Could not load the 17lands set list');
    }
    final body = jsonDecode(response.body);
    final codes = (body is List ? body : body['expansions'] as List).cast<String>();
    final names = await _scryfall.fetchSetNames();
    return [
      for (final code in codes) SetOption(code, names[code.toUpperCase()] ?? code),
    ];
  }
}