import 'dart:convert';
import 'package:http/http.dart' as http;

class ScryfallService {
  // Scryfall rejects requests without a proper user agent
  static const _headers = {'User-Agent': 'DraftSim/1.0', 'Accept': 'application/json'};

  // Returns card name -> (mana value, type line, oracle text, image url, arena id) for a whole set
  // Arena printings carry the arena ids, plain printings fill in cards missing from Arena
  Future<Map<String, (int, String, String, String, int?)>> fetchSetInfo(String setCode) async {
    final map = <String, (int, String, String, String, int?)>{};
    for (final q in ['set:spg game:arena', 'set:$setCode', 'set:$setCode game:arena']) {
      await _addSet(map, q);
    }
    return map;
  }

  Future<void> _addSet(Map<String, (int, String, String, String, int?)> map, String query) async {
    var url = 'https://api.scryfall.com/cards/search?q=${Uri.encodeQueryComponent(query)}&unique=cards';
    while (true) {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) break;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      for (final card in (body['data'] as List? ?? [])) {
        final cmc = (card['cmc'] as num?)?.toInt() ?? 0;
        final type = (card['type_line'] ?? '') as String;
        // Multi faced cards keep their rules text and images on the faces
        var oracle = card['oracle_text'] as String? ?? '';
        var img = (card['image_uris']?['normal'] ?? '') as String;
        final faces = card['card_faces'] as List? ?? [];
        if (oracle.isEmpty) {
          oracle = [for (final f in faces) (f['oracle_text'] ?? '') as String].join('\n');
        }
        if (img.isEmpty && faces.isNotEmpty) {
          img = (faces.first['image_uris']?['normal'] ?? '') as String;
        }
        final arenaId = (card['arena_id'] as num?)?.toInt();
        final fullName = card['name'] as String;
        // 17lands uses the front face name for double faced cards
        final front = fullName.split(' // ').first;
        map[fullName] = (cmc, type, oracle, img, arenaId);
        map[front] = (cmc, type, oracle, img, arenaId);
        map[fullName.toLowerCase()] = (cmc, type, oracle, img, arenaId);
        map[front.toLowerCase()] = (cmc, type, oracle, img, arenaId);
      }
      if (body['has_more'] == true && body['next_page'] != null) {
        url = body['next_page'];
      } else {
        break;
      }
    }
  }

  // Returns set code (uppercase) -> full set name
  Future<Map<String, String>> fetchSetNames() async {
    final map = <String, String>{};
    var url = 'https://api.scryfall.com/sets';
    while (true) {
      final response = await http.get(Uri.parse(url), headers: _headers);
      if (response.statusCode != 200) break;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      for (final s in (body['data'] as List? ?? [])) {
        map[(s['code'] as String).toUpperCase()] = s['name'] as String;
      }
      if (body['has_more'] == true && body['next_page'] != null) {
        url = body['next_page'];
      } else {
        break;
      }
    }
    return map;
  }
}