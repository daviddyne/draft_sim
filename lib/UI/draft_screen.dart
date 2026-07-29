import 'dart:io';

import 'package:draft_sim/Logic/draft_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'browse_screen.dart';
import 'live_draft_screen.dart';

enum RankStat { gihwr, iwd, alsa }

// Card image from the network, or from a downloaded file when the set is cached
// Shows a named placeholder if the image can't be loaded
Widget cardImage(CardRating card, {double? width, BoxFit? fit}) {
  Widget fallback(BuildContext context, Object error, StackTrace? stack) => SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: 0.716,
          child: Container(
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            color: const Color(0xFF3A2F5C),
            child: Text(card.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ),
        ),
      );
  if (!card.imageUrl.startsWith('http')) {
    return Image.file(File(card.imageUrl), width: width, fit: fit, errorBuilder: fallback);
  }
  return Image.network(card.imageUrl, width: width, fit: fit, errorBuilder: fallback);
}

class DraftScreen extends StatelessWidget {
  // Optional, lets other screens open the draft setup ready for a set
  final String? setCode;
  final String? eventType;

  const DraftScreen({super.key, this.setCode, this.eventType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DraftCubit(SeventeenLandsService()),
      child: _DraftView(setCode: setCode, eventType: eventType),
    );
  }
}

// Wraps any widget and shows a big card image with stats while hovering
class HoverZoom extends StatefulWidget {
  final CardRating card;
  final Widget child;
  // Keeps the preview's right edge this far from the screen edge
  final double rightInset;
  final double zoomWidth;
  final bool enabled;

  const HoverZoom({
    super.key,
    required this.card,
    required this.child,
    this.rightInset = 0,
    this.zoomWidth = 350,
    this.enabled = true,
  });

  @override
  State<HoverZoom> createState() => _HoverZoomState();
}

class _HoverZoomState extends State<HoverZoom> {
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _show(PointerEnterEvent event) {
    if (!widget.enabled) return;
    _hide();
    final screen = MediaQuery.of(context).size;
    // Place the preview beside the hovered widget so it never covers it
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final rightLimit = screen.width - widget.rightInset;
    final spaceRight = rightLimit - rect.right - 16;
    final spaceLeft = rect.left - 16;
    var width = widget.zoomWidth;
    double left;
    if (spaceRight >= width) {
      left = rect.right + 8;
    } else if (spaceLeft >= width) {
      left = rect.left - width - 8;
    } else if (spaceRight >= spaceLeft) {
      // No side fits the full preview, shrink it into the bigger gap
      width = spaceRight.clamp(120.0, widget.zoomWidth);
      left = rect.right + 8;
    } else {
      width = spaceLeft.clamp(120.0, widget.zoomWidth);
      left = rect.left - width - 8;
    }
    // Card images are roughly 1.4 times taller than wide, plus the stats row
    final height = (width * 1.4 + 44).clamp(0.0, screen.height - 16);
    final top = (event.position.dy - height / 2).clamp(8.0, screen.height - height - 8);
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: width,
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Constrained so the preview never runs off short screens
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height - 44),
                    child: cardImage(widget.card, width: width, fit: BoxFit.contain),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'GIH ${widget.card.gihwrLabel}   IWD ${widget.card.iwdLabel}   ALSA ${widget.card.alsaLabel}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _show,
      onExit: (_) => _hide(),
      child: widget.child,
    );
  }
}

class _DraftView extends StatefulWidget {
  final String? setCode;
  final String? eventType;

  const _DraftView({this.setCode, this.eventType});

  @override
  State<_DraftView> createState() => _DraftViewState();
}

