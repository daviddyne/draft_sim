import 'dart:async';

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
  // Typing is debounced, filtering every keystroke is slow on weaker devices
  String _searchTerm = '';
  Timer? _debounce;
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
  // Lets several sets be mixed, e.g. for a chaos draft
  void _showSetPicker(BuildContext context) {
    final cubit = context.read<BrowseCubit>();
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: AlertDialog(
          title: const Text('Sets in this view'),
          content: SizedBox(
            width: 420,
            height: 460,
            child: BlocBuilder<BrowseCubit, BrowseState>(
              builder: (context, state) {
                final options = state.available.isEmpty
                    ? [for (final c in state.setCodes) SetOption(c, c, '')]
                    : state.available;
                return Column(
                  children: [
                    if (state.loading) const LinearProgressIndicator(),
                    if (state.available.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                state.error ?? 'Set list not loaded yet',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(onPressed: cubit.loadAvailable, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final option = options[i];
                          final on = state.setCodes.contains(option.code);
                          return CheckboxListTile(
                            dense: true,
                            value: on,
                            title: Text('${option.name} (${option.code})', overflow: TextOverflow.ellipsis),
                            onChanged: (_) => cubit.toggleSet(option.code),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cubit.addAll(),
              child: const Text('Add all sets'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  // All filter rows can be collapsed to leave more room for cards
  bool _showFilters = true;
  // Cards dragged to another cost column, keyed by card name
  final Map<String, int> _costOverride = {};
  // Cards moved between the creature and noncreature rows, e.g. a sorcery that
  // makes a creature can be counted as one
  final Map<String, bool> _typeOverride = {};
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
  // 320 is the narrowest the rank columns and a card name fit in
  // The overall ranking can be hidden to leave the pair ranking alone
  bool _showSolo = true;
  // The pair table has its own width, so its splitter leaves the first table alone
  double _pairWidth = 340;
  double _rankWidth = 420;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(List<CardRating> cards) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _searchTerm = _searchController.text.trim().toLowerCase();
        _syncColors(cards);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<BrowseCubit, BrowseState>(
          builder: (context, state) => Text(
            state.setCodes.length <= 3
                ? '${state.setCodes.join(' + ')} card browser'
                : '${state.setCodes.length} sets · ${state.cards.length} cards',
          ),
        ),
        actions: [
          BlocBuilder<BrowseCubit, BrowseState>(
            builder: (context, state) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showSolo ? 'Hide the overall ranking' : 'Show the overall ranking',
                  icon: Icon(_showSolo ? Icons.table_rows : Icons.table_rows_outlined,
                      size: 20, color: _showSolo ? null : Theme.of(context).disabledColor),
                  onPressed: state.pair.isEmpty ? null : () => setState(() => _showSolo = !_showSolo),
                ),
                IconButton(
                  tooltip: state.pair.isEmpty ? 'Show ratings for a color pair' : 'Hide pair ratings',
                  icon: Icon(Icons.palette_outlined,
                      color: state.pair.isEmpty ? Theme.of(context).disabledColor : null),
                  onPressed: () => context.read<BrowseCubit>().togglePair(_deck),
                ),
                if (state.pair.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Choose color pair',
                    // A popup sizes its own menu, so the button stays as small as the dots
                    onSelected: (v) => context.read<BrowseCubit>().setPairManually(v),
                    itemBuilder: (context) => [
                      for (final p in _pairsByRating(state))
                        PopupMenuItem(
                          value: p,
                          height: 34,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _pairDots(p, size: 12),
                              const SizedBox(width: 6),
                              Text(
                                state.pairAverages[p] == null
                                    ? '-'
                                    : '${(state.pairAverages[p]! * 100).toStringAsFixed(1)}%',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _pairDots(state.pair, size: 12),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Choose sets',
            icon: const Icon(Icons.library_add),
            onPressed: () => _showSetPicker(context),
          ),
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
          _rebuildDerived(state.cards);
          final filtered = _memoFiltered;
          // Chips stay in place, dimmed when nothing matching them is left
          final availableTypes = _memoTypes;
          final availableRarities = _memoRarities;
          final availableColors = _memoColors;
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
                        onChanged: (_) => _onSearchChanged(state.cards),
                      ),
                    ),
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
                // Ranks run the full height on the right, the deck sits under the grid
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final hasDeck = _deck.isNotEmpty || _side.isNotEmpty;
                          // Can take the whole area, only the drag handle has to stay visible
                          final bottom = hasDeck
                              ? _bottomHeight.clamp(0.0, (box.maxHeight - 22).clamp(0.0, box.maxHeight))
                              : 0.0;
                          return Column(
                            children: [
                              Expanded(child: _buildGrid(filtered)),
                              if (hasDeck) ...[
                                _buildHSplitter(),
                                SizedBox(
                                  height: bottom,
                                  child: LayoutBuilder(
                                    builder: (context, inner) => Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: splitSize(inner.maxWidth, _sideSplit),
                                          child: _curve(_deck,
                                              showTargets: true,
                                              emptyText: 'Click cards to add them',
                                              onTap: _fromDeck,
                                              onSecondary: _deckToSide,
                                              lands: state.lands,
                                              onAddLand: _addToDeck),
                                        ),
                                        _buildSideSplitter(inner.maxWidth),
                                        Expanded(
                                          child: _curve(_side,
                                              showTargets: false,
                                              emptyText: 'Sideboard empty',
                                              onTap: _fromSide,
                                              onSecondary: _sideToDeck),
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
                    ),
                    _buildVSplitter(),
                    SizedBox(
                      width: _panelWidth(state),
                      child: _buildRankPanel(filtered, state),
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
            onTap: () => _addToDeck(card),
            onSecondary: () => _addToSide(card),
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

  // Overall ranking beside the pair ranking, either side can be absent
  Widget _rankPair(BrowseState state, Widget solo, Widget pair) {
    if (state.pair.isEmpty) return solo;
    if (!_showSolo) return pair;
    return LayoutBuilder(
      builder: (context, row) => Row(
        children: [
          SizedBox(
            width: (row.maxWidth - _pairWidth - 14).clamp(0.0, row.maxWidth),
            child: solo,
          ),
          _buildPairSplitter(),
          SizedBox(width: _pairWidth, child: pair),
        ],
      ),
    );
  }

  // How wide the whole panel needs to be for whatever is showing
  double _panelWidth(BrowseState state) {
    if (state.pair.isEmpty) return _rankWidth;
    return _showSolo ? _rankWidth + _pairWidth + 14 : _pairWidth;
  }

  // Drag to resize the pair table only, the first table keeps its width
  Widget _buildPairSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _pairWidth = snapTo(_pairWidth, 230.0, 700.0)),
        onHorizontalDragUpdate: (d) => setState(() {
          _pairWidth = (_pairWidth - d.delta.dx).clamp(230.0, 700.0);
        }),
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 3,
              height: 60,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  // Drag to resize the ranking panel
  Widget _buildVSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _rankWidth = snapTo(_rankWidth, 320.0, 700.0)),
        onHorizontalDragUpdate: (d) => setState(() {
          _rankWidth = (_rankWidth - d.delta.dx).clamp(320.0, 700.0);
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

  // Pairs ordered by how strong their playables are, unrated ones last
  List<String> _pairsByRating(BrowseState state) {
    return [...BrowseCubit.pairs]
      ..sort((a, b) => (state.pairAverages[b] ?? -1).compareTo(state.pairAverages[a] ?? -1));
  }

  // Two mana dots standing in for the pair, no letters to read
  Widget _pairDots(String pair, {double size = 10}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final letter in pair.split(''))
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(color: _manaColor(letter), shape: BoxShape.circle),
          ),
      ],
    );
  }

  // The chosen pair is plain text, an alternative pair is boxed in its colors
  Widget _pairBadge(String pair, double? wr, {bool faded = false}) {
    if (pair.isEmpty) return const SizedBox.shrink();
    final label = wr == null ? '-' : '${(wr * 100).toStringAsFixed(1)}%';
    if (!faded) return Text(label, style: const TextStyle(fontSize: 12));
    const alpha = 0.2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _manaColor(pair[1]).withValues(alpha: 0.9)),
        gradient: LinearGradient(colors: [
          _manaColor(pair[0]).withValues(alpha: alpha),
          _manaColor(pair[1]).withValues(alpha: alpha),
        ]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pairDots(pair, size: 7),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  // The pair this card performs best in, whichever that is
  (String, double)? _topPair(BrowseState state, CardRating card) {
    String? bestPair;
    var bestWr = -1.0;
    for (final entry in state.allPairRatings.entries) {
      final wr = entry.value[card.name];
      if (wr != null && wr > bestWr) {
        bestWr = wr;
        bestPair = entry.key;
      }
    }
    return bestPair == null ? null : (bestPair, bestWr);
  }

  // Shown beside the chosen pair only when some other pair rates the card higher
  (String, double)? _betterPair(BrowseState state, CardRating card) {
    final top = _topPair(state, card);
    if (top == null || top.$1 == state.pair) return null;
    final current = state.pairRatings[card.name];
    if (current != null && top.$2 <= current) return null;
    return top;
  }

  // Both tables use the same row height and badge slot, so their rows line up
  static const double rankRowHeight = 44;
  static const double badgeSlotHeight = 18;

  Widget _badgeSlot(Widget? badge) =>
      SizedBox(height: badgeSlotHeight, child: badge == null ? null : Center(child: badge));

  // The card's best pair, for the overall table
  Widget _topPairSlot(BrowseState state, CardRating card) {
    final top = _topPair(state, card);
    return _badgeSlot(top == null ? null : _pairBadge(top.$1, top.$2, faded: true));
  }

  // How much the pair rating gains or loses against the overall one
  // Green when the card is better in the pair, red when it is worse
  Widget _gihCompare(CardRating card, double? pairWr) {
    const up = Color(0xFF4CAF6D);
    const down = Color(0xFFD9534F);
    if (card.gihwr == null || pairWr == null) {
      return const Text('-', style: TextStyle(fontSize: 12));
    }
    final diff = (pairWr - card.gihwr!) * 100;
    final sign = diff >= 0 ? '+' : '';
    return Text(
      '$sign${diff.toStringAsFixed(1)}%',
      style: TextStyle(fontSize: 12, color: diff >= 0 ? up : down),
    );
  }

  // A second ranking beside the first, ordered by the chosen pair's win rates
  Widget _buildPairTable(BuildContext context, BrowseState state, List<CardRating> cards) {
    final ranked = List<CardRating>.from(cards)
      ..sort((a, b) => (state.pairRatings[b.name] ?? -1).compareTo(state.pairRatings[a.name] ?? -1));
    return LayoutBuilder(
      builder: (context, box) {
        final showHeader = box.maxHeight >= 70;
        return Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 30),
                    Expanded(
                      // Wraps and clips rather than overflowing when dragged narrow
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('In pair', style: Theme.of(context).textTheme.labelLarge),
                          // How strong the pair's best commons and uncommons are
                          if (state.pairAverage != null)
                            Text('top20 ${(state.pairAverage! * 100).toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    SizedBox(width: 70, child: Text('vs GIH', textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge)),
                    SizedBox(width: 70, child: Align(alignment: Alignment.centerRight,
                        child: _pairDots(state.pair, size: 12))),
                  ],
                ),
              ),
            if (showHeader) const Divider(height: 1),
            Expanded(
              child: state.pairRatings.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          SeventeenLandsService.lastPairNote.isEmpty
                              ? 'Loading pair ratings...'
                              : 'No pair data\n${SeventeenLandsService.lastPairNote}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )
                  : ranked.isEmpty
                      ? const Center(child: Text('No cards match'))
                      : ListView.builder(
                      itemCount: ranked.length,
                      itemBuilder: (context, i) => _pairRow(context, state, i + 1, ranked[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _pairRow(BuildContext context, BrowseState state, int rank, CardRating card) {
    final stats = Theme.of(context).textTheme.bodySmall;
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: CardGestures(
        onTap: () => _addToDeck(card),
        onSecondary: () => _addToSide(card),
        child: Container(
          height: rankRowHeight,
          decoration: _rowDecoration(card.color),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 30, child: Text('$rank', style: stats)),
              Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
              // The overall rating, colored by how it compares to the pair
              SizedBox(
                width: 70,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _gihCompare(card, state.pairRatings[card.name]),
                ),
              ),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _pairBadge(state.pair, state.pairRatings[card.name]),
                    ),
                    _badgeSlot(_betterPair(state, card) == null
                        ? null
                        : _pairBadge(_betterPair(state, card)!.$1, _betterPair(state, card)!.$2, faded: true)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            height: rankRowHeight,
            decoration: _rowDecoration(card.color),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('$rank', style: stats)),
                Expanded(
                  child: Text(
                    card.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(decoration: excluded ? TextDecoration.lineThrough : null),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(card.gihwrLabel, style: stats),
                      ),
                      // The pair this card is best in, so the ceiling is visible
                      _topPairSlot(context.read<BrowseCubit>().state, card),
                    ],
                  ),
                ),
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
  // Every change re-checks the color pair, unless one was chosen by hand
  void _deckChanged() => context.read<BrowseCubit>().autoPair(_deck);

  void _addToDeck(CardRating c) {
    setState(() => _deck.add(c));
    _deckChanged();
  }

  void _addToSide(CardRating c) => setState(() => _side.add(c));

  void _fromDeck(CardRating c) {
    setState(() => _deck.remove(c));
    _deckChanged();
  }

  void _fromSide(CardRating c) => setState(() => _side.remove(c));

  void _deckToSide(CardRating c) {
    setState(() {
      _deck.remove(c);
      _side.add(c);
    });
    _deckChanged();
  }

  void _sideToDeck(CardRating c) {
    setState(() {
      _side.remove(c);
      _deck.add(c);
    });
    _deckChanged();
  }

  // Ranked filtered cards, plus deck and sideboard tables once they have cards
  Widget _buildRankPanel(List<CardRating> filtered, BrowseState state) {
    final hasSide = _side.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final topH = hasSide ? splitSize(h, _deckSplit) : h;
        return Column(
          children: [
            SizedBox(
              height: topH,
              child: _rankPair(state, Column(
                        children: [
                          // The header is dropped when the pane is dragged too small for it
                          if (topH >= 70) _buildHeader(context),
                          if (topH >= 70) const Divider(height: 1),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(child: Text('No cards match'))
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, i) => _row(context, i + 1, filtered[i]),
                                  ),
                          ),
                        ],
                      ), _buildPairTable(context, state, filtered)),
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
        onTap: () => setState(() => _bottomHeight = snapTo(_bottomHeight, 0.0, MediaQuery.of(context).size.height)),
        onVerticalDragUpdate: (d) => setState(() {
          _bottomHeight = (_bottomHeight - d.delta.dy).clamp(0.0, MediaQuery.of(context).size.height);
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
        onTap: () => setState(() => _sideSplit = snapTo(_sideSplit, 0.2, 0.9)),
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
        onTap: () => setState(() => _deckSplit = snapTo(_deckSplit, 0.2, 0.85)),
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
    List<CardRating> lands = const [],
    void Function(CardRating)? onAddLand,
  }) {
    if (cards.isEmpty) return Center(child: Text(emptyText));
    final lands = _sortedPool(cards.where((c) => c.isLand).toList());
    final costs = List.generate(7, (i) => i);
    final spellRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && !_isCreature(x) && _bucketOf(x) == c).toList())];
    final creatureRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && _isCreature(x) && _bucketOf(x) == c).toList())];
    int maxLen(List<List<CardRating>> rows) => rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final maxTop = maxLen(spellRows);
    final maxBottom = maxLen([creatureRows, [lands]].expand((e) => e).toList());
    final creatures = creatureRows.fold(0, (s, r) => s + r.length);
    final spells = spellRows.fold(0, (s, r) => s + r.length);
    final nonLands = cards.where((c) => !c.isLand).toList();
    final avgCost = nonLands.isEmpty ? null : nonLands.fold(0.0, (s, c) => s + _costOf(c)) / nonLands.length;
    return LayoutBuilder(
      builder: (context, box) {
        // Dragged almost shut, nothing sensible fits, so draw nothing
        if (box.maxHeight < 40) return const SizedBox.shrink();
        final showHeader = showTargets && box.maxHeight >= 90;
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
                  _columnLabel('Lands', lands.length, showTargets ? (16, 18) : null),
                ],
              ),
            ),
            for (final c in costs)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dropping a card in a row sets both its cost and its type
                    if (topH > 0)
                      _costTarget(
                        c,
                        false,
                        SizedBox(
                          height: topH,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _cardStack(spellRows[c], w, offset, onTap, onSecondary, draggable: showTargets),
                          ),
                        ),
                      ),
                    if (showTargets && topH > 0)
                      _rowCount(spellRows[c].length + creatureRows[c].length, _combinedRange(c)),
                    if (topH > 0 && bottomH > 0) const SizedBox(height: 4),
                    if (bottomH > 0)
                      _costTarget(
                        c,
                        true,
                        SizedBox(
                          height: bottomH,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _cardStack(creatureRows[c], w, offset, onTap, onSecondary, draggable: showTargets),
                          ),
                        ),
                      ),
                    if (showTargets && bottomH > 0) _rowCount(creatureRows[c].length, _creatureRange(c)),
                    Text(c == 6 ? '6+' : '$c'),
                  ],
                ),
              ),
          ],
        );
        // No room for the totals, so just the cards
        if (!showHeader) return SingleChildScrollView(child: grid);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              // Sideboard keeps an equally tall header so both curves line up.
              // It wraps onto more lines when the half is too narrow for one.
              child: showTargets
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Deck ${cards.length}', style: const TextStyle(fontSize: 12)),
                        _totalLabel('Creatures', creatures, (14, 17)),
                        _totalLabel('Noncreatures', spells, (6, 9)),
                        _avgCostLabel(avgCost),
                        if (onAddLand != null) _basicLandBar(lands, onAddLand),
                      ],
                    )
                  : Text('Sideboard ${cards.length}', style: const TextStyle(fontSize: 12)),
            ),
            Expanded(child: SingleChildScrollView(child: grid)),
          ],
        );
      },
    );
  }

  // Cost the deck should count this card as, after any manual move
  int _bucketOf(CardRating card) => _costOverride[card.name] ?? card.costBucket;

  bool _isCreature(CardRating card) => _typeOverride[card.name] ?? card.isCreature;

  // A drop lands in one row of one column, fixing the card's cost and whether
  // the deck counts it as a creature
  Widget _costTarget(int cost, bool creature, Widget child) {
    return DragTarget<CardRating>(
      onAcceptWithDetails: (d) => setState(() {
        _costOverride[d.data.name] = cost;
        _typeOverride[d.data.name] = creature;
      }),
      builder: (context, candidate, rejected) => child,
    );
  }

  double _costOf(CardRating card) => (_costOverride[card.name] ?? card.cmc).toDouble();

  // Largest card width that keeps all eight columns and both rows in view
  double _fitCardWidth(BoxConstraints box, int maxTop, int maxBottom, bool showTargets) {
    const columns = 8;
    final byWidth = (box.maxWidth - 8) / columns;
    // Room for the two row counts, the cost label and a wrapped header
    final labels = showTargets ? 96.0 : 30.0;
    final rows = (maxTop == 0 ? 0.0 : 1.4 + 0.15 * (maxTop - 1)) +
        (maxBottom == 0 ? 0.0 : 1.4 + 0.15 * (maxBottom - 1));
    final byHeight = rows <= 0 ? byWidth : (box.maxHeight - labels) / rows;
    final fit = byWidth < byHeight ? byWidth : byHeight;
    final preferred = _cardSize * 0.47;
    return (fit < preferred ? fit : preferred).clamp(24.0, 400.0);
  }

  Widget _cardStack(List<CardRating> cards, double w, double offset,
      void Function(CardRating) onTap, void Function(CardRating) onSecondary,
      {bool draggable = false}) {
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
              child: _maybeDraggable(
                cards[i],
                w,
                draggable,
                HoverZoom(
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
            ),
        ],
      ),
    );
  }

  // Cards can be dragged sideways onto another cost column, which overrides the
  // cost used for the curve and the average. Horizontal only, so the area still
  // scrolls vertically with a finger.
  Widget _maybeDraggable(CardRating card, double w, bool enabled, Widget child) {
    if (!enabled) return child;
    return Draggable<CardRating>(
      data: card,
      affinity: Axis.horizontal,
      feedback: Opacity(
        opacity: 0.85,
        child: SizedBox(width: w, child: cardImage(card, width: w, decodeWidth: w)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: child,
    );
  }


  // Common limited guidance for a 17 land deck, split by card type
  (int, int)? _creatureRange(int cost) {
    return switch (cost) {
      0 => null,
      1 => (0, 2),
      2 => (4, 6),
      3 => (3, 5),
      4 => (2, 4),
      5 => (1, 3),
      _ => (0, 2),
    };
  }

  // Creatures and noncreatures together, the shape of the whole curve
  (int, int)? _combinedRange(int cost) {
    return switch (cost) {
      0 => null,
      1 => (0, 2),
      2 => (5, 7),
      3 => (4, 6),
      4 => (3, 5),
      5 => (2, 3),
      _ => (1, 2),
    };
  }

  // Small count under a stack, green while inside the recommended range
  Widget _rowCount(int count, (int, int)? range) {
    if (range == null) return const SizedBox(height: 14);
    return SizedBox(
      height: 14,
      child: Text('$count/${_rangeLabel(range)}',
          style: TextStyle(fontSize: 10, color: _rangeColor(count, range))),
    );
  }

  // Count against the recommended range, with the middle of the range in
  // brackets, green while inside it
  Widget _columnLabel(String label, int count, (int, int)? range) {
    if (range == null) return Text(label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text('$count/${_rangeLabel(range)}',
            style: TextStyle(fontSize: 11, color: _rangeColor(count, range))),
      ],
    );
  }

  // Red outside the range, yellow inside it, green on the recommended amount
  Color _rangeColor(int count, (int, int) range) {
    if (count < range.$1 || count > range.$2) return const Color(0xFFD9534F);
    final mid = (range.$1 + range.$2) / 2;
    if (count == mid.floor() || count == mid.ceil()) return const Color(0xFF4CAF6D);
    return const Color(0xFFE0B33C);
  }

  // 5(4-6) or 2.5(2-3), middle first, one decimal only when it isn't whole
  String _rangeLabel((int, int) range) {
    final mid = (range.$1 + range.$2) / 2;
    final label = mid == mid.roundToDouble() ? mid.round().toString() : mid.toStringAsFixed(1);
    return '$label(${range.$1}-${range.$2})';
  }

  // Deck total against the recommended range, green while inside it
  Widget _totalLabel(String label, int count, (int, int) range) {
    return Text(
      '$label $count/${_rangeLabel(range)}',
      style: TextStyle(fontSize: 12, color: _rangeColor(count, range)),
    );
  }

  // Average mana value of the nonland cards, most limited decks sit near three
  Widget _avgCostLabel(double? avg) {
    const low = 2.8;
    const high = 3.3;
    final ok = avg != null && avg >= low && avg <= high;
    return Text(
      'Avg cost ${avg == null ? '-' : avg.toStringAsFixed(1)}/${((low + high) / 2).toStringAsFixed(1)}($low-$high)',
      style: TextStyle(fontSize: 12, color: ok ? const Color(0xFF4CAF6D) : null),
    );
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

  // Everything derived from the filters, recomputed only when they change
  String? _memoKey;
  List<CardRating> _memoFiltered = const [];
  Set<String> _memoTypes = const {};
  Set<String> _memoRarities = const {};
  Set<String> _memoColors = const {};

  void _rebuildDerived(List<CardRating> cards) {
    final key = [
      cards.length,
      _searchTerm,
      _colors.toList()..sort(),
      _multicolor,
      _types.toList()..sort(),
      _rarities.toList()..sort(),
      _minGih,
      _rankStat,
      _excluded.length,
    ].join('|');
    if (key == _memoKey) return;
    _memoKey = key;
    _memoFiltered = _ranked(_filtered(cards));
    _memoTypes = _availableTypes(cards);
    _memoRarities = _availableRarities(cards);
    _memoColors = _availableColors(cards);
  }

  List<CardRating> _filtered(List<CardRating> cards) {
    return [
      for (final c in cards)
        if (_passesNonColor(c) && _passesColor(c)) c,
    ];
  }

  bool _passesNonColor(CardRating c, {bool ignoreTypes = false, bool ignoreRarities = false}) {
    final q = _searchTerm;
    if (q.isNotEmpty &&
        !c.name.toLowerCase().contains(q) &&
        !c.typeLine.toLowerCase().contains(q) &&
        !c.oracleText.toLowerCase().contains(q)) {
      return false;
    }
    if (!ignoreRarities && _rarities.isNotEmpty && !_rarities.contains(c.rarity)) return false;
    // Match against the front face so spell//land backsides don't count as lands
    if (!ignoreTypes && _types.isNotEmpty) {
      if (!_types.any((t) => c.typeLine.split(' // ').first.contains(t))) return false;
    }
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

  // Basics aren't drafted, so they get their own add buttons
  Widget _basicLandBar(List<CardRating> lands, void Function(CardRating) onAdd) {
    if (lands.isEmpty) return const SizedBox.shrink();
    const names = {'W': 'Plains', 'U': 'Island', 'B': 'Swamp', 'R': 'Mountain', 'G': 'Forest'};
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Add land', style: TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        for (final entry in names.entries)
          if (lands.where((l) => l.name == entry.value).firstOrNull case final land?)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Tooltip(
                message: entry.value,
                child: InkWell(
                  onTap: () => onAdd(land),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _manaColor(entry.key), shape: BoxShape.circle),
                    child: Text(entry.key, style: const TextStyle(fontSize: 11, color: Colors.black)),
                  ),
                ),
              ),
            ),
      ],
    );
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