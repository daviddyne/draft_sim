import 'dart:convert';

import 'package:draft_sim/Models/card_rating.dart';
import 'package:http/http.dart' as http;

class SeventeenLandsService {
  static const _base = 'https://www.17lands.com/api/card_data';

  // Fetches ratings for a set, e.g. fetchRatings('DSK')
  // Older sets often only have PremierDraft data, so that is the default
  Future<List<CardRating>> fetchRatings(
    String setCode, {
    String eventType = 'PremierDraft',
    String timePeriod = 'ALL_TIME',
  }) async {
    final uri = Uri.parse(
      '$_base?expansion=${setCode.toUpperCase()}&event_type=$eventType&time_period=$timePeriod',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        '17lands request failed (${response.statusCode}) for $setCode',
      );
    }
    final body = jsonDecode(response.body);
    // Response is wrapped in a "data" field
    final list = (body is Map ? body['data'] : body) as List?;
    if (list == null || list.isEmpty) {
      throw Exception('No card data for $setCode / $eventType');
    }
    final cards = list
        .map((e) => CardRating.fromJson(e as Map<String, dynamic>))
        .toList();
    // Cards without an image can't be shown in the pack grid
    return cards.where((c) => c.imageUrl.isNotEmpty).toList();
  }
}
