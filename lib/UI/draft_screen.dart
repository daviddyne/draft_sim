import 'package:draft_sim/Logic/draft_cubit.dart';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/card_cache_service.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'browse_screen.dart';
import 'live_draft_screen.dart';

enum RankStat { gihwr, iwd, alsa }

// Downloaded art if the card has been cached, otherwise straight from the web
// Shows a named placeholder if the image can't be loaded at all
Widget cardImage(CardRating card, {double? width, BoxFit? fit, double? decodeWidth}) {
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
  // Decoding at roughly the displayed size keeps memory down on weaker devices.
  // Not on web: resizing there decodes the bytes itself, which needs CORS headers
  // the image host doesn't send, and the card would fail to load at all.
  final target = decodeWidth ?? width;
  final cacheWidth = kIsWeb || target == null ? null : (target * 1.5).round().clamp(64, 720);
  // Small art for small cards, the full image only for the zoom preview
  final url = (decodeWidth ?? width ?? 0) <= 260 ? card.gridImageUrl : card.imageUrl;
  final bytes = _imageCache.image(card.name);
  if (bytes != null) {
    // Isolated so repainting one card doesn't repaint the whole grid
    return RepaintBoundary(
      child: Image.memory(bytes, width: width, fit: fit, cacheWidth: cacheWidth, errorBuilder: fallback),
    );
  }
  return RepaintBoundary(
    child: Image.network(
      url,
      width: width,
      fit: fit,
      cacheWidth: cacheWidth,
      // On web the canvas renderer needs CORS headers the image host may not send,
      // so fall back to a plain img element, which has no such restriction
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: fallback,
    ),
  );
}

// Tapping a splitter throws it to whichever end is further away, so one tap
// collapses a panel and the next brings it back. From the middle it collapses.
double snapTo(double value, double min, double max) {
  return value > (min + max) / 2 ? min : max;
}

// Size for one side of a splitter, safe when the area is too small for both.
// clamp throws if the lower bound ends up above the upper one, which happens
// during layout passes where the height is still zero.
double splitSize(double total, double fraction) {
  final room = total - 22;
  if (room <= 0) return 0;
  final wanted = total * fraction - 11;
  return wanted < 0 ? 0 : (wanted > room ? room : wanted);
}

final _imageCache = CardCacheService();

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
  // Every mounted card, so a drag can find whichever one is under the finger
  static final Set<_HoverZoomState> _live = {};
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _live.add(this);
  }

  @override
  void dispose() {
    _live.remove(this);
    _hide();
    super.dispose();
  }

  // Card under the given screen position, if any.
  // Uses the framework hit test so cards scrolled out of view or covered by
  // another area aren't found, which a plain rectangle check would miss.
  _HoverZoomState? _at(Offset position) {
    final view = View.maybeOf(context);
    if (view == null) return null;
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, position, view.viewId);
    for (final entry in result.path) {
      for (final state in _live) {
        if (identical(state.context.findRenderObject(), entry.target)) return state;
      }
    }
    return null;
  }

  // Moves the preview to whatever card the finger is over now
  void _dragTo(Offset position) {
    final target = _at(position);
    if (target == null) return;
    if (target != this) {
      _hide();
      target._show(position);
    } else if (_entry == null) {
      _show(position);
    }
  }

  void _show(Offset pointer) {
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
    final top = (pointer.dy - height / 2).clamp(8.0, screen.height - height - 8);
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
                    child: cardImage(widget.card, width: width, fit: BoxFit.contain, decodeWidth: width),
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

  // A drag can leave the preview owned by another card
  static void _hideAll() {
    for (final state in _live) {
      state._hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (e) => _show(e.position),
      onExit: (_) => _hide(),
      // Touch has no hover, so holding a card shows the preview instead
      // A short hold shows the preview, faster than the default long press
      child: RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 180)),
            (r) {
              r.onLongPressStart = (d) => _show(d.globalPosition);
              // Sliding onto another card previews that one instead
              r.onLongPressMoveUpdate = (d) => _dragTo(d.globalPosition);
              r.onLongPressEnd = (_) => _hideAll();
              r.onLongPressCancel = _hideAll;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }
}

// Card gestures shared by every screen: tap, right click, and a two finger tap
// standing in for right click on touch. Pointer events are used because a scale
// gesture loses to taps and scrolling in the gesture arena.
class CardGestures extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondary;

  const CardGestures({super.key, required this.child, this.onTap, this.onSecondary});

  @override
  State<CardGestures> createState() => _CardGesturesState();
}

