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
  DeckEvent? _pendingDeck;
  bool _loadingSet = false;
  // Sets that failed to load, so a bad match can't be retried forever
  final Set<String> _failedSets = {};
  // Detection that arrived while another set was loading
  DraftInfoEvent? _queuedInfo;

  ArenaDraftCubit(this._service, this._log) : super(const ArenaDraftState());

  Future<void> start({String? logPath}) async {
    final path = logPath ?? ArenaLogService.findLog();
    if (path == null) {
      emit(const ArenaDraftState(error: 'Player.log not found, enter the path manually'));
      return;
    }
    // Subscribe before parsing starts, a broadcast stream drops events without listeners
    await _sub?.cancel();
    _sub = _log.events.listen(_onEvent);
    emit(ArenaDraftState(logPath: path, connected: true));
    _log.start(path);
  }

  void _onEvent(ArenaDraftEvent e) {
    if (e is DraftInfoEvent) {
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
    } else if (e is DeckEvent) {
      if (_byArenaId.isEmpty) {
        _pendingDeck = e;
        return;
      }
      _applyDeck(e);
    }
  }

  // The submitted deck is the authoritative main/sideboard split
  void _applyDeck(DeckEvent e) {
    final main = [for (final id in e.mainIds) ?_byArenaId[id]];
    final side = [for (final id in e.sideIds) ?_byArenaId[id]];
    if (main.isEmpty && side.isEmpty) return;
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
    try {
      List<CardRating> cards;
      try {
        cards = await _service.fetchRatings(e.setCode, eventType: eventType);
      } catch (_) {
        // Not every set has data for every event type, PremierDraft is the safest fallback
        cards = await _service.fetchRatings(e.setCode);
      }
      _byArenaId = {for (final c in cards) if (c.arenaId != null) c.arenaId!: c};
      emit(state.copyWith(setCode: e.setCode, eventType: eventType, pack: [], pool: [], sideboard: [], unknownIds: 0));
      if (_pendingPack.isNotEmpty) _emitPack(_pendingPack);
      for (final id in _pendingPicks) {
        _emitPick(id);
      }
      if (_pendingDeck != null) _applyDeck(_pendingDeck!);
      _pendingPack = [];
      _pendingPicks.clear();
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
    final unknown = [for (final id in grpIds) if (!_byArenaId.containsKey(id)) id];
    emit(state.copyWith(pack: cards, unknownIds: unknown.length, unknownInfo: unknown.join(', ')));
  }

  void _emitPick(int grpId) {
    final card = _byArenaId[grpId];
    if (card == null) return;
    final pack = List<CardRating>.from(state.pack)..remove(card);
    emit(state.copyWith(pool: [...state.pool, card], pack: pack));
  }

  // Move a picked card to the planning sideboard, Arena itself doesn't track this during a draft
  void toSideboard(CardRating card) {
    final pool = List<CardRating>.from(state.pool)..remove(card);
    final side = List<CardRating>.from(state.sideboard)..add(card);
    emit(state.copyWith(pool: pool, sideboard: side));
  }

  // Move a sideboard card back into the pool
  void toPool(CardRating card) {
    final side = List<CardRating>.from(state.sideboard)..remove(card);
    final pool = List<CardRating>.from(state.pool)..add(card);
    emit(state.copyWith(pool: pool, sideboard: side));
  }

  // Clear the tracked draft without disconnecting, e.g. when starting a new one
  void clearDraft() => emit(state.copyWith(pack: [], pool: [], sideboard: [], unknownIds: 0));

  @override
  Future<void> close() {
    _sub?.cancel();
    _log.dispose();
    return super.close();
  }
}