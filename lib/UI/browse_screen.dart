import 'package:draft_sim/Logic/browse_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'draft_screen.dart';

const allTypes = ['Creature', 'Instant', 'Sorcery', 'Artifact', 'Enchantment', 'Planeswalker', 'Land', 'Battle'];
const allRarities = [
  ('common', 'Common', Color(0xFF9E9E9E)),
  ('uncommon', 'Uncommon', Color(0xFFB0C4DE)),
  ('rare', 'Rare', Color(0xFFD4AF37)),
  ('mythic', 'Mythic', Color(0xFFE86A33)),
];

class BrowseScreen extends StatelessWidget {
  final String setCode;
  final String eventType;

  const BrowseScreen({super.key, required this.setCode, required this.eventType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BrowseCubit(SeventeenLandsService())..load(setCode, eventType),
      child: _BrowseView(setCode: setCode, eventType: eventType),
    );
  }
}

class _BrowseView extends StatefulWidget {
  final String setCode;
  final String eventType;

  const _BrowseView({required this.setCode, required this.eventType});

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
  // All filter rows can be collapsed to leave more room for cards
  bool _showFilters = true;
  // Deck being built from the browsed cards
  final List<CardRating> _deck = [];
  final List<CardRating> _side = [];
  double _bottomHeight = 320;
  double _deckSplit = 0.6;
  // Width split between the deck and the sideboard below
  double _sideSplit = 0.7;
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
          IconButton(
            tooltip: _showFilters ? 'Hide filters' : 'Show filters',
            icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_off),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          IconButton(
            tooltip: 'Draft this set',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DraftScreen(setCode: widget.setCode, eventType: widget.eventType),
            )),
          ),
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
          if (state.loading) return const Center(child: CircularProgressIndicator());
          if (state.error != null) {
            return Center(child: Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
          }
          final filtered = _ranked(_filtered(state.cards));
          // Chips stay in place, dimmed when nothing matching them is left
          final availableTypes = _availableTypes(state.cards);
          final availableRarities = _availableRarities(state.cards);
          final availableColors = _availableColors(state.cards);
          return Column(
            children: [
              if (_showFilters)
                Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Keyword (name, type or rules text, e.g. goblin)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() => _syncColors(state.cards)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    for (final c in ['W', 'U', 'B', 'R', 'G', 'C'])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Opacity(
                          opacity: availableColors.contains(c) ? 1 : 0.35,
                          child: FilterChip(
                            label: Text(c),
                            selected: _colors.contains(c),
                            selectedColor: _manaColor(c).withValues(alpha: 0.5),
                            onSelected: (on) => setState(() {
                              // Plain click selects only this color, ctrl click adds or removes
                              final ctrl = HardwareKeyboard.instance.isControlPressed;
                              if (ctrl) {
                                on ? _colors.add(c) : _colors.remove(c);
                                if (on) _multicolor = true;
                              } else {
                                final wasOnlyThis = _colors.length == 1 && _colors.contains(c);
                                _colors.clear();
                                if (!wasOnlyThis) {
                                  _colors.add(c);
                                  _multicolor = true;
                                }
                              }
                              if (_colors.isEmpty) _multicolor = false;
                            }),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Opacity(
                        opacity: availableColors.contains('Multi') ? 1 : 0.35,
                        child: FilterChip(
                          label: const Text('Multi'),
                          selected: _multicolor,
                          selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                          onSelected: (on) => setState(() => _multicolor = on),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showFilters)
                Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Type', style: Theme.of(context).textTheme.labelLarge),
                    for (final t in allTypes)
                      Opacity(
                        opacity: availableTypes.contains(t) ? 1 : 0.35,
                        child: FilterChip(
                          label: Text(t),
                          visualDensity: VisualDensity.compact,
                          selected: _types.contains(t),
                          onSelected: (on) => setState(() {
                            on ? _types.add(t) : _types.remove(t);
                            _syncColors(state.cards);
                          }),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text('Rarity', style: Theme.of(context).textTheme.labelLarge),
                    for (final (r, label, color) in allRarities)
                      Opacity(
                        opacity: availableRarities.contains(r) ? 1 : 0.35,
                        child: FilterChip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                          selected: _rarities.contains(r),
                          selectedColor: color.withValues(alpha: 0.5),
                          onSelected: (on) => setState(() {
                            on ? _rarities.add(r) : _rarities.remove(r);
                            _syncColors(state.cards);
                          }),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      _minGih == 0 ? 'Min GIH: off' : 'Min GIH: ${_minGih.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    SizedBox(
                      width: 180,
                      child: Slider(
                        value: _minGih,
                        min: 0,
                        max: 70,
                        onChanged: (v) => setState(() {
                          _minGih = v;
                          _syncColors(state.cards);
                        }),
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
                    SizedBox(width: _rankWidth, child: _buildRankPanel(filtered)),
                  ],
                ),
              ),
              if (_deck.isNotEmpty || _side.isNotEmpty) ...[
                _buildHSplitter(),
                SizedBox(
                  height: _bottomHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: (constraints.maxWidth * _sideSplit - 11).clamp(0.0, constraints.maxWidth - 22),
                          child: _curve(_deck, showTargets: true, emptyText: 'Click cards to add them',
                              onTap: _fromDeck, onSecondary: _deckToSide),
                        ),
                        _buildSideSplitter(constraints.maxWidth),
                        Expanded(
                          child: _curve(_side, showTargets: false, emptyText: 'Sideboard empty',
                              onTap: _fromSide, onSecondary: _sideToDeck),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // Card image grid like the draft mode pack area, clicking adds to the deck
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
          child: CardGestures(
            // Left click or tap builds the deck, right click or two fingers sideboards
            onTap: () => setState(() => _deck.add(card)),
            onSecondary: () => setState(() => _side.add(card)),
            child: Opacity(
              opacity: excluded ? 0.35 : 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: cardImage(card, fit: BoxFit.contain, decodeWidth: _cardSize),
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
          // Wide grab area, the visible bar stays thin
          width: 22,
          child: Center(
            child: Container(
              width: 4,
              height: 80,
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
    final included = [for (final c in cards) if (!_excluded.contains(c.name)) c];
    final gih = _avg(included, (c) => c.gihwr);
    final iwd = _avg(included, (c) => c.iwd);
    final alsa = _avg(included, (c) => c.alsa);
    String pct(double? v) => v == null ? '-' : '${(v * 100).toStringAsFixed(1)}%';
    String pp(double? v) => v == null ? '-' : '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(1)}pp';
    String num(double? v) => v == null ? '-' : v.toStringAsFixed(2);
    final excludedCount = cards.length - included.length;
    final suffix = excludedCount > 0 ? ' ($excludedCount excluded)' : ' · click a table row to exclude it';
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
          Expanded(child: Text('Card', style: Theme.of(context).textTheme.labelLarge)),
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
            Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            Icon(Icons.arrow_drop_down, size: 16, color: selected ? null : Colors.transparent),
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
        onTap: () => setState(() => excluded ? _excluded.remove(card.name) : _excluded.add(card.name)),
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
                        style: TextStyle(decoration: excluded ? TextDecoration.lineThrough : null),
                      ),
                      Text(card.typeLine, style: stats, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                SizedBox(width: 70, child: Text(card.gihwrLabel, style: stats, textAlign: TextAlign.right)),
                SizedBox(width: 70, child: Text(card.iwdLabel, style: stats, textAlign: TextAlign.right)),
                SizedBox(width: 70, child: Text(card.alsaLabel, style: stats, textAlign: TextAlign.right)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Which filters the current results contain, used to dim the rest
  // Each row ignores its own filter, otherwise picking one dims all the others
  Set<String> _availableTypes(List<CardRating> cards) {
    final base = [for (final c in cards) if (_passesNonColor(c, ignoreTypes: true) && _passesColor(c)) c];
    return {
      for (final t in allTypes)
        if (base.any((c) => c.typeLine.split(' // ').first.contains(t))) t,
    };
  }

  Set<String> _availableRarities(List<CardRating> cards) {
    final base = [for (final c in cards) if (_passesNonColor(c, ignoreRarities: true) && _passesColor(c)) c];
    return {
      for (final r in allRarities)
        if (base.any((c) => c.rarity == r.$1)) r.$1,
    };
  }

  Set<String> _availableColors(List<CardRating> cards) {
    final base = [for (final c in cards) if (_passesNonColor(c)) c];
    final present = <String>{};
    for (final c in base) {
      if (c.color.isEmpty) {
        present.add('C');
      } else {
        present.addAll(c.color.split(''));
        if (c.color.length > 1) present.add('Multi');
      }
    }
    return present;
  }

  // Deck moves, cards can appear more than once so only one copy is removed
  void _fromDeck(CardRating c) => setState(() => _deck.remove(c));

  void _fromSide(CardRating c) => setState(() => _side.remove(c));

  void _deckToSide(CardRating c) => setState(() {
        _deck.remove(c);
        _side.add(c);
      });

  void _sideToDeck(CardRating c) => setState(() {
        _side.remove(c);
        _deck.add(c);
      });

  // Ranked filtered cards, plus deck and sideboard tables once they have cards
  Widget _buildRankPanel(List<CardRating> filtered) {
    final hasSide = _side.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final topH = hasSide ? (h * _deckSplit - 11).clamp(0.0, h - 22) : h;
        return Column(
          children: [
            SizedBox(
              height: topH,
              child: Column(
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No cards match'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) => _row(context, i + 1, filtered[i]),
                          ),
                  ),
                ],
              ),
            ),
            if (hasSide) ...[
              _buildDeckSplitter(h),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('Sideboard', style: Theme.of(context).textTheme.labelLarge)),
                          Text('${_side.length}', style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _ranked(_side).length,
                        itemBuilder: (context, i) => _row(context, i + 1, _ranked(_side)[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // Drag to resize the deck area
  Widget _buildHSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          _bottomHeight = (_bottomHeight - d.delta.dy).clamp(80.0, MediaQuery.of(context).size.height * 0.7);
        }),
        child: SizedBox(
          // Tall grab area, the visible bar stays thin
          height: 22,
          child: Center(
            child: Container(
              width: 80,
              height: 4,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  // Drag to split the deck and sideboard widths
  Widget _buildSideSplitter(double totalWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => setState(() {
          _sideSplit = (_sideSplit + d.delta.dx / totalWidth).clamp(0.2, 0.9);
        }),
        child: SizedBox(
          // Wide grab area, the visible bar stays thin
          width: 22,
          child: Center(
            child: Container(
              width: 4,
              height: 80,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  // Drag to split the ranks between filtered cards and the sideboard
  Widget _buildDeckSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          _deckSplit = (_deckSplit + d.delta.dy / totalHeight).clamp(0.2, 0.85);
        }),
        child: SizedBox(
          // Tall grab area, the visible bar stays thin
          height: 22,
          child: Center(
            child: Container(
              width: 80,
              height: 4,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  // Curve view: lands far left, columns by cost with spells on top, creatures below
  // Cards are scaled to fit the area so every column stays visible
  // Left click removes a card, right click or long press moves it across
  Widget _curve(List<CardRating> cards, {
    required bool showTargets,
    required String emptyText,
    required void Function(CardRating) onTap,
    required void Function(CardRating) onSecondary,
  }) {
    if (cards.isEmpty) return Center(child: Text(emptyText));
    final lands = _sortedPool(cards.where((c) => c.isLand).toList());
    final costs = List.generate(8, (i) => i);
    final spellRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && !x.isCreature && x.costBucket == c).toList())];
    final creatureRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && x.isCreature && x.costBucket == c).toList())];
    int maxLen(List<List<CardRating>> rows) => rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final maxTop = maxLen(spellRows);
    final maxBottom = maxLen([creatureRows, [lands]].expand((e) => e).toList());
    final creatures = creatureRows.fold(0, (s, r) => s + r.length);
    final spells = spellRows.fold(0, (s, r) => s + r.length);
    final nonLands = cards.where((c) => !c.isLand).toList();
    final avgCost = nonLands.isEmpty ? null : nonLands.fold(0, (s, c) => s + c.cmc) / nonLands.length;
    return LayoutBuilder(
      builder: (context, box) {
        final w = _fitCardWidth(box, maxTop, maxBottom, showTargets);
        final offset = w * 0.15;
        final cardH = w * 1.4;
        final topH = maxTop == 0 ? 0.0 : cardH + (maxTop - 1) * offset;
        final bottomH = maxBottom == 0 ? 0.0 : cardH + (maxBottom - 1) * offset;
        final grid = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (topH > 0) SizedBox(height: topH),
                  if (topH > 0 && bottomH > 0) const SizedBox(height: 4),
                  SizedBox(
                    height: bottomH,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _cardStack(lands, w, offset, onTap, onSecondary),
                    ),
                  ),
                  _columnLabel('Lands', lands.length, showTargets ? 17 : null),
                ],
              ),
            ),
            for (final c in costs)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (topH > 0)
                      SizedBox(
                        height: topH,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _cardStack(spellRows[c], w, offset, onTap, onSecondary),
                        ),
                      ),
                    if (topH > 0 && bottomH > 0) const SizedBox(height: 4),
                    if (bottomH > 0)
                      SizedBox(
                        height: bottomH,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _cardStack(creatureRows[c], w, offset, onTap, onSecondary),
                        ),
                      ),
                    _columnLabel(c == 7 ? '7+' : '$c', spellRows[c].length + creatureRows[c].length,
                        showTargets ? _curveTarget(c) : null),
                  ],
                ),
              ),
          ],
        );
        if (!showTargets) return SingleChildScrollView(child: grid);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: Row(
                children: [
                  _totalLabel('Creatures', creatures, 16),
                  const SizedBox(width: 12),
                  _totalLabel('Noncreatures', spells, 7),
                  const SizedBox(width: 12),
                  Text('Avg cost ${avgCost == null ? '-' : avgCost.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(child: SingleChildScrollView(child: grid)),
          ],
        );
      },
    );
  }

  // Largest card width that keeps all nine columns and both rows in view
  double _fitCardWidth(BoxConstraints box, int maxTop, int maxBottom, bool showTargets) {
    const columns = 9;
    final byWidth = (box.maxWidth - 8) / columns;
    final labels = showTargets ? 54.0 : 30.0;
    final rows = (maxTop == 0 ? 0.0 : 1.4 + 0.15 * (maxTop - 1)) +
        (maxBottom == 0 ? 0.0 : 1.4 + 0.15 * (maxBottom - 1));
    final byHeight = rows <= 0 ? byWidth : (box.maxHeight - labels) / rows;
    final fit = byWidth < byHeight ? byWidth : byHeight;
    final preferred = _cardSize * 0.47;
    return (fit < preferred ? fit : preferred).clamp(24.0, 400.0);
  }

  Widget _cardStack(List<CardRating> cards, double w, double offset,
      void Function(CardRating) onTap, void Function(CardRating) onSecondary) {
    if (cards.isEmpty) return SizedBox(width: w);
    final h = w * 1.4 + (cards.length - 1) * offset;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              top: i * offset,
              child: HoverZoom(
                card: cards[i],
                zoomWidth: _zoomSize,
                enabled: _zoomEnabled,
                child: CardGestures(
                  onTap: () => onTap(cards[i]),
                  onSecondary: () => onSecondary(cards[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: cardImage(cards[i], width: w, decodeWidth: w),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int? _curveTarget(int cost) {
    return switch (cost) {
      0 => null,
      1 => 1,
      2 => 6,
      3 => 6,
      4 => 4,
      5 => 3,
      6 => 2,
      _ => 1,
    };
  }

  Widget _columnLabel(String label, int count, int? target) {
    if (target == null) return Text(label);
    final met = count >= target;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text('$count/$target', style: TextStyle(fontSize: 11, color: met ? const Color(0xFF4CAF6D) : null)),
      ],
    );
  }

  Widget _totalLabel(String label, int count, int target) {
    final met = count >= target;
    return Text('$label $count/$target',
        style: TextStyle(fontSize: 12, color: met ? const Color(0xFF4CAF6D) : null));
  }

  // Sorted by color then name so piles are easy to scan
  List<CardRating> _sortedPool(List<CardRating> pool) {
    final sorted = List<CardRating>.from(pool)
      ..sort((a, b) {
        final c = a.color.compareTo(b.color);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return sorted;
  }

  List<CardRating> _filtered(List<CardRating> cards) {
    return [
      for (final c in cards)
        if (_passesNonColor(c) && _passesColor(c)) c,
    ];
  }

  bool _passesNonColor(CardRating c, {bool ignoreTypes = false, bool ignoreRarities = false}) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !c.name.toLowerCase().contains(q) &&
        !c.typeLine.toLowerCase().contains(q) &&
        !c.oracleText.toLowerCase().contains(q)) {
      return false;
    }
    if (!ignoreRarities && _rarities.isNotEmpty && !_rarities.contains(c.rarity)) return false;
    // Match against the front face so spell//land backsides don't count as lands
    if (!ignoreTypes && _types.isNotEmpty && !_types.any((t) => c.typeLine.split(' // ').first.contains(t))) return false;
    // With a floor set, unrated cards (low sample) are dropped too
    if (_minGih > 0 && (c.gihwr == null || c.gihwr! * 100 < _minGih)) return false;
    return true;
  }

  bool _passesColor(CardRating c) {
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
  }

  // When the other filters leave nothing in the chosen colors, switch to the
  // colors that are actually present instead of showing an empty list
  void _syncColors(List<CardRating> cards) {
    if (_colors.isEmpty) return;
    final base = [for (final c in cards) if (_passesNonColor(c)) c];
    if (base.isEmpty || base.any(_passesColor)) return;
    final present = <String>{};
    for (final c in base) {
      if (c.color.isEmpty) {
        present.add('C');
      } else {
        present.addAll(c.color.split(''));
      }
    }
    setState(() {
      _colors
        ..clear()
        ..addAll(present);
      _multicolor = true;
    });
  }

  List<CardRating> _ranked(List<CardRating> cards) {
    final sorted = List<CardRating>.from(cards);
    sorted.sort((a, b) => switch (_rankStat) {
      RankStat.gihwr => (b.gihwr ?? -1).compareTo(a.gihwr ?? -1),
      RankStat.iwd => (b.iwd ?? -9).compareTo(a.iwd ?? -9),
      RankStat.alsa => (a.alsa ?? 99).compareTo(b.alsa ?? 99),
    });
    return sorted;
  }

  double? _avg(List<CardRating> cards, double? Function(CardRating) f) {
    final vals = [for (final c in cards) if (f(c) != null) f(c)!];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  BoxDecoration _rowDecoration(String color) {
    final letters = color.isEmpty ? ['C'] : color.split('');
    final colors = [for (final l in letters) _manaColor(l).withValues(alpha: 0.35)];
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