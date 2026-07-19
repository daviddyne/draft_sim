import 'package:draft_sim/Logic/browse_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'draft_screen.dart';

class BrowseScreen extends StatelessWidget {
  final String setCode;
  final String eventType;

  const BrowseScreen({
    super.key,
    required this.setCode,
    required this.eventType,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          BrowseCubit(SeventeenLandsService())..load(setCode, eventType),
      child: _BrowseView(setCode: setCode),
    );
  }
}

class _BrowseView extends StatefulWidget {
  final String setCode;

  const _BrowseView({required this.setCode});

  @override
  State<_BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<_BrowseView> {
  final _searchController = TextEditingController();
  final Set<String> _colors = {};
  // Include multicolor cards that contain any selected color
  bool _multicolor = false;
  // Empty means all rarities
  final Set<String> _rarities = {};
  // Empty means all card types
  final Set<String> _types = {};
  // Minimum GIH in percent, 0 means no floor
  double _minGih = 0;
  // Cards clicked away so they don't drag the averages
  final Set<String> _excluded = {};
  RankStat _rankStat = RankStat.gihwr;
  // Same view controls as draft mode
  double _cardSize = 240;
  double _zoomSize = 350;
  bool _zoomEnabled = true;
  double _rankWidth = 420;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.setCode.toUpperCase()} card browser'),
        actions: [
          const Icon(Icons.photo_size_select_large, size: 18),
          Tooltip(
            message: 'Card size',
            child: SizedBox(
              width: 150,
              child: Slider(
                value: _cardSize,
                min: 150,
                max: 600,
                onChanged: (v) => setState(() => _cardSize = v),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle hover zoom',
            icon: Icon(
              Icons.zoom_in,
              size: 20,
              color: _zoomEnabled ? null : Theme.of(context).disabledColor,
            ),
            onPressed: () => setState(() => _zoomEnabled = !_zoomEnabled),
          ),
          Tooltip(
            message: 'Hover zoom size',
            child: SizedBox(
              width: 150,
              child: Slider(
                value: _zoomSize,
                min: 300,
                max: 900,
                onChanged: (v) => setState(() => _zoomSize = v),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: BlocBuilder<BrowseCubit, BrowseState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final filtered = _ranked(_filtered(state.cards));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText:
                              'Keyword (name, type or rules text, e.g. goblin)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    for (final c in ['W', 'U', 'B', 'R', 'G', 'C'])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(c),
                          selected: _colors.contains(c),
                          selectedColor: _manaColor(c).withValues(alpha: 0.5),
                          onSelected: (on) => setState(
                            () => on ? _colors.add(c) : _colors.remove(c),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: FilterChip(
                        label: const Text('Multi'),
                        selected: _multicolor,
                        selectedColor: const Color(
                          0xFFD4AF37,
                        ).withValues(alpha: 0.5),
                        onSelected: (on) => setState(() => _multicolor = on),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    Text('Type', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(width: 8),
                    for (final t in const [
                      'Creature',
                      'Instant',
                      'Sorcery',
                      'Artifact',
                      'Enchantment',
                      'Planeswalker',
                      'Land',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(t),
                          selected: _types.contains(t),
                          onSelected: (on) => setState(
                            () => on ? _types.add(t) : _types.remove(t),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    Text(
                      'Rarity',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 8),
                    for (final (r, label, color) in const [
                      ('common', 'Common', Color(0xFF9E9E9E)),
                      ('uncommon', 'Uncommon', Color(0xFFB0C4DE)),
                      ('rare', 'Rare', Color(0xFFD4AF37)),
                      ('mythic', 'Mythic', Color(0xFFE86A33)),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(label),
                          selected: _rarities.contains(r),
                          selectedColor: color.withValues(alpha: 0.5),
                          onSelected: (on) => setState(
                            () => on ? _rarities.add(r) : _rarities.remove(r),
                          ),
                        ),
                      ),
                    const SizedBox(width: 16),
                    Text(
                      _minGih == 0
                          ? 'Min GIH: off'
                          : 'Min GIH: ${_minGih.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SizedBox(
                      width: 200,
                      child: Slider(
                        value: _minGih,
                        min: 0,
                        max: 70,
                        onChanged: (v) => setState(() => _minGih = v),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSummary(context, filtered),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildGrid(filtered)),
                    _buildVSplitter(),
                    SizedBox(
                      width: _rankWidth,
                      child: Column(
                        children: [
                          _buildHeader(context),
                          const Divider(height: 1),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(child: Text('No cards match'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, i) =>
                                        _row(context, i + 1, filtered[i]),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Card image grid like the draft mode pack area, click toggles exclusion
  Widget _buildGrid(List<CardRating> cards) {
    if (cards.isEmpty) return const Center(child: Text('No cards match'));
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _cardSize,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final card = cards[i];
        final excluded = _excluded.contains(card.name);
        return HoverZoom(
          card: card,
          zoomWidth: _zoomSize,
          enabled: _zoomEnabled,
          child: GestureDetector(
            onTap: () => setState(
              () => excluded
                  ? _excluded.remove(card.name)
                  : _excluded.add(card.name),
            ),
            child: Opacity(
              opacity: excluded ? 0.35 : 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: cardImage(card, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      },
    );
  }

  // Drag to resize the ranking panel
  Widget _buildVSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(() {
          _rankWidth = (_rankWidth - d.delta.dx).clamp(260.0, 700.0);
        }),
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The averages are the whole point: compare goblins vs elves at a glance
  // Excluded cards stay visible but don't count
  Widget _buildSummary(BuildContext context, List<CardRating> cards) {
    final included = [
      for (final c in cards)
        if (!_excluded.contains(c.name)) c,
    ];
    final gih = _avg(included, (c) => c.gihwr);
    final iwd = _avg(included, (c) => c.iwd);
    final alsa = _avg(included, (c) => c.alsa);
    String pct(double? v) =>
        v == null ? '-' : '${(v * 100).toStringAsFixed(1)}%';
    String pp(double? v) => v == null
        ? '-'
        : '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(1)}pp';
    String num(double? v) => v == null ? '-' : v.toStringAsFixed(2);
    final excludedCount = cards.length - included.length;
    final suffix = excludedCount > 0
        ? ' ($excludedCount excluded)'
        : ' · click a card to exclude it';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        '${included.length} cards · Avg GIH ${pct(gih)} · Avg IWD ${pp(iwd)} · Avg ALSA ${num(alsa)}$suffix',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          const SizedBox(width: 30),
          Expanded(
            child: Text('Card', style: Theme.of(context).textTheme.labelLarge),
          ),
          _headerCell('GIH', RankStat.gihwr),
          _headerCell('IWD', RankStat.iwd),
          _headerCell('ALSA', RankStat.alsa),
        ],
      ),
    );
  }

  Widget _headerCell(String label, RankStat stat) {
    final selected = _rankStat == stat;
    return InkWell(
      onTap: () => setState(() => _rankStat = stat),
      child: SizedBox(
        width: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selected ? null : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int rank, CardRating card) {
    final stats = Theme.of(context).textTheme.bodySmall;
    final excluded = _excluded.contains(card.name);
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: GestureDetector(
        onTap: () => setState(
          () =>
              excluded ? _excluded.remove(card.name) : _excluded.add(card.name),
        ),
        child: Opacity(
          opacity: excluded ? 0.35 : 1,
          child: Container(
            decoration: _rowDecoration(card.color),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('$rank', style: stats)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          decoration: excluded
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        card.typeLine,
                        style: stats,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    card.gihwrLabel,
                    style: stats,
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    card.iwdLabel,
                    style: stats,
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    card.alsaLabel,
                    style: stats,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<CardRating> _filtered(List<CardRating> cards) {
    final q = _searchController.text.trim().toLowerCase();
    return cards.where((c) {
      if (q.isNotEmpty &&
          !c.name.toLowerCase().contains(q) &&
          !c.typeLine.toLowerCase().contains(q) &&
          !c.oracleText.toLowerCase().contains(q)) {
        return false;
      }
      if (_rarities.isNotEmpty && !_rarities.contains(c.rarity)) return false;
      // Match against the front face so spell//land backsides don't count as lands
      if (_types.isNotEmpty &&
          !_types.any((t) => c.typeLine.split(' // ').first.contains(t))) {
        return false;
      }
      // With a floor set, unrated cards (low sample) are dropped too
      if (_minGih > 0 && (c.gihwr == null || c.gihwr! * 100 < _minGih)) {
        return false;
      }
      // Colorless cards
      if (c.color.isEmpty) {
        if (_colors.isEmpty) return !_multicolor;
        return _colors.contains('C');
      }
      final letters = c.color.split('');
      // Multicolor toggle alone shows only multicolor cards
      if (_colors.isEmpty) return !_multicolor || letters.length > 1;
      // A card matches when all its colors are among the selected ones
      if (letters.every(_colors.contains)) return true;
      // With multicolor on, a multicolor card only needs to contain a selected color
      return _multicolor && letters.length > 1 && letters.any(_colors.contains);
    }).toList();
  }

  List<CardRating> _ranked(List<CardRating> cards) {
    final sorted = List<CardRating>.from(cards);
    sorted.sort(
      (a, b) => switch (_rankStat) {
        RankStat.gihwr => (b.gihwr ?? -1).compareTo(a.gihwr ?? -1),
        RankStat.iwd => (b.iwd ?? -9).compareTo(a.iwd ?? -9),
        RankStat.alsa => (a.alsa ?? 99).compareTo(b.alsa ?? 99),
      },
    );
    return sorted;
  }

  double? _avg(List<CardRating> cards, double? Function(CardRating) f) {
    final vals = [
      for (final c in cards)
        if (f(c) != null) f(c)!,
    ];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  BoxDecoration _rowDecoration(String color) {
    final letters = color.isEmpty ? ['C'] : color.split('');
    final colors = [
      for (final l in letters) _manaColor(l).withValues(alpha: 0.35),
    ];
    if (colors.length == 1) return BoxDecoration(color: colors.first);
    return BoxDecoration(gradient: LinearGradient(colors: colors));
  }

  Color _manaColor(String letter) {
    return switch (letter) {
      'W' => const Color(0xFFF5F0D8),
      'U' => const Color(0xFF4A90D9),
      'B' => const Color(0xFF6B5E75),
      'R' => const Color(0xFFD9534F),
      'G' => const Color(0xFF4CAF6D),
      _ => const Color(0xFF9E9E9E),
    };
  }
}