class _CardGesturesState extends State<CardGestures> {
  int _pointers = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        _pointers++;
        if (_pointers >= 2 && !_fired && widget.onSecondary != null) {
          _fired = true;
          widget.onSecondary!();
        }
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: GestureDetector(
        // Skip the tap when the two finger gesture already handled it
        onTap: () => _fired ? null : widget.onTap?.call(),
        onSecondaryTap: widget.onSecondary,
        child: widget.child,
      ),
    );
  }

  void _release() {
    if (_pointers > 0) _pointers--;
    if (_pointers == 0 && _fired) {
      // Cleared after the tap would have resolved, so it stays suppressed
      Future.delayed(const Duration(milliseconds: 250), () => _fired = false);
    }
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

  String _eventLabel(String event) {
    return switch (event) {
      'PremierDraft' => 'Premier Draft',
      'QuickDraft' => 'Quick Draft',
      'TradDraft' => 'Traditional Draft',
      _ => event,
    };
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
  // Cards dragged to another cost column, keyed by card name
  final Map<String, int> _costOverride = {};
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
          BlocBuilder<DraftCubit, DraftState>(
            builder: (context, state) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: state.pair.isEmpty ? 'Show ratings for a color pair' : 'Hide pair ratings',
                  icon: Icon(Icons.palette_outlined,
                      color: state.pair.isEmpty ? Theme.of(context).disabledColor : null),
                  onPressed: () => context.read<DraftCubit>().togglePair(),
                ),
                if (state.pair.isNotEmpty)
                  DropdownButton<String>(
                    value: state.pair,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final p in DraftCubit.pairs)
                        DropdownMenuItem(value: p, child: _pairDots(p, size: 12)),
                    ],
                    onChanged: (v) => v == null ? null : context.read<DraftCubit>().setPair(v),
                  ),
              ],
            ),
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
          if (state.finished) return _buildFinished(state);
          return LayoutBuilder(
            builder: (context, box) {
              // Can take the whole area, only the drag handle has to stay visible
              final pool = _poolHeight.clamp(0.0, (box.maxHeight - 22).clamp(0.0, box.maxHeight));
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
                            builder: (context, inner) => Column(
                              children: [
                                SizedBox(
                                  height: splitSize(inner.maxHeight, _rankSplit),
                                  child: _buildRankTable(context, 'Pack', state.currentPack, pickable: true),
                                ),
                                _buildRankSplitter(inner.maxHeight),
                                Expanded(
                                  child: _buildRankTable(context, 'Your picks', state.playerPool, pickable: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildSplitter(),
                  SizedBox(height: pool, child: _buildPool(state.playerPool, state.sideboard)),
                ],
              );
            },
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
        onTap: () => setState(() => _rankSplit = snapTo(_rankSplit, 0.15, 0.85)),
        onVerticalDragUpdate: (d) => setState(() {
          _rankSplit = (_rankSplit + d.delta.dy / totalHeight).clamp(0.15, 0.85);
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

  // Drag to resize the ranking panel
  Widget _buildVSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _rankWidth = snapTo(_rankWidth, 300.0, 700.0)),
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

  // Drag to resize the picked cards area
  Widget _buildSplitter() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _poolHeight = snapTo(_poolHeight, 0.0, MediaQuery.of(context).size.height)),
        onVerticalDragUpdate: (d) => setState(() {
          _poolHeight = (_poolHeight - d.delta.dy).clamp(0.0, MediaQuery.of(context).size.height);
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
            Builder(builder: (context) {
              // Only offer formats the selected set actually has data for
              final match = sets.where((s) => s.code == _setController.text.trim()).toList();
              final available = match.isEmpty || match.first.events.isEmpty
                  ? const ['PremierDraft', 'QuickDraft', 'TradDraft']
                  : match.first.events;
              final value = available.contains(_eventType) ? _eventType : available.first;
              return DropdownButton<String>(
                value: value,
                items: [
                  for (final e in available)
                    DropdownMenuItem(value: e, child: Text(_eventLabel(e))),
                ],
                onChanged: (v) => setState(() => _eventType = v!),
              );
            }),
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
            // Arena tracking reads a log file, which a browser can't do
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const LiveDraftScreen(),
                )),
                child: const Text('Track Arena draft'),
              ),
            ],
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
          child: CardGestures(
            onTap: () => context.read<DraftCubit>().pickCard(card),
            onSecondary: () => context.read<DraftCubit>().pickCard(card, toSide: true),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: cardImage(card, fit: BoxFit.contain, decodeWidth: _cardSize),
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
                    Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
                    _headerCell('GIH', RankStat.gihwr),
                    _headerCell('IWD', RankStat.iwd),
                    _headerCell('ALSA', RankStat.alsa),
                  ],
                ),
              ),
            if (showHeader) const Divider(height: 1),
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
      },
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

  // Win rate within a pair, boxed in that pair's colors
  // faded marks an alternative pair rather than the chosen one
  Widget _pairBadge(String pair, double? wr, {bool faded = false}) {
    if (pair.isEmpty) return const SizedBox.shrink();
    final alpha = faded ? 0.2 : 0.4;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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
          Text(
            wr == null ? '-' : '${(wr * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  // The pair where this card is best, when that beats both the chosen pair and
  // its overall rating. Nothing to sort by, it's just worth knowing.
  (String, double)? _betterPair(DraftState state, CardRating card) {
    if (state.allPairRatings.isEmpty) return null;
    final current = state.pairRatings[card.name] ?? card.gihwr ?? 0;
    final overall = card.gihwr ?? 0;
    final floor = current > overall ? current : overall;
    String? bestPair;
    var bestWr = floor;
    for (final entry in state.allPairRatings.entries) {
      if (entry.key == state.pair) continue;
      final wr = entry.value[card.name];
      if (wr != null && wr > bestWr) {
        bestWr = wr;
        bestPair = entry.key;
      }
    }
    return bestPair == null ? null : (bestPair, bestWr);
  }

  Widget _rankRow(BuildContext context, int rank, CardRating card, {required bool pickable}) {
    final stats = Theme.of(context).textTheme.bodySmall;
    final state = context.read<DraftCubit>().state;
    return HoverZoom(
      card: card,
      rightInset: _rankWidth + 8,
      zoomWidth: _zoomSize,
      enabled: _zoomEnabled,
      child: CardGestures(
        onTap: pickable ? () => context.read<DraftCubit>().pickCard(card) : null,
        onSecondary: pickable ? () => context.read<DraftCubit>().pickCard(card, toSide: true) : null,
        child: Container(
          decoration: _rowDecoration(card.color),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              SizedBox(width: 22, child: Text('$rank', style: stats)),
              Expanded(child: Text(card.name, overflow: TextOverflow.ellipsis)),
              SizedBox(
                width: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Chosen pair on top, it's what the list is sorted by
                    if (state.pair.isNotEmpty) _pairBadge(state.pair, state.pairRatings[card.name]),
                    Text(card.gihwrLabel, style: stats),
                    if (state.pair.isNotEmpty)
                      if (_betterPair(state, card) case final better?)
                        _pairBadge(better.$1, better.$2, faded: true),
                  ],
                ),
              ),
              SizedBox(width: 62, child: Text(card.iwdLabel, style: stats, textAlign: TextAlign.right)),
              SizedBox(width: 62, child: Text(card.alsaLabel, style: stats, textAlign: TextAlign.right)),
            ],
          ),
        ),
      ),
    );
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


  // Main deck curve on the left half, sideboard curve on the right half
  Widget _buildPool(List<CardRating> pool, List<CardRating> sideboard, {List<CardRating> lands = const []}) {
    final cubit = context.read<DraftCubit>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _curve(pool,
              onSecondary: cubit.toSideboard,
              showTargets: true,
              emptyText: 'No picks yet',
              lands: lands,
              onAddLand: cubit.addLand),
        ),
        Container(width: 2, color: Theme.of(context).dividerColor),
        Expanded(child: _curve(sideboard, onSecondary: cubit.toPool, showTargets: false, emptyText: 'Sideboard empty')),
      ],
    );
  }

  // Curve view: lands far left, columns by cost with spells on top, creatures below
  // Cards scale to fit so every column from lands to 6+ stays visible
  // Right click or long press a card to move it to the other side
  Widget _curve(List<CardRating> cards, {
    required void Function(CardRating) onSecondary,
    required bool showTargets,
    required String emptyText,
    List<CardRating> lands = const [],
    void Function(CardRating)? onAddLand,
  }) {
    if (cards.isEmpty) return Center(child: Text(emptyText));
    final lands = _sortedPool(cards.where((c) => c.isLand).toList());
    final costs = List.generate(7, (i) => i);
    final spellRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && !x.isCreature && _bucketOf(x) == c).toList())];
    final creatureRows = [for (final c in costs) _sortedPool(cards.where((x) => !x.isLand && x.isCreature && _bucketOf(x) == c).toList())];
    int maxLen(List<List<CardRating>> rows) => rows.fold(0, (m, r) => r.length > m ? r.length : m);
    final maxTop = maxLen(spellRows);
    final maxBottom = maxLen([creatureRows, [lands]].expand((e) => e).toList());
    final totalCreatures = creatureRows.fold(0, (s, r) => s + r.length);
    final totalSpells = spellRows.fold(0, (s, r) => s + r.length);
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
                    child: Align(alignment: Alignment.bottomCenter, child: _cardStack(lands, w, offset, onSecondary)),
                  ),
                  _columnLabel('Lands', lands.length, showTargets ? (16, 18) : null),
                ],
              ),
            ),
            for (final c in costs)
              Expanded(
                // Dropping a card here counts it as this cost from now on
                child: DragTarget<CardRating>(
                  onAcceptWithDetails: (d) => setState(() => _costOverride[d.data.name] = c),
                  builder: (context, candidate, rejected) => Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    if (topH > 0)
                      SizedBox(
                        height: topH,
                        child: Align(alignment: Alignment.bottomCenter, child: _cardStack(spellRows[c], w, offset, onSecondary, draggable: showTargets)),
                      ),
                    if (showTargets && topH > 0) _rowCount(spellRows[c].length, _spellRange(c)),
                    if (topH > 0 && bottomH > 0) const SizedBox(height: 4),
                    if (bottomH > 0)
                      SizedBox(
                        height: bottomH,
                        child: Align(alignment: Alignment.bottomCenter, child: _cardStack(creatureRows[c], w, offset, onSecondary, draggable: showTargets)),
                      ),
                    if (showTargets && bottomH > 0) _rowCount(creatureRows[c].length, _creatureRange(c)),
                    Text(c == 6 ? '6+' : '$c'),
                    ],
                  ),
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
                        Text('Picked ${cards.length}', style: const TextStyle(fontSize: 12)),
                        _totalLabel('Creatures', totalCreatures, (14, 17)),
                        _totalLabel('Noncreatures', totalSpells, (6, 9)),
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

  // Noncreatures are fewer and sit lower, removal and tricks mostly
  (int, int)? _spellRange(int cost) {
    return switch (cost) {
      0 => null,
      1 => (0, 2),
      2 => (1, 3),
      3 => (1, 3),
      4 => (0, 2),
      5 => (0, 1),
      _ => (0, 1),
    };
  }

  // Small count under a stack, green while inside the recommended range
  Widget _rowCount(int count, (int, int)? range) {
    if (range == null) return const SizedBox(height: 14);
    final ok = count >= range.$1 && count <= range.$2;
    return SizedBox(
      height: 14,
      child: Text('$count/${_rangeLabel(range)}',
          style: TextStyle(fontSize: 10, color: ok ? const Color(0xFF4CAF6D) : null)),
    );
  }

  // Count against the recommended range, with the middle of the range in
  // brackets, green while inside it
  Widget _columnLabel(String label, int count, (int, int)? range) {
    if (range == null) return Text(label);
    final ok = count >= range.$1 && count <= range.$2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Text('$count/${_rangeLabel(range)}',
            style: TextStyle(fontSize: 11, color: ok ? const Color(0xFF4CAF6D) : null)),
      ],
    );
  }

  // 5(4-6) or 2.5(2-3), middle first, one decimal only when it isn't whole
  String _rangeLabel((int, int) range) {
    final mid = (range.$1 + range.$2) / 2;
    final label = mid == mid.roundToDouble() ? mid.round().toString() : mid.toStringAsFixed(1);
    return '$label(${range.$1}-${range.$2})';
  }

  // Deck total against the recommended range, green while inside it
  Widget _totalLabel(String label, int count, (int, int) range) {
    final ok = count >= range.$1 && count <= range.$2;
    return Text(
      '$label $count/${_rangeLabel(range)}',
      style: TextStyle(fontSize: 12, color: ok ? const Color(0xFF4CAF6D) : null),
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

  // Cards stacked with their title bars visible, right click moves the card
  Widget _cardStack(List<CardRating> cards, double w, double offset, void Function(CardRating) onSecondary,
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


  // Drafting is over, so the deck and sideboard get the whole screen
  Widget _buildFinished(DraftState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildPool(state.playerPool, state.sideboard, lands: state.lands)),
        _buildVSplitter(),
        SizedBox(
          width: _rankWidth,
          child: LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                SizedBox(
                  height: splitSize(box.maxHeight, _rankSplit),
                  child: _buildRankTable(context, 'Your picks', state.playerPool, pickable: false),
                ),
                _buildRankSplitter(box.maxHeight),
                Expanded(child: _buildRankTable(context, 'Sideboard', state.sideboard, pickable: false)),
              ],
            ),
          ),
        ),
      ],
    );
  }


  List<CardRating> _ranked(List<CardRating> cards) {
    final state = context.read<DraftCubit>().state;
    // With a pair selected its win rates drive the order, that's the point of it
    final pairOn = state.pair.isNotEmpty && state.pairRatings.isNotEmpty;
    double gih(CardRating c) => pairOn ? (state.pairRatings[c.name] ?? -1) : (c.gihwr ?? -1);
    final sorted = List<CardRating>.from(cards);
    // Missing stats (low sample size) always sort to the bottom
    sorted.sort((a, b) => switch (_rankStat) {
      RankStat.gihwr => gih(b).compareTo(gih(a)),
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