class _DraftViewState extends State<_DraftView> {
  final _setController = TextEditingController();
  String? _selectedCode;
  String _eventType = 'PremierDraft';
  // Offline downloads
  final SeventeenLandsService _downloadService = SeventeenLandsService();
  List<CachedSet> _cached = [];
  String? _downloadStatus;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    // Opened from another screen with a set already chosen
    if (widget.setCode != null) _setController.text = widget.setCode!;
    if (widget.eventType != null) _eventType = widget.eventType!;
    _refreshCached();
  }

  Future<void> _refreshCached() async {
    final list = await _downloadService.cache.listCached();
    if (mounted) setState(() => _cached = list);
  }

  // Replaces the stored stats with the latest, keeps the downloaded art
  Future<void> _updateSet(String setCode, String eventType) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadStatus = 'Updating $setCode...';
    });
    try {
      final count = await _downloadService.downloadSet(
        setCode,
        eventType,
        onProgress: (done, total) {
          if (mounted) setState(() => _downloadStatus = 'Downloading images $done/$total');
        },
      );
      if (mounted) setState(() => _downloadStatus = 'Updated $setCode with $count cards');
    } catch (e) {
      if (mounted) setState(() => _downloadStatus = 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
      await _refreshCached();
    }
  }

  Future<void> _downloadSet() async {
    final code = _setController.text.trim();
    if (code.isEmpty || _downloading) return;
    setState(() {
      _downloading = true;
      _downloadStatus = 'Downloading $code...';
    });
    try {
      final count = await _downloadService.downloadSet(
        code,
        _eventType,
        onProgress: (done, total) {
          if (mounted) setState(() => _downloadStatus = 'Downloading images $done/$total');
        },
      );
      if (mounted) setState(() => _downloadStatus = 'Saved $count cards for ${code.toUpperCase()}');
    } catch (e) {
      if (mounted) setState(() => _downloadStatus = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
      await _refreshCached();
    }
  }
  RankStat _rankStat = RankStat.gihwr;
  // Card size in the pack grid, the pick area scales along with it
  double _cardSize = 240;
  // Width of the hover zoom preview
  double _zoomSize = 350;
  bool _zoomEnabled = true;
  // Height of the picked cards area, adjusted by dragging the splitter
  double _poolHeight = 320;
  // Width of the ranking panel, adjusted by dragging the vertical splitter
  double _rankWidth = 420;
  // Vertical split between the pack table and the picks table
  double _rankSplit = 0.6;

  @override
  void dispose() {
    _setController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<DraftCubit, DraftState>(
          builder: (context, state) {
            if (state.packNumber == 0) return const Text('17lands Draft Sim');
            if (state.finished) return const Text('Draft complete');
            return Text('Pack ${state.packNumber} · Pick ${state.pickNumber}');
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Browse this set',
            icon: const Icon(Icons.manage_search),
            onPressed: () {
              final code = _setController.text.trim();
              if (code.isEmpty) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BrowseScreen(setCode: code, eventType: _eventType),
              ));
            },
          ),
          IconButton(
            tooltip: 'Abandon draft and pick another set',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.read<DraftCubit>().reset(),
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
      body: BlocBuilder<DraftCubit, DraftState>(
        builder: (context, state) {
          if (state.loading) return const Center(child: CircularProgressIndicator());
          if (state.packNumber == 0) return _buildSetup(context, state.error, state.sets);
          if (state.finished) return _buildFinished(state.playerPool, state.sideboard);
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildPack(context, state.currentPack)),
                    _buildVSplitter(),
                    SizedBox(
                      width: _rankWidth,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Column(
                          children: [
                            SizedBox(
                              height: (constraints.maxHeight * _rankSplit - 5).clamp(0.0, constraints.maxHeight - 10),
                              child: _buildRankTable(context, 'Pack', state.currentPack, pickable: true),
                            ),
                            _buildRankSplitter(constraints.maxHeight),
                            Expanded(child: _buildRankTable(context, 'Your picks', state.playerPool, pickable: false)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSplitter(),
              SizedBox(height: _poolHeight, child: _buildPool(state.playerPool, state.sideboard)),
            ],
          );
        },
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

  // Drag to resize the picked cards area
  Widget _buildSplitter() {
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

  Widget _buildSetup(BuildContext context, String? error, List<SetOption> sets) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (sets.isNotEmpty)
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Select a set'),
                value: _selectedCode,
                // Reload on open so a newly released set appears without a restart
                onTap: () => context.read<DraftCubit>().refreshSets(),
                items: [
                  for (final s in sets)
                    DropdownMenuItem(
                      value: s.code,
                      child: Text('${s.name} (${s.code})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                // Selecting fills the code field, which stays the source of truth
                onChanged: (v) => setState(() {
                  _selectedCode = v;
                  _setController.text = v ?? '';
                }),
              )
            else
              const Text('Loading set list...'),
            const SizedBox(height: 12),
            TextField(
              controller: _setController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Or type a set code (e.g. MSH)'),
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _eventType,
              items: const [
                DropdownMenuItem(value: 'PremierDraft', child: Text('Premier Draft')),
                DropdownMenuItem(value: 'QuickDraft', child: Text('Quick Draft')),
                DropdownMenuItem(value: 'TradDraft', child: Text('Traditional Draft')),
              ],
              onChanged: (v) => setState(() => _eventType = v!),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.read<DraftCubit>().startDraft(_setController.text.trim(), eventType: _eventType),
              child: const Text('Start draft'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                final code = _setController.text.trim();
                if (code.isEmpty) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BrowseScreen(setCode: code, eventType: _eventType),
                ));
              },
              child: const Text('Browse cards'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LiveDraftScreen(),
              )),
              child: const Text('Track Arena draft'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _downloading ? null : _downloadSet,
              icon: const Icon(Icons.download),
              label: const Text('Download set for offline use'),
            ),
            if (_downloadStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_downloadStatus!, style: Theme.of(context).textTheme.bodySmall),
              ),
            if (_cached.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Available offline', style: Theme.of(context).textTheme.labelLarge),
              for (final c in _cached)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${c.setCode} · ${c.eventType} · ${c.cardCount} cards'),
                  subtitle: Text('Downloaded ${c.downloaded.toString().split('.').first}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Update stats to the latest',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: _downloading ? null : () => _updateSet(c.setCode, c.eventType),
                      ),
                      IconButton(
                        tooltip: 'Delete download',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await _downloadService.cache.delete(c.setCode, c.eventType);
                          await _refreshCached();
                        },
                      ),
                    ],
                  ),
                  // Tapping a download goes straight to browsing that set
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BrowseScreen(setCode: c.setCode, eventType: c.eventType),
                  )),
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  // Left click picks to the pool, right click picks straight to the sideboard
  Widget _buildPack(BuildContext context, List<CardRating> pack) {
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
          child: GestureDetector(
            onSecondaryTap: () => context.read<DraftCubit>().pickCard(card, toSide: true),
            child: InkWell(
              onTap: () => context.read<DraftCubit>().pickCard(card),
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

  // Ranked table like the 17lands Arena overlay
  // Tap a column header to rank by that stat, pickable rows pick the card on tap
  Widget _buildRankTable(BuildContext context, String title, List<CardRating> cards, {required bool pickable}) {
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
              ? const Center(child: Text('No picks yet'))
              : ListView.builder(
                  itemCount: ranked.length,
                  itemBuilder: (context, i) => _rankRow(context, i + 1, ranked[i], pickable: pickable),
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

  Widget _rankRow(BuildContext context, int rank, CardRating card, {required bool pickable}) {
    final stats = Theme.of(context).textTheme.bodySmall;
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: GestureDetector(
        onSecondaryTap: pickable ? () => context.read<DraftCubit>().pickCard(card, toSide: true) : null,
        child: InkWell(
          onTap: pickable ? () => context.read<DraftCubit>().pickCard(card) : null,
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
        ),
      ),
    );
  }

  // Whole row tinted with the card's colors, gradient for multicolor
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

  // Small mana dots so the card's colors are visible at a glance
  Widget _colorPips(String color) {
    final letters = color.isEmpty ? ['C'] : color.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in letters)
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(color: _manaColor(l), shape: BoxShape.circle),
          ),
      ],
    );
  }

  // Main deck curve on the left half, sideboard curve on the right half
  Widget _buildPool(List<CardRating> pool, List<CardRating> sideboard) {
    final cubit = context.read<DraftCubit>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _curve(pool, onSecondary: cubit.toSideboard, showTargets: true, emptyText: 'No picks yet')),
        Container(width: 2, color: Theme.of(context).dividerColor),
        Expanded(child: _curve(sideboard, onSecondary: cubit.toPool, showTargets: false, emptyText: 'Sideboard empty')),
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
    // Empty rows take no space, so no gap above the cost labels
    final topH = maxTop == 0 ? 0.0 : cardH + (maxTop - 1) * offset;
    final bottomH = maxBottom == 0 ? 0.0 : cardH + (maxBottom - 1) * offset;
    // Deck totals against a typical 16 creature / 7 noncreature split
    final totalCreatures = creatureRows.fold(0, (s, r) => s + r.length);
    final totalSpells = spellRows.fold(0, (s, r) => s + r.length);
    // Average cost of the nonland cards, lands would drag it toward zero
    final nonLands = cards.where((c) => !c.isLand).toList();
    final avgCost = nonLands.isEmpty ? null : nonLands.fold(0, (s, c) => s + c.cmc) / nonLands.length;
    final scroll = SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // No left padding so the piles start at the screen edge
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
                  _columnLabel(
                    c == 7 ? '7+' : '$c',
                    spellRows[c].length + creatureRows[c].length,
                    showTargets ? _curveTarget(c) : null,
                  ),
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
              const SizedBox(width: 12),
              Text(
                'Avg cost ${avgCost == null ? '-' : avgCost.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(child: scroll),
      ],
    );
  }

  // Deck total with recommended amount, green when met
  Widget _totalLabel(String label, int count, int target) {
    final met = count >= target;
    return Text(
      '$label $count/$target',
      style: TextStyle(fontSize: 12, color: met ? const Color(0xFF4CAF6D) : null),
    );
  }

  // Rough guideline for a 40 card deck with 17 lands and 23 spells
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

  // Cost label with the stack count against the recommended curve amount
  Widget _columnLabel(String label, int count, int? target) {
    if (target == null) return Text(label);
    final met = count >= target;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text(
          '$count/$target',
          style: TextStyle(fontSize: 11, color: met ? const Color(0xFF4CAF6D) : null),
        ),
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

  Widget _buildFinished(List<CardRating> pool, List<CardRating> sideboard) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final card in _sortedPool(pool)) _finishedTile(card),
        if (sideboard.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Sideboard', style: Theme.of(context).textTheme.titleMedium),
          ),
        for (final card in _sortedPool(sideboard)) _finishedTile(card),
      ],
    );
  }

  Widget _finishedTile(CardRating card) {
    return HoverZoom(
      card: card,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: ListTile(
        leading: cardImage(card, width: 44),
        title: Row(
          children: [
            _colorPips(card.color),
            const SizedBox(width: 6),
            Flexible(child: Text(card.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        subtitle: Text('GIH ${card.gihwrLabel} · IWD ${card.iwdLabel} · ALSA ${card.alsaLabel}'),
      ),
    );
  }

  List<CardRating> _ranked(List<CardRating> cards) {
    final sorted = List<CardRating>.from(cards);
    // Missing stats (low sample size) always sort to the bottom
    sorted.sort((a, b) => switch (_rankStat) {
      RankStat.gihwr => (b.gihwr ?? -1).compareTo(a.gihwr ?? -1),
      RankStat.iwd => (b.iwd ?? -9).compareTo(a.iwd ?? -9),
      RankStat.alsa => (a.alsa ?? 99).compareTo(b.alsa ?? 99),
    });
    return sorted;
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
}