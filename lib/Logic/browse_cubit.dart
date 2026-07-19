import 'package:draft_sim/Models/card_rating.dart';
import 'package:draft_sim/Services/seventeen_lands_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BrowseState {
  final bool loading;
  final String? error;
  final List<CardRating> cards;

  const BrowseState({this.loading = false, this.error, this.cards = const []});
}

class BrowseCubit extends Cubit<BrowseState> {
  final SeventeenLandsService _service;

  BrowseCubit(this._service) : super(const BrowseState());

  Future<void> load(String setCode, String eventType) async {
    emit(const BrowseState(loading: true));
    try {
      final cards = await _service.fetchRatings(setCode, eventType: eventType);
      emit(BrowseState(cards: cards));
    } catch (e) {
      emit(BrowseState(error: e.toString()));
    }
  }
}
