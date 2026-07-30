import 'dart:async';

import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/arena_log_service.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ArenaDraftState {
  final String? error;
  final String? logPath;
  final bool connected;
  // Detected from the log, empty until the first draft event shows up
  final String setCode;
  final String eventType;
  final List<CardRating> pack;
  final List<CardRating> pool;
  final List<CardRating> sideboard;
  // Pack cards from the log that couldn't be matched to 17lands data
  final int unknownIds;
  final String unknownInfo;

  const ArenaDraftState({
    this.error,
    this.logPath,
    this.connected = false,
    this.setCode = '',
    this.eventType = '',
    this.pack = const [],
    this.pool = const [],
    this.sideboard = const [],
    this.unknownIds = 0,
    this.unknownInfo = '',
  });

  ArenaDraftState copyWith({
    String? error,
    String? logPath,
    bool? connected,
    String? setCode,
    String? eventType,
    List<CardRating>? pack,
    List<CardRating>? pool,
    List<CardRating>? sideboard,
    int? unknownIds,
    String? unknownInfo,
  }) {
    return ArenaDraftState(
      error: error,
      logPath: logPath ?? this.logPath,
      connected: connected ?? this.connected,
      setCode: setCode ?? this.setCode,
      eventType: eventType ?? this.eventType,
      pack: pack ?? this.pack,
      pool: pool ?? this.pool,
      sideboard: sideboard ?? this.sideboard,
      unknownIds: unknownIds ?? this.unknownIds,
      unknownInfo: unknownInfo ?? this.unknownInfo,
    );
  }
}

class ArenaDraftCubit extends Cubit<ArenaDraftState> {
  final SeventeenLandsService _service;
  final ArenaLogService _log;
  Map<int, CardRating> _byArenaId = {};
  StreamSubscription? _sub;
  // Events that arrived before the set data finished loading
  List<int> _pendingPack = [];
  final List<int> _pendingPicks = [];
  List<int> _pendingPool = [];
  // Set once Arena reports a built deck, its split then wins over pool updates
  bool _deckApplied = false;
  // Every card picked this draft, used to derive the sideboard from the maindeck
  final List<CardRating> _fullPool = [];
  // Pool as of the last report, so new picks can be told apart from old ones
  List<int> _lastPoolIds = [];
  // Which draft the events belong to, a change means a new draft started
  String _draftId = '';
  DeckEvent? _pendingDeck;
  bool _loadingSet = false;
  // Sets that failed to load, so a bad match can't be retried forever
  final Set<String> _failedSets = {};
  // Detection that arrived while another set was loading
  DraftInfoEvent? _queuedInfo;

  ArenaDraftCubit(this._service, this._log) : super(const ArenaDraftState());

  // Raw material for the diagnostics view
  List<String> get deckLines => _log.deckLines;
  List<String> get parsedEvents => _log.parsedEvents;
  String get draftId => _draftId;
  int get poolCount => _fullPool.length;
  bool get deckApplied => _deckApplied;

  Future<void> start({String? logPath}) async {
    final path = logPath ?? ArenaLogService.findLog();
    if (path == null) {
      emit(
        const ArenaDraftState(
          error: 'Player.log not found, enter the path manually',
        ),
      );
      return;
    }
    // Subscribe before parsing starts, a broadcast stream drops events without listeners
    await _sub?.cancel();
    _sub = _log.events.listen(_onEvent);
    emit(ArenaDraftState(logPath: path, connected: true));
    _log.start(path);
  }

