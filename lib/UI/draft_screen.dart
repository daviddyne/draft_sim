import 'package:draft_sim/Logic/draft_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum RankStat { gihwr, iwd, alsa }

class DraftScreen extends StatelessWidget {
  const DraftScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DraftCubit(SeventeenLandsService()),
      child: const _DraftView(),
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

  const HoverZoom({
    super.key,
    required this.card,
    required this.child,
    this.rightInset = 0,
    this.zoomWidth = 520,
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
    final top = (event.position.dy - height / 2).clamp(
      8.0,
      screen.height - height - 8,
    );
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
                    child: Image.network(
                      widget.card.imageUrl,
                      width: width,
                      fit: BoxFit.contain,
                    ),
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
  const _DraftView();

  @override
  State<_DraftView> createState() => _DraftViewState();
}

class _DraftViewState extends State<_DraftView> {
  final _setController = TextEditingController();
  String _eventType = 'PremierDraft';
  RankStat _rankStat = RankStat.gihwr;
  // Card size in the pack grid, the pick strip scales along with it
  double _cardSize = 475;
  // Width of the hover zoom preview
  double _zoomSize = 520;

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
          const Icon(Icons.zoom_in, size: 18),
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
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.packNumber == 0) return _buildSetup(context, state.error);
          if (state.finished) return _buildFinished(state.playerPool);
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildPack(context, state.currentPack)),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 420,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildRankTable(
                              context,
                              'Pack',
                              state.currentPack,
                              pickable: true,
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            flex: 2,
                            child: _buildRankTable(
                              context,
                              'Your picks',
                              state.playerPool,
                              pickable: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: _cardSize * 0.47 * 1.4 + 44,
                child: _buildPool(state.playerPool),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSetup(BuildContext context, String? error) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _setController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Set code (e.g. MSH, DSK, LTR)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _eventType,
              items: const [
                DropdownMenuItem(
                  value: 'PremierDraft',
                  child: Text('Premier Draft'),
                ),
                DropdownMenuItem(
                  value: 'QuickDraft',
                  child: Text('Quick Draft'),
                ),
                DropdownMenuItem(
                  value: 'TradDraft',
                  child: Text('Traditional Draft'),
                ),
              ],
              onChanged: (v) => setState(() => _eventType = v!),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.read<DraftCubit>().startDraft(
                _setController.text.trim(),
                eventType: _eventType,
              ),
              child: const Text('Start draft'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
          child: InkWell(
            onTap: () => context.read<DraftCubit>().pickCard(card),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(card.imageUrl, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  // Ranked table like the 17lands Arena overlay
  // Tap a column header to rank by that stat, pickable rows pick the card on tap
  Widget _buildRankTable(
    BuildContext context,
    String title,
    List<CardRating> cards, {
    required bool pickable,
  }) {
    final ranked = _ranked(cards);
    return Column(
      children: [
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
        const Divider(height: 1),
        Expanded(
          child: ranked.isEmpty
              ? const Center(child: Text('No picks yet'))
              : ListView.builder(
                  itemCount: ranked.length,
                  itemBuilder: (context, i) =>
                      _rankRow(context, i + 1, ranked[i], pickable: pickable),
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

  Widget _rankRow(
    BuildContext context,
    int rank,
    CardRating card, {
    required bool pickable,
  }) {
    final stats = Theme.of(context).textTheme.bodySmall;
    return HoverZoom(
      card: card,
      rightInset: 428,
      zoomWidth: _zoomSize,
      child: InkWell(
        onTap: pickable
            ? () => context.read<DraftCubit>().pickCard(card)
            : null,
        child: Container(
          decoration: _rowDecoration(card.color),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              SizedBox(width: 22, child: Text('$rank', style: stats)),
              Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
              SizedBox(
                width: 62,
                child: Text(
                  card.gihwrLabel,
                  style: stats,
                  textAlign: TextAlign.right,
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
      ),
    );
  }

  // Whole row tinted with the card's colors, gradient for multicolor
  BoxDecoration _rowDecoration(String color) {
    final letters = color.isEmpty ? ['C'] : color.split('');
    final colors = [
      for (final l in letters) _manaColor(l).withValues(alpha: 0.35),
    ];
    if (colors.length == 1) return BoxDecoration(color: colors.first);
    return BoxDecoration(gradient: LinearGradient(colors: colors));
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
            decoration: BoxDecoration(
              color: _manaColor(l),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
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

  List<CardRating> _ranked(List<CardRating> pack) {
    final sorted = List<CardRating>.from(pack);
    // Missing stats (low sample size) always sort to the bottom
    sorted.sort(
      (a, b) => switch (_rankStat) {
        RankStat.gihwr => (b.gihwr ?? -1).compareTo(a.gihwr ?? -1),
        RankStat.iwd => (b.iwd ?? -9).compareTo(a.iwd ?? -9),
        RankStat.alsa => (a.alsa ?? 99).compareTo(b.alsa ?? 99),
      },
    );
    return sorted;
  }

  Widget _buildPool(List<CardRating> pool) {
    if (pool.isEmpty) return const Center(child: Text('No picks yet'));
    final sorted = _sortedPool(pool);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text(
            'Your picks (${pool.length})',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final card = sorted[i];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: HoverZoom(
                  card: card,
                  zoomWidth: _zoomSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      card.imageUrl,
                      width: _cardSize * 0.47,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFinished(List<CardRating> pool) {
    final sorted = _sortedPool(pool);
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final card = sorted[i];
        return HoverZoom(
          card: card,
          zoomWidth: _zoomSize,
          child: ListTile(
            leading: Image.network(card.imageUrl, width: 44),
            title: Row(
              children: [
                _colorPips(card.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(card.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Text(
              'GIH ${card.gihwrLabel} · IWD ${card.iwdLabel} · ALSA ${card.alsaLabel}',
            ),
          ),
        );
      },
    );
  }

  // Sorted by color then name so the pool is easy to scan
  List<CardRating> _sortedPool(List<CardRating> pool) {
    final sorted = List<CardRating>.from(pool)
      ..sort((a, b) {
        final c = a.color.compareTo(b.color);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return sorted;
  }
}
