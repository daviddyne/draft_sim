import 'dart:convert';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/scryfall_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class SetOption {
  final String code;
  final String name;
  final String released;
  // Formats this set has data for, empty means all are worth trying
  final List<String> events;

  const SetOption(this.code, this.name, this.released, {this.events = const []});
}

class SeventeenLandsService {
  // Why the last pair fetch came back empty, shown in the app so a missing
  // file or a bad path doesn't just look like missing data
  static String lastPairNote = '';
  static const pairs = ['WU', 'WB', 'WR', 'WG', 'UB', 'UR', 'UG', 'BR', 'BG', 'RG'];
  static const _base = 'https://www.17lands.com/api/card_data';
  static const _expansions = 'https://www.17lands.com/data/expansions';
  // 17lands sends no CORS header, so web builds read data committed next to the
  // app instead. A GitHub Action refreshes those files daily.
  // A proxy can be used instead: --dart-define=PROXY=https://...
  static const _proxy = String.fromEnvironment('PROXY');
  static const _dataBase = String.fromEnvironment('DATA_BASE', defaultValue: 'data');
  static const _timeout = Duration(seconds: 20);
  final ScryfallService _scryfall = ScryfallService();
  final CardCacheService cache = CardCacheService();

  // True when data comes from files next to the app instead of live apis
  static bool get _static => kIsWeb && _proxy.isEmpty;

  // Wraps a url in the proxy when running in a browser
  static Uri _url(String target) {
    if (!kIsWeb || _proxy.isEmpty) return Uri.parse(target);
    return Uri.parse('$_proxy?url=${Uri.encodeQueryComponent(target)}');
  }

  // On web without a proxy the data comes from the app's own files
  // colors filters the ratings to decks of that pair, e.g. WU
  static Uri _cardDataUrl(String setCode, String eventType, String timePeriod, {String colors = ''}) {
    final suffix = colors.isEmpty ? '' : '&colors=$colors';
    final live = '$_base?expansion=${setCode.toUpperCase()}&event_type=$eventType&time_period=$timePeriod$suffix';
    if (_static) {
      // Pair files are only built for Premier Draft, they barely differ by format
      if (colors.isNotEmpty) {
        return Uri.parse('$_dataBase/${setCode.toUpperCase()}_PremierDraft_$colors.json');
      }
      return Uri.parse('$_dataBase/${setCode.toUpperCase()}_$eventType.json');
    }
    return _url(live);
  }

  // Card name to win rate for decks of one color pair, empty when unavailable
  Future<Map<String, double>> fetchPairRatings(String setCode, String eventType, String colors) async {
    try {
      // Kept once fetched, they are small and never change for a finished set
      final stored = cache.loadPairRatings(setCode, eventType, colors);
      if (stored != null && stored.isNotEmpty) return stored;
      final uri = _cardDataUrl(setCode, eventType, 'ALL_TIME', colors: colors);
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        lastPairNote = '$uri returned ${response.statusCode}';
        return const {};
      }
      final body = jsonDecode(response.body);
      final list = (body is Map ? body['data'] : body) as List?;
      if (list == null) return const {};
      final out = <String, double>{};
      for (final e in list) {
        final row = e as Map<String, dynamic>;
        final name = (row['name'] ?? '') as String;
        // Prebuilt files use the cache field names, the live api its own
        final wr = (row['ever_drawn_win_rate'] ?? row['gihwr']) as num?;
        if (name.isNotEmpty && wr != null) out[name] = wr.toDouble();
      }
      if (out.isNotEmpty) {
        await cache.savePairRatings(setCode, eventType, colors, out);
      } else {
        lastPairNote = '$uri had no ratings';
      }
      return out;
    } catch (e) {
      lastPairNote = 'pair fetch failed: $e';
      return const {};
    }
  }

  static Uri _expansionsUrl() {
    if (_static) return Uri.parse('$_dataBase/sets.json');
    return _url(_expansions);
  }

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
    // On web the data is prebuilt and already merged, so no api calls are made
    if (_static) {
      final response = await http.get(_cardDataUrl(setCode, eventType, timePeriod)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw Exception('No data for $setCode / $eventType');
      }
      final list = jsonDecode(response.body) as List;
      return [for (final e in list) CardRating.fromCache(e as Map<String, dynamic>)];
    }
    final uri = _cardDataUrl(setCode, eventType, timePeriod);
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
    if (_static) {
      final response = await http.get(Uri.parse('$_dataBase/${setCode.toUpperCase()}_lands.json')).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final list = jsonDecode(response.body) as List;
      return [for (final e in list) CardRating.fromCache(e as Map<String, dynamic>)];
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
    // Pair ratings too, otherwise the pair table is empty offline
    for (final pair in pairs) {
      await fetchPairRatings(setCode, eventType, pair);
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
    final response = await http.get(_expansionsUrl()).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Could not load the 17lands set list');
    }
    if (_static) {
      final list = jsonDecode(response.body) as List;
      return [
        for (final e in list)
          SetOption(
            e['code'] as String,
            (e['name'] ?? e['code']) as String,
            (e['released'] ?? '') as String,
            events: [for (final v in (e['events'] as List? ?? [])) v as String],
          ),
      ];
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