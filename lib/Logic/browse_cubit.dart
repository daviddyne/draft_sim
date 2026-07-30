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

  const BrowseState({
    this.loading = false,
    this.error,
    this.cards = const [],
    this.setCodes = const [],
    this.available = const [],
  });

  BrowseState copyWith({
    bool? loading,
    String? error,
    List<CardRating>? cards,
    List<String>? setCodes,
    List<SetOption>? available,
  }) {
    return BrowseState(
      loading: loading ?? this.loading,
      error: error,
      cards: cards ?? this.cards,
      setCodes: setCodes ?? this.setCodes,
      available: available ?? this.available,
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
    emit(state.copyWith(loading: true, setCodes: [setCode]));
    await _fetch(setCode);
    _publish();
    _loadAvailable();
  }

  Future<void> _loadAvailable() async {
    try {
      emit(state.copyWith(available: await _service.fetchSets()));
    } catch (_) {
      // The picker just stays limited to what is already loaded
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
  }
}