  void _onEvent(ArenaDraftEvent e) {
    if (e is DraftIdEvent) {
      if (e.id == _draftId) return;
      _draftId = e.id;
      _startFresh();
    } else if (e is DraftInfoEvent) {
      _onDraftInfo(e);
    } else if (e is PackEvent) {
      if (_byArenaId.isEmpty) {
        _pendingPack = e.grpIds;
        return;
      }
      _emitPack(e.grpIds);
    } else if (e is PickEvent) {
      if (_byArenaId.isEmpty) {
        _pendingPicks.add(e.grpId);
        return;
      }
      _emitPick(e.grpId);
    } else if (e is PoolEvent) {
      if (_byArenaId.isEmpty) {
        _pendingPool = e.grpIds;
        return;
      }
      _applyPool(e.grpIds);
    } else if (e is DeckCandidateEvent) {
      // Only meaningful once a draft is being tracked
      if (_byArenaId.isEmpty || _fullPool.isEmpty) return;
      _applyCandidates(e.arrays);
    } else if (e is DeckEvent) {
      if (_byArenaId.isEmpty) {
        _pendingDeck = e;
        return;
      }
      _applyDeck(e);
    }
  }

  // The reported pool replaces ours, so picks can't drift or double count
  // Once a deck has been built in Arena its split wins, so the pool no longer overrides it
  void _applyPool(List<int> grpIds) {
    final cards = [for (final id in grpIds) ?_byArenaId[id]];
    if (cards.isEmpty) return;
    // A pool never shrinks inside one draft, so this is a new one
    if (cards.length < _fullPool.length) _startFresh();
    _fullPool
      ..clear()
      ..addAll(cards);
    if (_deckApplied) {
      _lastPoolIds = [for (final c in cards) c.arenaId ?? 0];
      return;
    }
    // Take out only what was added since the last report, so duplicates in the
    // pack survive and the final pick still clears the pack
    final added = List<int>.from([for (final c in cards) c.arenaId ?? 0]);
    for (final id in _lastPoolIds) {
      added.remove(id);
    }
    _lastPoolIds = [for (final c in cards) c.arenaId ?? 0];
    final pack = List<CardRating>.from(state.pack);
    for (final id in added) {
      final i = pack.indexWhere((c) => c.arenaId == id);
      if (i >= 0) pack.removeAt(i);
    }
    emit(state.copyWith(pool: cards, pack: pack));
  }

