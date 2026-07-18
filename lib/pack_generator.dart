import 'dart:math';
import 'package:draft_sim/Models/card_rating.dart';


class PackGenerator {
  final List<CardRating> commons;
  final List<CardRating> uncommons;
  final List<CardRating> rares;
  final List<CardRating> mythics;
  final Random _random = Random();

  PackGenerator(List<CardRating> allCards)
      : commons = allCards.where((c) => c.rarity == 'common').toList(),
        uncommons = allCards.where((c) => c.rarity == 'uncommon').toList(),
        rares = allCards.where((c) => c.rarity == 'rare').toList(),
        mythics = allCards.where((c) => c.rarity == 'mythic').toList();

  // 14 cards: 1 rare/mythic, 3 uncommons, 10 commons
  // Close enough to real collation for pick training
  List<CardRating> generatePack() {
    final pack = <CardRating>[];
    if (mythics.isNotEmpty && _random.nextInt(7) == 0) {
      pack.add(mythics[_random.nextInt(mythics.length)]);
    } else if (rares.isNotEmpty) {
      pack.add(rares[_random.nextInt(rares.length)]);
    }
    pack.addAll(_pickUnique(uncommons, 3));
    pack.addAll(_pickUnique(commons, 10));
    return pack;
  }

  // Shuffle a copy and take the first cards so a pack never has duplicates
  List<CardRating> _pickUnique(List<CardRating> pool, int count) {
    final copy = List<CardRating>.from(pool)..shuffle(_random);
    return copy.take(min(count, copy.length)).toList();
  }
}