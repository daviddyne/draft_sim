class CardRating {
  final String name;
  final String color;
  final String rarity;
  final String imageUrl;
  final double? gihwr;
  final double? iwd;
  final double? alsa;

  CardRating({
    required this.name,
    required this.color,
    required this.rarity,
    required this.imageUrl,
    this.gihwr,
    this.iwd,
    this.alsa,
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