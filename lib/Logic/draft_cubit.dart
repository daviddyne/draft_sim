import 'dart:math';

import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:draft_sim/pack_generator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DraftState {
  final bool loading;
  final String? error;
  final List<List<CardRating>> packs;
  final List<CardRating> playerPool;
  final int packNumber;
  final int pickNumber;
  final bool finished;

  const DraftState({
    this.loading = false,
    this.error,
    this.packs = const [],
    this.playerPool = const [],
    this.packNumber = 0,
    this.pickNumber = 0,
    this.finished = false,
  });

  // The player always sits at seat 0
  List<CardRating> get currentPack => packs.isEmpty ? const [] : packs[0];

  DraftState copyWith({
    bool? loading,
    String? error,
    List<List<CardRating>>? packs,
    List<CardRating>? playerPool,
    int? packNumber,
    int? pickNumber,
    bool? finished,
  }) {
    return DraftState(
      loading: loading ?? this.loading,
      error: error,
      packs: packs ?? this.packs,
      playerPool: playerPool ?? this.playerPool,
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

  DraftCubit(this._service) : super(const DraftState());

  // Abandon the current draft and go back to set selection
  void reset() => emit(const DraftState());

  Future<void> startDraft(
    String setCode, {
    String eventType = 'PremierDraft',
  }) async {
    emit(const DraftState(loading: true));
    try {
      final cards = await _service.fetchRatings(setCode, eventType: eventType);
      _generator = PackGenerator(cards);
      emit(
        DraftState(
          packs: List.generate(seats, (_) => _generator!.generatePack()),
          packNumber: 1,
          pickNumber: 1,
        ),
      );
    } catch (e) {
      emit(DraftState(error: e.toString()));
    }
  }

  void pickCard(CardRating card) {
    if (state.finished || state.packs.isEmpty) return;
    final packs = state.packs.map((p) => List<CardRating>.from(p)).toList();
    packs[0].remove(card);
    final pool = List<CardRating>.from(state.playerPool)..add(card);
    for (var i = 1; i < seats; i++) {
      if (packs[i].isNotEmpty) packs[i].remove(_botPick(packs[i]));
    }
    if (packs[0].isEmpty) {
      if (state.packNumber == packsPerDraft) {
        emit(state.copyWith(playerPool: pool, finished: true, packs: []));
        return;
      }
      emit(
        state.copyWith(
          packs: List.generate(seats, (_) => _generator!.generatePack()),
          playerPool: pool,
          packNumber: state.packNumber + 1,
          pickNumber: 1,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        packs: _rotate(packs, state.packNumber.isOdd),
        playerPool: pool,
        pickNumber: state.pickNumber + 1,
      ),
    );
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