  // A deck line can hold several arrays, so pick the one that behaves like a deck:
  // 40ish cards, mostly cards we drafted, and not just the whole pool repeated
  void _applyCandidates(List<List<int>> arrays) {
    if (_fullPool.isEmpty) return;
    final poolIds = _fullPool.map((c) => c.arenaId).toList();
    List<int>? best;
    var bestOverlap = 0;
    for (final a in arrays) {
      final known = a.where(_byArenaId.containsKey).toList();
      if (known.length < 30 || known.length > 60) continue;
      final overlap = known.where(poolIds.contains).length;
      // The pool itself shows up as an array too, a deck always leaves cards behind
      if (overlap >= _fullPool.length) continue;
      if (overlap < 15) continue;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = known;
      }
    }
    if (best == null) return;
    _applyDeck(DeckEvent(best, const []));
  }

  // The submitted deck is the authoritative main deck
  // If Arena logs a sideboard we use it, otherwise it is whatever the deck left over
  void _applyDeck(DeckEvent e) {
    // Arena also logs decks for ordinary games, which say nothing about a draft
    if (_fullPool.isEmpty) return;
    final main = [for (final id in e.mainIds) ?_byArenaId[id]];
    if (main.length < 20) return;
    // The deck has to be built from cards this draft actually picked
    final poolIds = _fullPool.map((c) => c.arenaId).toSet();
    final fromPool = main.where((c) => poolIds.contains(c.arenaId)).length;
    if (fromPool < main.length ~/ 2) return;
    var side = [for (final id in e.sideIds) ?_byArenaId[id]];
    if (side.isEmpty) {
      final rest = List<CardRating>.from(_fullPool);
      // Remove one pool copy per maindeck card, basics added in Arena aren't in the pool
      for (final c in main) {
        final i = rest.indexWhere((x) => x.arenaId == c.arenaId);
        if (i >= 0) rest.removeAt(i);
      }
      side = rest;
    }
    _deckApplied = true;
    emit(state.copyWith(pool: main, sideboard: side));
  }

  Future<void> _onDraftInfo(DraftInfoEvent e) async {
    // Arena's internal names map onto 17lands event types
    final eventType = switch (e.eventType) {
      'BotDraft' => 'QuickDraft',
      'CompDraft' => 'TradDraft',
      final t => t,
    };
    final key = '${e.setCode}/$eventType';
    if (_failedSets.contains(key)) return;
    if (state.setCode == e.setCode && state.eventType == eventType) return;
    if (_loadingSet) {
      _queuedInfo = e;
      return;
    }
    _loadingSet = true;
    _deckApplied = false;
    _fullPool.clear();
    _lastPoolIds = [];
    try {
      List<CardRating> cards;
      try {
        cards = await _service.fetchRatings(e.setCode, eventType: eventType);
      } catch (_) {
        // Not every set has data for every event type, PremierDraft is the safest fallback
        cards = await _service.fetchRatings(e.setCode);
      }
      _byArenaId = {
        for (final c in cards)
          if (c.arenaId != null) c.arenaId!: c,
      };
      // Basic lands fill the pack land slot, they have no ratings of their own
      try {
        for (final land in await _service.fetchBasicLands(
          e.setCode,
          eventType: eventType,
        )) {
          _byArenaId[land.arenaId!] = land;
        }
      } catch (_) {
        // Lands are cosmetic here, a failure just means the land slot stays unmatched
      }
      emit(
        state.copyWith(
          setCode: e.setCode,
          eventType: eventType,
          pack: [],
          pool: [],
          sideboard: [],
          unknownIds: 0,
        ),
      );
      if (_pendingPack.isNotEmpty) _emitPack(_pendingPack);
      for (final id in _pendingPicks) {
        _emitPick(id);
      }
      if (_pendingPool.isNotEmpty) _applyPool(_pendingPool);
      if (_pendingDeck != null) _applyDeck(_pendingDeck!);
      _pendingPack = [];
      _pendingPicks.clear();
      _pendingPool = [];
      _pendingDeck = null;
    } catch (err) {
      _failedSets.add(key);
      emit(state.copyWith(error: 'Could not load data for ${e.setCode}: $err'));
    } finally {
      _loadingSet = false;
      final queued = _queuedInfo;
      _queuedInfo = null;
      if (queued != null) _onDraftInfo(queued);
    }
  }

  void _emitPack(List<int> grpIds) {
    final cards = [for (final id in grpIds) ?_byArenaId[id]];
    final unknown = [
      for (final id in grpIds)
        if (!_byArenaId.containsKey(id)) id,
    ];
    emit(
      state.copyWith(
        pack: cards,
        unknownIds: unknown.length,
        unknownInfo: unknown.join(', '),
      ),
    );
  }

  void _emitPick(int grpId) {
    final card = _byArenaId[grpId];
    if (card == null) return;
    _fullPool.add(card);
    if (_deckApplied) return;
    final pack = List<CardRating>.from(state.pack)..remove(card);
    emit(state.copyWith(pool: [...state.pool, card], pack: pack));
  }

  // Wipes what was tracked so a new draft doesn't inherit the previous one
  void _startFresh() {
    _deckApplied = false;
    _fullPool.clear();
    _lastPoolIds = [];
    emit(
      state.copyWith(
        pack: [],
        pool: [],
        sideboard: [],
        unknownIds: 0,
        unknownInfo: '',
      ),
    );
  }

  // Clear the tracked draft without disconnecting, e.g. when starting a new one
  // Re-reads the log from the start, so the draft in progress is picked up again
  void clearDraft() {
    _draftId = '';
    _startFresh();
    final path = state.logPath;
    if (path != null) _log.start(path);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _log.dispose();
    return super.close();
  }
}
