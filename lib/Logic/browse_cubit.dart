import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BrowseState {
  final bool loading;
  final String? error;
  final List<CardRating> cards;
  // Sets currently mixed into the view, for chaos drafts and cross set browsing
  final List<String> setCodes;
  // Sets that could be added, from the same source the start screen uses
  final List<SetOption> available;
  // Basic lands, so a deck can include them
  final List<CardRating> lands;
  // Color pair whose ratings are shown beside the overall ones, empty is off
  final String pair;
  final Map<String, double> pairRatings;
  final Map<String, Map<String, double>> allPairRatings;
  // Average of the pair's top 20 commons and uncommons, how deep the pair runs
  final double? pairAverage;
  // The same figure for every pair, for comparing them in the picker
  final Map<String, double> pairAverages;

  const BrowseState({
    this.loading = false,
    this.error,
    this.cards = const [],
    this.setCodes = const [],
    this.available = const [],
    this.lands = const [],
    this.pair = '',
    this.pairRatings = const {},
    this.allPairRatings = const {},
    this.pairAverage,
    this.pairAverages = const {},
  });

  BrowseState copyWith({
    bool? loading,
    String? error,
    List<CardRating>? cards,
    List<String>? setCodes,
    List<SetOption>? available,
    List<CardRating>? lands,
    String? pair,
    Map<String, double>? pairRatings,
    Map<String, Map<String, double>>? allPairRatings,
    double? pairAverage,
    Map<String, double>? pairAverages,
  }) {
    return BrowseState(
      loading: loading ?? this.loading,
      error: error,
      cards: cards ?? this.cards,
      setCodes: setCodes ?? this.setCodes,
      available: available ?? this.available,
      lands: lands ?? this.lands,
      pair: pair ?? this.pair,
      pairRatings: pairRatings ?? this.pairRatings,
      allPairRatings: allPairRatings ?? this.allPairRatings,
      pairAverage: pairAverage ?? this.pairAverage,
      pairAverages: pairAverages ?? this.pairAverages,
    );
  }
}

class BrowseCubit extends Cubit<BrowseState> {
  final SeventeenLandsService _service;
  String _eventType = 'PremierDraft';
  // Cards per set, so toggling one off doesn't need a refetch of the others
  final Map<String, List<CardRating>> _bySet = {};

  BrowseCubit(this._service) : super(const BrowseState());

  Future<void> load(String setCode, String eventType) async {
    _eventType = eventType;
    _setCode = setCode;
    emit(state.copyWith(loading: true, setCodes: [setCode]));
    await _fetch(setCode);
    _publish();
    loadAvailable();
    _loadLands(setCode);
  }

  static const pairs = ['WU', 'WB', 'WR', 'WG', 'UB', 'UR', 'UG', 'BR', 'BG', 'RG'];
  String _setCode = '';

  Future<void> togglePair(List<CardRating> deck) async {
    if (state.pair.isNotEmpty) {
      emit(state.copyWith(pair: '', pairRatings: const {}));
      return;
    }
    await setPair(bestPair(deck));
  }

  // Chosen from the dropdown, detection carries on as the deck changes
  Future<void> setPairManually(String pair) async => setPair(pair);

  // Whichever pair has the deepest playables, before any cards say otherwise
  String _strongestPair() {
    if (state.pairAverages.isEmpty) return pairs.first;
    final ranked = [...state.pairAverages.entries]..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.key;
  }

  // The deck as last seen, so the guess can be redone when ratings arrive
  List<CardRating> _lastDeck = const [];

  // Called whenever the deck changes, keeps the pair in step with it
  void autoPair(List<CardRating> deck) {
    _lastDeck = deck;
    if (state.pair.isEmpty) return;
    final guess = bestPair(deck);
    if (guess != state.pair) setPair(guess);
  }

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

  // How strong the pair's playables are, averaged over its best 20 commons
  // and uncommons. Rares are left out, they can't be counted on.
  double? _pairAverage(Map<String, double> ratings) {
    final pool = state.cards.where((c) => c.rarity == 'common' || c.rarity == 'uncommon').toList();
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
    autoPair(_lastDeck);
  }


  // The pair holding most of the deck, weighted by how good those cards are
  String bestPair(List<CardRating> deck) {
    final pool = deck.where((c) => !c.isLand && c.color.isNotEmpty).toList();
    if (pool.isEmpty) return _strongestPair();
    var best = <String>[];
    var bestCount = -1;
    var bestScore = -1.0;
    for (final pair in pairs) {
      final cards = pool.where((c) => c.color.split('').every(pair.contains)).toList();
      final score = cards.fold(0.0, (s, c) => s + ((c.gihwr ?? 0.5) - 0.45));
      if (cards.length > bestCount || (cards.length == bestCount && score > bestScore)) {
        best = [pair];
        bestCount = cards.length;
        bestScore = score;
      } else if (cards.length == bestCount && score == bestScore) {
        best.add(pair);
      }
    }
    return best.first;
  }

  Future<void> _loadLands(String setCode) async {
    try {
      emit(state.copyWith(lands: await _service.fetchBasicLands(setCode, eventType: _eventType)));
    } catch (_) {
      // Without art the deck simply can't show basics
    }
  }

  Future<void> loadAvailable() async {
    try {
      emit(state.copyWith(available: await _service.fetchSets()));
    } catch (e) {
      // Shown in the picker so an empty list isn't a mystery
      emit(state.copyWith(error: 'Could not load the set list: $e'));
    }
  }

  // Adds or removes a set from the mix
  Future<void> toggleSet(String setCode) async {
    final codes = List<String>.from(state.setCodes);
    if (codes.contains(setCode)) {
      if (codes.length == 1) return;
      codes.remove(setCode);
      emit(state.copyWith(setCodes: codes));
      _publish();
      return;
    }
    codes.add(setCode);
    emit(state.copyWith(setCodes: codes, loading: true));
    await _fetch(setCode);
    _publish();
  }

  // Loads everything the picker knows about, for a full cross set view
  Future<void> addAll() async {
    emit(state.copyWith(loading: true));
    final codes = List<String>.from(state.setCodes);
    for (final option in state.available) {
      if (codes.contains(option.code)) continue;
      await _fetch(option.code);
      if (_bySet.containsKey(option.code)) codes.add(option.code);
    }
    emit(state.copyWith(setCodes: codes));
    _publish();
  }

  Future<void> _fetch(String setCode) async {
    if (_bySet.containsKey(setCode)) return;
    try {
      final event = _eventTypeFor(setCode);
      _bySet[setCode] = await _service.fetchRatings(setCode, eventType: event);
    } catch (e) {
      emit(state.copyWith(error: 'Could not load $setCode: $e'));
    }
  }

  // Falls back to Premier Draft, which nearly every set has
  String _eventTypeFor(String setCode) {
    final match = state.available.where((s) => s.code == setCode).toList();
    if (match.isEmpty || match.first.events.isEmpty) return _eventType;
    final events = match.first.events;
    return events.contains(_eventType) ? _eventType : events.first;
  }

  // Pair ratings are on by default, once there are cards to rate
  bool _pairStarted = false;

  // One list from every selected set, keeping the first copy of a repeated card
  void _publish() {
    final seen = <String>{};
    final cards = <CardRating>[];
    for (final code in state.setCodes) {
      for (final card in _bySet[code] ?? const <CardRating>[]) {
        if (seen.add(card.name)) cards.add(card);
      }
    }
    emit(state.copyWith(loading: false, cards: cards));
    if (!_pairStarted && cards.isNotEmpty) {
      _pairStarted = true;
      setPair(bestPair(const []));
    }
  }
}