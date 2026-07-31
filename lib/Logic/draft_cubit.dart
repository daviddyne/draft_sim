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
  // Basic lands for this set, so they can be added to the deck
  final List<CardRating> lands;
  // Color pair whose ratings are shown alongside the overall ones, empty is off
  final String pair;
  // Card name to win rate within that pair
  final Map<String, double> pairRatings;
  // Every pair's ratings, used to spot a card that is better somewhere else
  final Map<String, Map<String, double>> allPairRatings;
  // Average of the pair's top 20 commons and uncommons, how deep the pair runs
  final double? pairAverage;
  // The same figure for every pair, for comparing them in the picker
  final Map<String, double> pairAverages;
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
    this.lands = const [],
    this.pair = '',
    this.pairRatings = const {},
    this.allPairRatings = const {},
    this.pairAverage,
    this.pairAverages = const {},
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
    List<CardRating>? lands,
    String? pair,
    Map<String, double>? pairRatings,
    Map<String, Map<String, double>>? allPairRatings,
    double? pairAverage,
    Map<String, double>? pairAverages,
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
      lands: lands ?? this.lands,
      pair: pair ?? this.pair,
      pairRatings: pairRatings ?? this.pairRatings,
      allPairRatings: allPairRatings ?? this.allPairRatings,
      pairAverage: pairAverage ?? this.pairAverage,
      pairAverages: pairAverages ?? this.pairAverages,
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
    } catch (e) {
      // Show why the dropdown is empty, typing a code still works
      emit(state.copyWith(error: 'Could not load the set list: $e'));
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
      _setCode = setCode;
      _eventType = eventType;
      final cards = await _service.fetchRatings(setCode, eventType: eventType);
      _generator = PackGenerator(cards);
      // Optional, a draft still works without art for basics
      var lands = <CardRating>[];
      try {
        lands = await _service.fetchBasicLands(setCode, eventType: eventType);
      } catch (_) {}
      emit(DraftState(
        sets: state.sets,
        lands: lands,
        packs: List.generate(seats, (_) => _generator!.generatePack()),
        packNumber: 1,
        pickNumber: 1,
      ));
      // Pair ratings are on by default, the guess improves with every pick
      setPair(bestPair());
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
    _autoPair();
  }

  // Whichever pair has the deepest playables, before any picks say otherwise
  String _strongestPair() {
    if (state.pairAverages.isEmpty) return pairs[_random.nextInt(pairs.length)];
    final ranked = [...state.pairAverages.entries]..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.key;
  }

  // Keeps the pair in step with what is being picked, early on only
  void _autoPair() {
    if (state.pair.isEmpty) return;
    final guess = bestPair();
    if (guess != state.pair) setPair(guess);
  }

  static const pairs = ['WU', 'WB', 'WR', 'WG', 'UB', 'UR', 'UG', 'BR', 'BG', 'RG'];
  String _setCode = '';
  String _eventType = 'PremierDraft';

  // Turns the pair filter on with the best guess, or off again
  Future<void> togglePair() async {
    if (state.pair.isNotEmpty) {
      emit(state.copyWith(pair: '', pairRatings: const {}));
      return;
    }
    await setPair(bestPair());
  }

  // Chosen from the dropdown, detection carries on from the next pick
  Future<void> setPairManually(String pair) async => setPair(pair);

  Future<void> setPair(String pair) async {
    emit(state.copyWith(pair: pair, pairRatings: state.allPairRatings[pair] ?? const {}));
    final ratings = state.allPairRatings[pair] ?? await _service.fetchPairRatings(_setCode, _eventType, pair);
    if (state.pair == pair) {
      final avg = _pairAverage(ratings);
      final averages = Map<String, double>.from(state.pairAverages);
      if (avg != null) averages[pair] = avg;
      emit(state.copyWith(pairRatings: ratings, pairAverage: avg, pairAverages: averages));
    }
    _loadAllPairs();
  }

  // Fetched once in the background, so the other pairs can be compared against
  // How strong the pair's playables are, averaged over its best 20 commons
  // and uncommons. Rares are left out, they can't be counted on.
  double? _pairAverage(Map<String, double> ratings) {
    final pool = [...?_generator?.commons, ...?_generator?.uncommons];
    final rated = [for (final c in pool) ?ratings[c.name]]..sort((a, b) => b.compareTo(a));
    if (rated.isEmpty) return null;
    final top = rated.take(20).toList();
    return top.reduce((a, b) => a + b) / top.length;
  }

  Future<void> _loadAllPairs() async {
    final missing = pairs.where((p) => (state.allPairRatings[p] ?? const {}).isEmpty).toList();
    if (missing.isEmpty) return;
    // A few at a time, ten sequential requests made switching pairs sluggish
    const batch = 5;
    for (var i = 0; i < missing.length; i += batch) {
      final slice = missing.skip(i).take(batch).toList();
      // One pair failing shouldn't abandon the rest of the batch
      final results = await Future.wait([
        for (final p in slice) _service.fetchPairRatings(_setCode, _eventType, p),
      ]);
      if (isClosed) return;
      final all = Map<String, Map<String, double>>.from(state.allPairRatings);
      final averages = Map<String, double>.from(state.pairAverages);
      for (var j = 0; j < slice.length; j++) {
        all[slice[j]] = results[j];
        if (_pairAverage(results[j]) case final avg?) averages[slice[j]] = avg;
      }
      emit(state.copyWith(allPairRatings: all, pairAverages: averages));
    }
    _autoPair();
  }


  // The pair holding most of the picked cards, weighted by how good they are.
  // With only a few picks many pairs tie, so the result is near arbitrary early on.
  String bestPair() {
    final pool = state.playerPool.where((c) => !c.isLand && c.color.isNotEmpty).toList();
    if (pool.isEmpty) return _strongestPair();
    var best = <String>[];
    var bestCount = -1;
    var bestScore = -1.0;
    for (final pair in pairs) {
      final cards = pool.where((c) => c.color.split('').every(pair.contains)).toList();
      // A card above average adds more than a filler card
      final score = cards.fold(0.0, (s, c) => s + ((c.gihwr ?? 0.5) - 0.45));
      if (cards.length > bestCount || (cards.length == bestCount && score > bestScore)) {
        best = [pair];
        bestCount = cards.length;
        bestScore = score;
      } else if (cards.length == bestCount && score == bestScore) {
        best.add(pair);
      }
    }
    return best[_random.nextInt(best.length)];
  }

  // Basics aren't drafted, they're added while building the deck
  void addLand(CardRating land) {
    emit(state.copyWith(playerPool: [...state.playerPool, land]));
  }

  void removeCard(CardRating card) {
    final pool = List<CardRating>.from(state.playerPool)..remove(card);
    emit(state.copyWith(playerPool: pool));
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