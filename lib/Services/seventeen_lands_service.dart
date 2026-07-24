import 'dart:convert';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:http/http.dart' as http;
import 'scryfall_service.dart';

class SetOption {
  final String code;
  final String name;

  const SetOption(this.code, this.name);
}

class SeventeenLandsService {
  static const _base = 'https://www.17lands.com/api/card_data';
  final ScryfallService _scryfall = ScryfallService();

  // Fetches ratings for a set, e.g. fetchRatings('MSH')
  // Older sets often only have PremierDraft data, so that is the default
  Future<List<CardRating>> fetchRatings(
    String setCode, {
    String eventType = 'PremierDraft',
    String timePeriod = 'ALL_TIME',
  }) async {
    final uri = Uri.parse('$_base?expansion=${setCode.toUpperCase()}&event_type=$eventType&time_period=$timePeriod');
    final response = await http.get(uri);
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
  Future<List<CardRating>> fetchBasicLands(String setCode) async {
    final lands = await _scryfall.fetchBasicLands(setCode);
    return [
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
  }

  // Set list for the start screen dropdown, full names come from Scryfall
  Future<List<SetOption>> fetchSets() async {
    final response = await http.get(Uri.parse('https://www.17lands.com/data/expansions'));
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