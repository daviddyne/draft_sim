import 'dart:math';
import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:draft_sim/pack_generator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DraftState {
  final bool loading;
  final String? error;
  final List<SetOption> sets;
  final List<List<CardRating>> packs;
  final List<CardRating> playerPool;
  final List<CardRating> sideboard;
  final int packNumber;
  final int pickNumber;
  final bool finished;

  const DraftState({
    this.loading = false,
    this.error,
    this.sets = const [],
    this.packs = const [],
    this.playerPool = const [],
    this.sideboard = const [],
    this.packNumber = 0,
    this.pickNumber = 0,
    this.finished = false,
  });

  // The player always sits at seat 0
  List<CardRating> get currentPack => packs.isEmpty ? const [] : packs[0];

  DraftState copyWith({
    bool? loading,
    String? error,
    List<SetOption>? sets,
    List<List<CardRating>>? packs,
    List<CardRating>? playerPool,
    List<CardRating>? sideboard,
    int? packNumber,
    int? pickNumber,
    bool? finished,
  }) {
    return DraftState(
      loading: loading ?? this.loading,
      error: error,
      sets: sets ?? this.sets,
      packs: packs ?? this.packs,
      playerPool: playerPool ?? this.playerPool,
      sideboard: sideboard ?? this.sideboard,
      packNumber: packNumber ?? this.packNumber,
      pickNumber: pickNumber ?? this.pickNumber,
      finished: finished ?? this.finished,
    );
  }
}

class DraftCubit extends Cubit<DraftState> {
  static const seats = 8;
  static const packsPerDraft = 3;
  final SeventeenLandsService _service;
  final Random _random = Random();
  PackGenerator? _generator;
  // When the set list was last fetched, so opening the dropdown doesn't refetch it
  DateTime? _setsLoadedAt;

  DraftCubit(this._service) : super(const DraftState()) {
    _loadSets();
  }

  Future<void> _loadSets() async {
    try {
      emit(state.copyWith(sets: await _service.fetchSets()));
      _setsLoadedAt = DateTime.now();
    } catch (_) {
      // Dropdown stays empty, typing a code still works
    }
  }

  // Called when the set dropdown is opened, so new releases show up
  // Skipped while the list is fresh, the set list costs several requests
  Future<void> refreshSets() async {
    final last = _setsLoadedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    await _loadSets();
  }

  // Abandon the current draft and go back to set selection
  void reset() => emit(DraftState(sets: state.sets));

  Future<void> startDraft(String setCode, {String eventType = 'PremierDraft'}) async {
    emit(DraftState(loading: true, sets: state.sets));
    try {
      final cards = await _service.fetchRatings(setCode, eventType: eventType);
      _generator = PackGenerator(cards);
      emit(DraftState(
        sets: state.sets,
        packs: List.generate(seats, (_) => _generator!.generatePack()),
        packNumber: 1,
        pickNumber: 1,
      ));
    } catch (e) {
      emit(DraftState(error: e.toString(), sets: state.sets));
    }
  }

  // toSide sends the pick straight to the sideboard
  void pickCard(CardRating card, {bool toSide = false}) {
    if (state.finished || state.packs.isEmpty) return;
    final packs = state.packs.map((p) => List<CardRating>.from(p)).toList();
    packs[0].remove(card);
    final pool = List<CardRating>.from(state.playerPool);
    final side = List<CardRating>.from(state.sideboard);
    (toSide ? side : pool).add(card);
    for (var i = 1; i < seats; i++) {
      if (packs[i].isNotEmpty) packs[i].remove(_botPick(packs[i]));
    }
    if (packs[0].isEmpty) {
      if (state.packNumber == packsPerDraft) {
        emit(state.copyWith(playerPool: pool, sideboard: side, finished: true, packs: []));
        return;
      }
      emit(state.copyWith(
        packs: List.generate(seats, (_) => _generator!.generatePack()),
        playerPool: pool,
        sideboard: side,
        packNumber: state.packNumber + 1,
        pickNumber: 1,
      ));
      return;
    }
    emit(state.copyWith(
      packs: _rotate(packs, state.packNumber.isOdd),
      playerPool: pool,
      sideboard: side,
      pickNumber: state.pickNumber + 1,
    ));
  }

  // Move a picked card to the sideboard
  void toSideboard(CardRating card) {
    final pool = List<CardRating>.from(state.playerPool)..remove(card);
    final side = List<CardRating>.from(state.sideboard)..add(card);
    emit(state.copyWith(playerPool: pool, sideboard: side));
  }

  // Move a sideboard card back into the pool
  void toPool(CardRating card) {
    final side = List<CardRating>.from(state.sideboard)..remove(card);
    final pool = List<CardRating>.from(state.playerPool)..add(card);
    emit(state.copyWith(playerPool: pool, sideboard: side));
  }

  // Bots take the card real drafters take earliest (lowest ALSA)
  // A bit of noise so all eight tables don't draft identically
  CardRating _botPick(List<CardRating> pack) {
    CardRating best = pack.first;
    double bestScore = double.infinity;
    for (final card in pack) {
      final score = (card.alsa ?? 8.0) + _random.nextDouble() * 1.5;
      if (score < bestScore) {
        bestScore = score;
        best = card;
      }
    }
    return best;
  }

  // Pack 1 and 3 pass left, pack 2 passes right
  List<List<CardRating>> _rotate(List<List<CardRating>> packs, bool passLeft) {
    final n = packs.length;
    if (passLeft) return [for (var i = 0; i < n; i++) packs[(i + 1) % n]];
    return [for (var i = 0; i < n; i++) packs[(i - 1 + n) % n]];
  }
}