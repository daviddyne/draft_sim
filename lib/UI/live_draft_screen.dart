import 'package:draft_sim/Logic/arena_draft_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/arena_log_service.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'browse_screen.dart';
import 'draft_screen.dart';

class LiveDraftScreen extends StatelessWidget {
  const LiveDraftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ArenaDraftCubit(SeventeenLandsService(), ArenaLogService())..start(),
      child: const _LiveView(),
    );
  }
}

class _LiveView extends StatefulWidget {
  const _LiveView();

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  final _pathController = TextEditingController();
  RankStat _rankStat = RankStat.gihwr;
  double _cardSize = 240;
  double _zoomSize = 350;
  bool _zoomEnabled = true;
  double _rankWidth = 420;
  // Cards dragged to another cost column, keyed by card name
  final Map<String, int> _costOverride = {};
  // Cards moved between the creature and noncreature rows, e.g. a sorcery that
  // makes a creature can be counted as one
  final Map<String, bool> _typeOverride = {};
  // The overall ranking can be hidden to leave the pair ranking alone
  bool _showSolo = true;
  // The pair table has its own width, so its splitter leaves the first table alone
  double _pairWidth = 340;
  // Vertical split between the pack table and the picks table
  double _rankSplit = 0.6;
  // Vertical split between the picks table and the sideboard table
  double _sideSplit = 0.6;
  // Vertical split between main deck and sideboard in the finished layout
  double _doneSplit = 0.65;
  // Colors shown in the pool curves, empty shows everything
  final Set<String> _colorFilter = {};

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ArenaDraftCubit, ArenaDraftState>(
          builder: (context, state) => Row(
            children: [
              Text(
                state.setCode.isEmpty
                    ? 'Arena · detecting set...'
                    : 'Arena · ${state.setCode} ${state.eventType}',
              ),
              const SizedBox(width: 16),
              if (state.connected) _buildColorFilter(),
              if (state.unknownIds > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    '${state.unknownIds} unmatched (${state.unknownInfo})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD9534F),
                    ),
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    state.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD9534F),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Browse this set',
            icon: const Icon(Icons.manage_search),
            onPressed: () {
              final s = context.read<ArenaDraftCubit>().state;
              if (s.setCode.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      BrowseScreen(setCode: s.setCode, eventType: s.eventType),
                ),
              );
            },
          ),
          BlocBuilder<ArenaDraftCubit, ArenaDraftState>(
            builder: (context, state) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _showSolo
                      ? 'Hide the overall ranking'
                      : 'Show the overall ranking',
                  icon: Icon(
                    _showSolo ? Icons.table_rows : Icons.table_rows_outlined,
                    size: 20,
                    color: _showSolo ? null : Theme.of(context).disabledColor,
                  ),
                  onPressed: state.pair.isEmpty
                      ? null
                      : () => setState(() => _showSolo = !_showSolo),
                ),
                IconButton(
                  tooltip: state.pair.isEmpty
                      ? 'Show ratings for a color pair'
                      : 'Hide pair ratings',
                  icon: Icon(
                    Icons.palette_outlined,
                    color: state.pair.isEmpty
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                  onPressed: () => context.read<ArenaDraftCubit>().togglePair(),
                ),
                if (state.pair.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Choose color pair',
                    // A popup sizes its own menu, so the button stays as small as the dots
                    onSelected: (v) =>
                        context.read<ArenaDraftCubit>().setPairManually(v),
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
            tooltip: 'Deck detection diagnostics',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => _showDiagnostics(context),
          ),
          IconButton(
            tooltip: 'Clear tracked draft',
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<ArenaDraftCubit>().clearDraft(),
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
      body: BlocBuilder<ArenaDraftCubit, ArenaDraftState>(
        builder: (context, state) {
          // Auto detection failed, let the user paste the log path
          if (!state.connected) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state.error ?? 'Connecting...'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'Path to Player.log',
                        hintText:
                            '~/Games/Heroic/Prefixes/default/MTGArena/pfx/drive_c/users/.../Player.log',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.read<ArenaDraftCubit>().start(
                        logPath: _pathController.text.trim(),
                      ),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildDonePool(state.pool, state.sideboard)),
              _buildVSplitter(),
              SizedBox(
                width: _panelWidth(state),
                child: _buildRankPanel(state),
              ),
            ],
          );
        },
      ),
    );
  }

  // Shows what the log parser found, so tracking problems can be diagnosed
  void _showDiagnostics(BuildContext context) {
    final cubit = context.read<ArenaDraftCubit>();
    final s = cubit.state;
    final summary = StringBuffer()
      ..writeln('set ${s.setCode} ${s.eventType}')
      ..writeln('draft id ${cubit.draftId.isEmpty ? "none" : cubit.draftId}')
      ..writeln(
        'pool ${cubit.poolCount} · maindeck ${s.pool.length} · sideboard ${s.sideboard.length}',
      )
      ..writeln('deck detected ${cubit.deckApplied}')
      ..writeln('log ${s.logPath}')
      ..writeln('')
      ..writeln('Parsed events, newest last:')
      ..writeln(
        cubit.parsedEvents.isEmpty ? '(none)' : cubit.parsedEvents.join('\n'),
      )
      ..writeln('')
      ..writeln('Recent lines mentioning a deck:')
      ..writeln(
        cubit.deckLines.isEmpty ? '(none)' : cubit.deckLines.join('\n\n'),
      );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tracking diagnostics'),
        content: SizedBox(
          width: 900,
          child: SingleChildScrollView(
            child: SelectableText(
              summary.toString(),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Pack ranks on top, then picks, and a sideboard table once Arena reports one
  // The pack table disappears when there is nothing left to pick
  Widget _buildRankPanel(ArenaDraftState state) {
    final hasSide = state.sideboard.isNotEmpty;
    final hasPack = state.pack.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final packH = hasPack ? splitSize(h, _rankSplit) : 0.0;
        final rest = hasPack ? h - packH - 22 : h;
        return Column(
          children: [
            if (hasPack) ...[
              SizedBox(
                height: packH,
                child: _rankPair(
                  state,
                  _buildRankTable(context, 'Pack', state.pack),
                  _buildPairTable(context, state, state.pack),
                ),
              ),
              _buildRankSplitter(h),
            ],
            if (!hasSide)
              Expanded(
                child: _rankPair(
                  state,
                  _buildRankTable(
                    context,
                    state.setCode.isEmpty
                        ? 'Waiting for a draft in Arena'
                        : 'Your picks',
                    state.pool,
                  ),
                  _buildPairTable(context, state, state.pool),
                ),
              )
            else ...[
              SizedBox(
                height: splitSize(rest, _sideSplit),
                child: _rankPair(
                  state,
                  _buildRankTable(context, 'Your picks', state.pool),
                  _buildPairTable(context, state, state.pool),
                ),
              ),
              _buildSideSplitter(rest),
              Expanded(
                child: _buildRankTable(context, 'Sideboard', state.sideboard),
              ),
            ],
          ],
        );
      },
    );
  }

  // Drag to change the split between the picks table and the sideboard table
  Widget _buildSideSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _sideSplit = snapTo(_sideSplit, 0.2, 0.85)),
        onVerticalDragUpdate: (d) => setState(() {
          _sideSplit = (_sideSplit + d.delta.dy / totalHeight).clamp(0.2, 0.85);
        }),
        child: SizedBox(
          // Tall grab area, the visible bar stays thin
          height: 22,
          child: Center(
            child: Container(
              width: 80,
              height: 4,
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

  Widget _buildRankTable(
    BuildContext context,
    String title,
    List<CardRating> cards,
  ) {
    final ranked = _ranked(cards);
    return LayoutBuilder(
      builder: (context, box) {
        // Dragged small, the header alone wouldn't fit, so it is dropped
        final showHeader = box.maxHeight >= 70;
        return Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 22),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    _headerCell('GIH', RankStat.gihwr),
                    _headerCell('IWD', RankStat.iwd),
                    _headerCell('ALSA', RankStat.alsa),
                  ],
                ),
              ),
            if (showHeader) const Divider(height: 1),
            Expanded(
              child: ranked.isEmpty
                  ? const Center(child: Text('Nothing yet'))
                  : ListView.builder(
                      itemCount: ranked.length,
                      itemBuilder: (context, i) =>
                          _rankRow(context, i + 1, ranked[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  // Pairs ordered by how strong their playables are, unrated ones last
  List<String> _pairsByRating(ArenaDraftState state) {
    return [...ArenaDraftCubit.pairs]..sort(
      (a, b) =>
          (state.pairAverages[b] ?? -1).compareTo(state.pairAverages[a] ?? -1),
    );
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
            decoration: BoxDecoration(
              color: _manaColor(letter),
              shape: BoxShape.circle,
            ),
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
        gradient: LinearGradient(
          colors: [
            _manaColor(pair[0]).withValues(alpha: alpha),
            _manaColor(pair[1]).withValues(alpha: alpha),
          ],
        ),
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

  // The pair where this card is best, when that beats the chosen pair and overall
  // The pair this card performs best in, whichever that is
  (String, double)? _topPair(ArenaDraftState state, CardRating card) {
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
  (String, double)? _betterPair(ArenaDraftState state, CardRating card) {
    final top = _topPair(state, card);
    if (top == null || top.$1 == state.pair) return null;
    final current = state.pairRatings[card.name];
    if (current != null && top.$2 <= current) return null;
    return top;
  }

  // Both tables use the same row height and badge slot, so their rows line up
  static const double rankRowHeight = 44;
  static const double badgeSlotHeight = 18;

  Widget _badgeSlot(Widget? badge) => SizedBox(
    height: badgeSlotHeight,
    child: badge == null ? null : Center(child: badge),
  );

  // The card's best pair, for the overall table
  Widget _topPairSlot(ArenaDraftState state, CardRating card) {
    final top = _topPair(state, card);
    return _badgeSlot(
      top == null ? null : _pairBadge(top.$1, top.$2, faded: true),
    );
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
  Widget _buildPairTable(
    BuildContext context,
    ArenaDraftState state,
    List<CardRating> cards,
  ) {
    final ranked = List<CardRating>.from(cards)
      ..sort(
        (a, b) => (state.pairRatings[b.name] ?? -1).compareTo(
          state.pairRatings[a.name] ?? -1,
        ),
      );
    return LayoutBuilder(
      builder: (context, box) {
        final showHeader = box.maxHeight >= 70;
        return Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 22),
                    Expanded(
                      // Wraps and clips rather than overflowing when dragged narrow
                      child: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'In pair',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          // How strong the pair's best commons and uncommons are
                          if (state.pairAverage != null)
                            Text(
                              'top20 ${(state.pairAverage! * 100).toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                        'vs GIH',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _pairDots(state.pair, size: 12),
                      ),
                    ),
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
                  ? const Center(child: Text('Nothing yet'))
                  : ListView.builder(
                      itemCount: ranked.length,
                      itemBuilder: (context, i) =>
                          _pairRow(context, state, i + 1, ranked[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _pairRow(
    BuildContext context,
    ArenaDraftState state,
    int rank,
    CardRating card,
  ) {
    final stats = Theme.of(context).textTheme.bodySmall;
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: Container(
        height: rankRowHeight,
        decoration: _rowDecoration(card.color),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 22, child: Text('$rank', style: stats)),
            Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
            // The overall rating, colored by how it compares to the pair
            SizedBox(
              width: 62,
              child: Align(
                alignment: Alignment.centerRight,
                child: _gihCompare(card, state.pairRatings[card.name]),
              ),
            ),
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _pairBadge(state.pair, state.pairRatings[card.name]),
                  _badgeSlot(
                    _betterPair(state, card) == null
                        ? null
                        : _pairBadge(
                            _betterPair(state, card)!.$1,
                            _betterPair(state, card)!.$2,
                            faded: true,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, RankStat stat) {
    final selected = _rankStat == stat;
    return InkWell(
      onTap: () => setState(() => _rankStat = stat),
      child: SizedBox(
        width: 62,
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

  Widget _rankRow(BuildContext context, int rank, CardRating card) {
    final stats = Theme.of(context).textTheme.bodySmall;
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: Container(
        height: rankRowHeight,
        decoration: _rowDecoration(card.color),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 22, child: Text('$rank', style: stats)),
            Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(card.gihwrLabel, style: stats),
                  ),
                  // The pair this card is best in, so the ceiling is visible
                  _topPairSlot(context.read<ArenaDraftCubit>().state, card),
                ],
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                card.iwdLabel,
                style: stats,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                card.alsaLabel,
                style: stats,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Color chips filtering both the main deck and sideboard curves
  // Colorless cards and lands always show since any deck can play them
  Widget _buildColorFilter() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in ['W', 'U', 'B', 'R', 'G'])
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () => setState(
                () => _colorFilter.contains(c)
                    ? _colorFilter.remove(c)
                    : _colorFilter.add(c),
              ),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorFilter.contains(c)
                      ? _manaColor(c)
                      : _manaColor(c).withValues(alpha: 0.25),
                ),
                child: Text(
                  c,
                  style: TextStyle(
                    fontSize: 12,
                    color: _colorFilter.contains(c) ? Colors.black : null,
                    fontWeight: _colorFilter.contains(c)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<CardRating> _colorFiltered(List<CardRating> cards) {
    if (_colorFilter.isEmpty) return cards;
    return [
      for (final c in cards)
        if (c.color.isEmpty || c.color.split('').every(_colorFilter.contains))
          c,
    ];
  }

  // Main deck left, sideboard right, split draggable
  Widget _buildDonePool(List<CardRating> pool, List<CardRating> sideboard) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: splitSize(constraints.maxWidth, _doneSplit),
            child: _curve(
              _colorFiltered(pool),
              showTargets: true,
              emptyText: 'No picks tracked yet',
              onSecondary: context.read<ArenaDraftCubit>().toSideboard,
            ),
          ),
          _buildDoneSplitter(constraints.maxWidth),
          Expanded(
            child: _curve(
              _colorFiltered(sideboard),
              showTargets: false,
              emptyText: 'Sideboard follows your Arena deck',
              onSecondary: context.read<ArenaDraftCubit>().toPool,
            ),
          ),
        ],
      ),
    );
  }

  // Drag to change the split between main deck and sideboard
  Widget _buildDoneSplitter(double totalWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _doneSplit = snapTo(_doneSplit, 0.2, 0.85)),
        onHorizontalDragUpdate: (d) => setState(() {
          _doneSplit = (_doneSplit + d.delta.dx / totalWidth).clamp(0.2, 0.85);
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

  // Curve view: lands far left, columns by cost with spells on top, creatures below
  // Cards scale to fit so every column from lands to 6+ stays visible
  // Read only, the split mirrors the deck built in Arena
  Widget _curve(
    List<CardRating> cards, {
    required bool showTargets,
    required String emptyText,
    void Function(CardRating)? onSecondary,
  }) {
    if (cards.isEmpty) return Center(child: Text(emptyText));
    final lands = _sortedPool(cards.where((c) => c.isLand).toList());
    final costs = List.generate(7, (i) => i);
    final spellRows = [
      for (final c in costs)
        _sortedPool(
          cards
              .where((x) => !x.isLand && !_isCreature(x) && _bucketOf(x) == c)
              .toList(),
        ),
    ];
    final creatureRows = [
      for (final c in costs)
        _sortedPool(
          cards
              .where((x) => !x.isLand && _isCreature(x) && _bucketOf(x) == c)
              .toList(),
        ),
    ];
    int maxLen(List<List<CardRating>> rows) =>
        rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final maxTop = maxLen(spellRows);
    final maxBottom = maxLen(
      [
        creatureRows,
        [lands],
      ].expand((e) => e).toList(),
    );
    final totalCreatures = creatureRows.fold(0, (s, r) => s + r.length);
    final totalSpells = spellRows.fold(0, (s, r) => s + r.length);
    final nonLands = cards.where((c) => !c.isLand).toList();
    final avgCost = nonLands.isEmpty
        ? null
        : nonLands.fold(0.0, (s, c) => s + _costOf(c)) / nonLands.length;
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
                      child: _cardStack(lands, w, offset, onSecondary),
                    ),
                  ),
                  _columnLabel(
                    'Lands',
                    lands.length,
                    showTargets ? (16, 18) : null,
                  ),
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
                            child: _cardStack(
                              spellRows[c],
                              w,
                              offset,
                              onSecondary,
                              draggable: showTargets,
                            ),
                          ),
                        ),
                      ),
                    if (showTargets && topH > 0)
                      _rowCount(
                        spellRows[c].length + creatureRows[c].length,
                        _combinedRange(c),
                      ),
                    if (topH > 0 && bottomH > 0) const SizedBox(height: 4),
                    if (bottomH > 0)
                      _costTarget(
                        c,
                        true,
                        SizedBox(
                          height: bottomH,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _cardStack(
                              creatureRows[c],
                              w,
                              offset,
                              onSecondary,
                              draggable: showTargets,
                            ),
                          ),
                        ),
                      ),
                    if (showTargets && bottomH > 0)
                      _rowCount(creatureRows[c].length, _creatureRange(c)),
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
                        Text(
                          'Picked ${cards.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        _totalLabel('Creatures', totalCreatures, (14, 17)),
                        _totalLabel('Noncreatures', totalSpells, (6, 9)),
                        _avgCostLabel(avgCost),
                      ],
                    )
                  : Text(
                      'Sideboard ${cards.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
            ),
            Expanded(child: SingleChildScrollView(child: grid)),
          ],
        );
      },
    );
  }

  // Cost the deck should count this card as, after any manual move
  int _bucketOf(CardRating card) => _costOverride[card.name] ?? card.costBucket;

  bool _isCreature(CardRating card) =>
      _typeOverride[card.name] ?? card.isCreature;

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

  double _costOf(CardRating card) =>
      (_costOverride[card.name] ?? card.cmc).toDouble();

  // Cards can be dragged sideways onto another cost column, which overrides the
  // cost used for the curve and the average
  Widget _maybeDraggable(
    CardRating card,
    double w,
    bool enabled,
    Widget child,
  ) {
    if (!enabled) return child;
    return Draggable<CardRating>(
      data: card,
      affinity: Axis.horizontal,
      feedback: Opacity(
        opacity: 0.85,
        child: SizedBox(
          width: w,
          child: cardImage(card, width: w, decodeWidth: w),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: child,
    );
  }

  // Largest card width that keeps all eight columns and both rows in view
  double _fitCardWidth(
    BoxConstraints box,
    int maxTop,
    int maxBottom,
    bool showTargets,
  ) {
    const columns = 8;
    final byWidth = (box.maxWidth - 8) / columns;
    // Room for the two row counts, the cost label and a wrapped header
    final labels = showTargets ? 96.0 : 30.0;
    final rows =
        (maxTop == 0 ? 0.0 : 1.4 + 0.15 * (maxTop - 1)) +
        (maxBottom == 0 ? 0.0 : 1.4 + 0.15 * (maxBottom - 1));
    final byHeight = rows <= 0 ? byWidth : (box.maxHeight - labels) / rows;
    final fit = byWidth < byHeight ? byWidth : byHeight;
    final preferred = _cardSize * 0.47;
    return (fit < preferred ? fit : preferred).clamp(24.0, 400.0);
  }

  // Cards stacked with their title bars visible
  Widget _cardStack(
    List<CardRating> cards,
    double w,
    double offset,
    void Function(CardRating)? onSecondary, {
    bool draggable = false,
  }) {
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
                    onSecondary: onSecondary == null
                        ? null
                        : () => onSecondary(cards[i]),
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
      child: Text(
        '$count/${_rangeLabel(range)}',
        style: TextStyle(fontSize: 10, color: _rangeColor(count, range)),
      ),
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
        Text(
          '$count/${_rangeLabel(range)}',
          style: TextStyle(fontSize: 11, color: _rangeColor(count, range)),
        ),
      ],
    );
  }

  // Red outside the range, yellow inside it, green on the recommended amount
  Color _rangeColor(int count, (int, int) range) {
    if (count < range.$1 || count > range.$2) return const Color(0xFFD9534F);
    final mid = (range.$1 + range.$2) / 2;
    if (count == mid.floor() || count == mid.ceil()) {
      return const Color(0xFF4CAF6D);
    }
    return const Color(0xFFE0B33C);
  }

  // 5(4-6) or 2.5(2-3), middle first, one decimal only when it isn't whole
  String _rangeLabel((int, int) range) {
    final mid = (range.$1 + range.$2) / 2;
    final label = mid == mid.roundToDouble()
        ? mid.round().toString()
        : mid.toStringAsFixed(1);
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
      style: TextStyle(
        fontSize: 12,
        color: ok ? const Color(0xFF4CAF6D) : null,
      ),
    );
  }

  // Overall ranking beside the pair ranking, either side can be absent
  Widget _rankPair(ArenaDraftState state, Widget solo, Widget pair) {
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
  double _panelWidth(ArenaDraftState state) {
    if (state.pair.isEmpty) return _rankWidth;
    return _showSolo ? _rankWidth + _pairWidth + 14 : _pairWidth;
  }

  // Drag to resize the pair table only, the first table keeps its width
  Widget _buildPairSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            setState(() => _pairWidth = snapTo(_pairWidth, 214.0, 700.0)),
        onHorizontalDragUpdate: (d) => setState(() {
          _pairWidth = (_pairWidth - d.delta.dx).clamp(214.0, 700.0);
        }),
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 3,
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

  Widget _buildVSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            setState(() => _rankWidth = snapTo(_rankWidth, 300.0, 700.0)),
        onHorizontalDragUpdate: (d) => setState(() {
          _rankWidth = (_rankWidth - d.delta.dx).clamp(300.0, 700.0);
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

  // Drag to change the split between the pack table and the picks table
  Widget _buildRankSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            setState(() => _rankSplit = snapTo(_rankSplit, 0.15, 0.85)),
        onVerticalDragUpdate: (d) => setState(() {
          _rankSplit = (_rankSplit + d.delta.dy / totalHeight).clamp(
            0.15,
            0.85,
          );
        }),
        child: SizedBox(
          // Tall grab area, the visible bar stays thin
          height: 22,
          child: Center(
            child: Container(
              width: 80,
              height: 4,
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

  List<CardRating> _sortedPool(List<CardRating> pool) {
    final sorted = List<CardRating>.from(pool)
      ..sort((a, b) {
        final c = a.color.compareTo(b.color);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return sorted;
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
