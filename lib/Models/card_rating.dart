class CardRating {
  final String name;
  final String color;
  final String rarity;
  final String imageUrl;
  final double? gihwr;
  final double? iwd;
  final double? alsa;
  // Filled from Scryfall since 17lands doesn't provide cost, type or rules text
  final int cmc;
  final String typeLine;
  final String oracleText;
  // Arena grp id, used to match cards from the Arena log
  final int? arenaId;

  CardRating({
    required this.name,
    required this.color,
    required this.rarity,
    required this.imageUrl,
    this.gihwr,
    this.iwd,
    this.alsa,
    this.cmc = 0,
    this.typeLine = '',
    this.oracleText = '',
    this.arenaId,
  });

  factory CardRating.fromJson(Map<String, dynamic> json) {
    return CardRating(
      name: json['name'] ?? '',
      color: json['color'] ?? '',
      rarity: json['rarity'] ?? '',
      imageUrl: json['url'] ?? '',
      gihwr: (json['ever_drawn_win_rate'] as num?)?.toDouble(),
      iwd: (json['drawn_improvement_win_rate'] as num?)?.toDouble(),
      alsa: (json['avg_seen'] as num?)?.toDouble(),
    );
  }

  // Cache format, keeps the fields merged in from Scryfall as well
  factory CardRating.fromCache(Map<String, dynamic> json) {
    return CardRating(
      name: json['name'] ?? '',
      color: json['color'] ?? '',
      rarity: json['rarity'] ?? '',
      imageUrl: json['image'] ?? '',
      gihwr: (json['gihwr'] as num?)?.toDouble(),
      iwd: (json['iwd'] as num?)?.toDouble(),
      alsa: (json['alsa'] as num?)?.toDouble(),
      cmc: (json['cmc'] as num?)?.toInt() ?? 0,
      typeLine: json['type'] ?? '',
      oracleText: json['oracle'] ?? '',
      arenaId: (json['arenaId'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toCache() {
    return {
      'name': name,
      'color': color,
      'rarity': rarity,
      'image': imageUrl,
      'gihwr': gihwr,
      'iwd': iwd,
      'alsa': alsa,
      'cmc': cmc,
      'type': typeLine,
      'oracle': oracleText,
      'arenaId': arenaId,
    };
  }

  CardRating withInfo(int cmc, String typeLine, String oracleText, String freshImageUrl, int? arenaId) {
    return CardRating(
      name: name,
      color: color,
      rarity: rarity,
      // Scryfall image links rotate, so a freshly fetched one beats the stored 17lands one
      imageUrl: freshImageUrl.isNotEmpty ? freshImageUrl : imageUrl,
      gihwr: gihwr,
      iwd: iwd,
      alsa: alsa,
      cmc: cmc,
      typeLine: typeLine,
      oracleText: oracleText,
      arenaId: arenaId,
    );
  }

  // Double faced cards get their front face type
  String get _frontType => typeLine.split(' // ').first;

  bool get isLand => _frontType.contains('Land');

  bool get isCreature => _frontType.contains('Creature');

  // Curve column, everything at 7 or more shares one pile
  int get costBucket => cmc >= 7 ? 7 : cmc;

  // 0.55 -> "55.0%"
  String get gihwrLabel => gihwr == null ? '-' : '${(gihwr! * 100).toStringAsFixed(1)}%';

  // 0.012 -> "+1.2pp"
  String get iwdLabel {
    if (iwd == null) return '-';
    final pp = iwd! * 100;
    final sign = pp >= 0 ? '+' : '';
    return '$sign${pp.toStringAsFixed(1)}pp';
  }

  String get alsaLabel => alsa == null ? '-' : alsa!.toStringAsFixed(2);
}