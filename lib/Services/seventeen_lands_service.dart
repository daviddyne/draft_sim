import 'dart:convert';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/scryfall_service.dart';
import 'package:http/http.dart' as http;

class SetOption {
  final String code;
  final String name;
  final String released;

  const SetOption(this.code, this.name, this.released);
}

class SeventeenLandsService {
  static const _base = 'https://www.17lands.com/api/card_data';
  static const _timeout = Duration(seconds: 20);
  final ScryfallService _scryfall = ScryfallService();
  final CardCacheService cache = CardCacheService();

  // A downloaded set is used as is, even online, so ratings only change when
  // the set is updated on purpose. Without a download it goes to the network.
  Future<List<CardRating>> fetchRatings(
    String setCode,
    {String eventType = 'PremierDraft',
    String timePeriod = 'ALL_TIME',
    bool save = false}) async {
    final stored = await cache.load(setCode, eventType);
    if (stored != null && stored.isNotEmpty) return stored;
    try {
      final cards = await _fetchOnline(setCode, eventType, timePeriod);
      if (save) await cache.save(setCode, eventType, cards);
      return cards;
    } catch (e) {
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
    if (!save) {
      final stored = await cache.load(setCode, eventType, lands: true);
      if (stored != null && stored.isNotEmpty) return stored;
    }
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
  }

  // Downloads a set for offline use, including card images
  // onProgress reports downloaded images out of the total
  Future<int> downloadSet(String setCode, String eventType, {void Function(int done, int total)? onProgress}) async {
    final cards = await _fetchOnline(setCode, eventType, 'ALL_TIME');
    await cache.save(setCode, eventType, cards);
    var lands = <CardRating>[];
    try {
      lands = await fetchBasicLands(setCode, eventType: eventType, save: true);
    } catch (_) {
      // Lands are optional, the set itself is what matters
    }
    await _downloadImages(setCode, [...cards, ...lands], onProgress);
    return cards.length;
  }

  // Fetches art a few at a time, missing images just stay missing
  // Art already on disk is kept, only stats are refreshed on an update
  Future<void> _downloadImages(String setCode, List<CardRating> cards, void Function(int, int)? onProgress) async {
    final todo = <CardRating>[];
    for (final c in cards) {
      if (!c.imageUrl.startsWith('http')) continue;
      if (cache.hasImage(c.name)) continue;
      todo.add(c);
    }
    var done = 0;
    const batch = 6;
    for (var i = 0; i < todo.length; i += batch) {
      final slice = todo.skip(i).take(batch);
      await Future.wait([
        for (final card in slice)
          () async {
            try {
              final r = await http.get(Uri.parse(card.imageUrl)).timeout(_timeout);
              if (r.statusCode == 200) await cache.saveImage(card.name, r.bodyBytes);
            } catch (_) {
              // One missing image shouldn't stop the download
            }
            done++;
            onProgress?.call(done, todo.length);
          }(),
      ]);
    }
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
    final options = [
      for (final code in codes)
        SetOption(code, names[code.toUpperCase()]?.$1 ?? code, names[code.toUpperCase()]?.$2 ?? ''),
    ];
    // Newest first, sets without a known date fall to the bottom
    options.sort((a, b) => b.released.compareTo(a.released));
    return options;
  }
}