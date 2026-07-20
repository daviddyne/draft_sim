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
      create: (_) => ArenaDraftCubit(SeventeenLandsService(), ArenaLogService())..start(),
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
  double _poolHeight = 320;
  double _rankWidth = 420;
  // Vertical split between the pack table and the picks table
  double _rankSplit = 0.6;
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
          builder: (context, state) => Text(
            state.setCode.isEmpty ? 'Arena · detecting set...' : 'Arena · ${state.setCode} ${state.eventType}',
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Browse this set',
            icon: const Icon(Icons.manage_search),
            onPressed: () {
              final s = context.read<ArenaDraftCubit>().state;
              if (s.setCode.isEmpty) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BrowseScreen(setCode: s.setCode, eventType: s.eventType),
              ));
            },
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
                        hintText: '~/Games/Heroic/Prefixes/default/MTGArena/pfx/drive_c/users/.../Player.log',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.read<ArenaDraftCubit>().start(logPath: _pathController.text.trim()),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            );
          }
          // All picks made: give the whole screen to the picked cards
          final done = state.pack.isEmpty && state.pool.length + state.sideboard.length >= 40;
          if (done) {
            return Column(
              children: [
                _buildStatus(context, state),
                _buildColorFilter(),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildDonePool(state.pool, state.sideboard)),
                      _buildVSplitter(),
                      SizedBox(
                        width: _rankWidth,
                        child: _buildRankTable(context, 'Your picks', [...state.pool, ...state.sideboard]),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              _buildStatus(context, state),
              _buildColorFilter(),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: state.pack.isEmpty
                          ? Center(
                              child: Text(state.setCode.isEmpty
                                  ? 'Waiting for a draft... join or continue one in Arena'
                                  : 'Waiting for a pack... open or pick in Arena'),
                            )
                          : _buildPack(state.pack),
                    ),
                    _buildVSplitter(),
                    SizedBox(
                      width: _rankWidth,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Column(
                          children: [
                            SizedBox(
                              height: (constraints.maxHeight * _rankSplit - 5).clamp(0.0, constraints.maxHeight - 10),
                              child: _buildRankTable(context, 'Pack', state.pack),
                            ),
                            _buildRankSplitter(constraints.maxHeight),
                            Expanded(child: _buildRankTable(context, 'Your picks', state.pool)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildHSplitter(),
              SizedBox(height: _poolHeight, child: _buildPool(state.pool, state.sideboard)),
            ],
          );
        },
      ),
    );
  }

  // Connection line: log path, live indicator and unmatched card warning
  Widget _buildStatus(BuildContext context, ArenaDraftState state) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: state.connected ? const Color(0xFF4CAF6D) : const Color(0xFFD9534F)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              state.connected ? 'Tracking ${state.logPath}' : 'Not connected',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.unknownIds > 0)
            Text(
              '${state.unknownIds} unmatched in pack (ids: ${state.unknownInfo})',
              style: style?.copyWith(color: const Color(0xFFD9534F)),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(state.error!, style: style?.copyWith(color: const Color(0xFFD9534F))),
            ),
        ],
      ),
    );
  }

  Widget _buildPack(List<CardRating> pack) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _cardSize,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: pack.length,
      itemBuilder: (context, i) {
        final card = pack[i];
        return HoverZoom(
          card: card,
          zoomWidth: _zoomSize,
          enabled: _zoomEnabled,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: cardImage(card, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Widget _buildRankTable(BuildContext context, String title, List<CardRating> cards) {
    final ranked = _ranked(cards);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              const SizedBox(width: 22),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
              _headerCell('GIH', RankStat.gihwr),
              _headerCell('IWD', RankStat.iwd),
              _headerCell('ALSA', RankStat.alsa),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ranked.isEmpty
              ? const Center(child: Text('Nothing yet'))
              : ListView.builder(
                  itemCount: ranked.length,
                  itemBuilder: (context, i) => _rankRow(context, i + 1, ranked[i]),
                ),
        ),
      ],
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
            Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            Icon(Icons.arrow_drop_down, size: 16, color: selected ? null : Colors.transparent),
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
        decoration: _rowDecoration(card.color),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            SizedBox(width: 22, child: Text('$rank', style: stats)),
            Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
            SizedBox(width: 62, child: Text(card.gihwrLabel, style: stats, textAlign: TextAlign.right)),
            SizedBox(width: 62, child: Text(card.iwdLabel, style: stats, textAlign: TextAlign.right)),
            SizedBox(width: 62, child: Text(card.alsaLabel, style: stats, textAlign: TextAlign.right)),
          ],
        ),
      ),
    );
  }

  // Color chips filtering both the main deck and sideboard curves
  // Colorless cards and lands always show since any deck can play them
  Widget _buildColorFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          Text('Colors', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 8),
          for (final c in ['W', 'U', 'B', 'R', 'G'])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilterChip(
                label: Text(c),
                visualDensity: VisualDensity.compact,
                selected: _colorFilter.contains(c),
                selectedColor: _manaColor(c).withValues(alpha: 0.5),
                onSelected: (on) => setState(() => on ? _colorFilter.add(c) : _colorFilter.remove(c)),
              ),
            ),
        ],
      ),
    );
  }

  List<CardRating> _colorFiltered(List<CardRating> cards) {
    if (_colorFilter.isEmpty) return cards;
    return [
      for (final c in cards)
        if (c.color.isEmpty || c.color.split('').every(_colorFilter.contains)) c,
    ];
  }

  // Finished layout: main deck on top, sideboard below, split draggable
  Widget _buildDonePool(List<CardRating> pool, List<CardRating> sideboard) {
    final cubit = context.read<ArenaDraftCubit>();
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          SizedBox(
            height: (constraints.maxHeight * _doneSplit - 5).clamp(0.0, constraints.maxHeight - 10),
            child: _curve(_colorFiltered(pool), onSecondary: cubit.toSideboard, showTargets: true, emptyText: 'No picks tracked yet'),
          ),
          _buildDoneSplitter(constraints.maxHeight),
          Expanded(
            child: _curve(_colorFiltered(sideboard), onSecondary: cubit.toPool, showTargets: false, emptyText: 'Sideboard empty'),
          ),
        ],
      ),
    );
  }

  // Drag to change the split between main deck and sideboard
  Widget _buildDoneSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          _doneSplit = (_doneSplit + d.delta.dy / totalHeight).clamp(0.15, 0.85);
        }),
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  // Main deck curve on the left half, planning sideboard on the right half
  Widget _buildPool(List<CardRating> pool, List<CardRating> sideboard) {
    final cubit = context.read<ArenaDraftCubit>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _curve(_colorFiltered(pool), onSecondary: cubit.toSideboard, showTargets: true, emptyText: 'No picks tracked yet')),
        Container(width: 2, color: Theme.of(context).dividerColor),
        Expanded(child: _curve(_colorFiltered(sideboard), onSecondary: cubit.toPool, showTargets: false, emptyText: 'Sideboard empty')),
      ],
    );
  }

  // Curve view: lands far left, columns by cost with spells on top and creatures below
  // Right click a card to move it to the other side
  Widget _curve(List<CardRating> cards, {required void Function(CardRating) onSecondary, required bool showTargets, required String emptyText}) {
    final w = _cardSize * 0.47;
    final offset = w * 0.15;
    final cardH = w * 1.4;
    if (cards.isEmpty) return Center(child: Text(emptyText));
    final lands = _sortedPool(cards.where((c) => c.isLand).toList());
    final costs = List.generate(8, (i) => i);
    final spellRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && !x.isCreature && x.costBucket == c).toList())];
    final creatureRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && x.isCreature && x.costBucket == c).toList())];
    int maxLen(List<List<CardRating>> rows) => rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final maxTop = maxLen(spellRows);
    final maxBottom = maxLen(creatureRows);
    final topH = maxTop == 0 ? 0.0 : cardH + (maxTop - 1) * offset;
    final bottomH = maxBottom == 0 ? 0.0 : cardH + (maxBottom - 1) * offset;
    final totalCreatures = creatureRows.fold(0, (s, r) => s + r.length);
    final totalSpells = spellRows.fold(0, (s, r) => s + r.length);
    final scroll = SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _cardStack(lands, w, offset, onSecondary),
                _columnLabel('Lands', lands.length, showTargets ? 17 : null),
              ],
            ),
            const SizedBox(width: 12),
            for (final c in costs) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (topH > 0)
                    SizedBox(
                      height: topH,
                      width: w,
                      child: Align(alignment: Alignment.bottomCenter, child: _cardStack(spellRows[c], w, offset, onSecondary)),
                    ),
                  if (topH > 0 && bottomH > 0) const SizedBox(height: 6),
                  if (bottomH > 0)
                    SizedBox(
                      height: bottomH,
                      width: w,
                      child: Align(alignment: Alignment.bottomCenter, child: _cardStack(creatureRows[c], w, offset, onSecondary)),
                    ),
                  _columnLabel(c == 7 ? '7+' : '$c', spellRows[c].length + creatureRows[c].length, showTargets ? _curveTarget(c) : null),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
    if (!showTargets) return scroll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
          child: Row(
            children: [
              _totalLabel('Creatures', totalCreatures, 16),
              const SizedBox(width: 12),
              _totalLabel('Noncreatures', totalSpells, 7),
            ],
          ),
        ),
        Expanded(child: scroll),
      ],
    );
  }

  // Cards stacked with their title bars visible, right click moves the card
  Widget _cardStack(List<CardRating> cards, double w, double offset, void Function(CardRating) onSecondary) {
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
                child: GestureDetector(
                  onSecondaryTap: () => onSecondary(cards[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: cardImage(cards[i], width: w),
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
    return Text(
      '$label $count/$target',
      style: TextStyle(fontSize: 12, color: met ? const Color(0xFF4CAF6D) : null),
    );
  }

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
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
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
        onVerticalDragUpdate: (d) => setState(() {
          _rankSplit = (_rankSplit + d.delta.dy / totalHeight).clamp(0.15, 0.85);
        }),
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => setState(() {
          _poolHeight = (_poolHeight - d.delta.dy).clamp(60.0, MediaQuery.of(context).size.height * 0.75);
        }),
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
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