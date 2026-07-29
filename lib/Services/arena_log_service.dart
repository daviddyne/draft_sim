import 'dart:async';
import 'package:draft_sim/Services/log_reader_stub.dart'
    if (dart.library.io) 'package:draft_sim/Services/log_reader_io.dart';

// One event parsed out of the Arena log
sealed class ArenaDraftEvent {}

class PackEvent extends ArenaDraftEvent {
  final List<int> grpIds;

  PackEvent(this.grpIds);
}

class PickEvent extends ArenaDraftEvent {
  final int grpId;

  PickEvent(this.grpId);
}

// Which draft the log lines belong to, e.g. PremierDraft_MSH
class DraftInfoEvent extends ArenaDraftEvent {
  final String eventType;
  final String setCode;

  DraftInfoEvent(this.eventType, this.setCode);
}

// The full pool so far, quick draft repeats this in every status message
class PoolEvent extends ArenaDraftEvent {
  final List<int> grpIds;

  PoolEvent(this.grpIds);
}

// A deck submission after the draft, the authoritative main/sideboard split
class DeckEvent extends ArenaDraftEvent {
  final List<int> mainIds;
  final List<int> sideIds;

  DeckEvent(this.mainIds, this.sideIds);
}

// Arrays found on a line that mentions a deck, the cubit decides which are real
class DeckCandidateEvent extends ArenaDraftEvent {
  final List<List<int>> arrays;

  DeckCandidateEvent(this.arrays);
}

class ArenaLogService {
  Timer? _timer;
  int _offset = 0;
  final _controller = StreamController<ArenaDraftEvent>.broadcast();
  // Recent log lines mentioning a deck, kept for the diagnostics view
  final List<String> deckLines = [];

  Stream<ArenaDraftEvent> get events => _controller.stream;

  // Finds Arena's log, desktop only
  static String? findLog() => LogReader.findLog();

  // Parses the whole current session first (Arena wipes the log per restart),
  // then keeps tailing new lines. Huge logs are capped to the newest chunk.
  void start(String path) {
    stop();
    _offset = 0;
    if (LogReader.exists(path)) {
      const cap = 32 * 1024 * 1024;
      final len = LogReader.length(path);
      if (len > cap) _offset = len - cap;
      _poll(path);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll(path));
  }

  void _poll(String path) {
    if (!LogReader.exists(path)) return;
    final len = LogReader.length(path);
    // Arena restarted and truncated the log
    if (len < _offset) _offset = 0;
    if (len == _offset) return;
    final chunk = LogReader.read(path, _offset, len);
    _offset = len;
    _parse(chunk);
  }

  // Arena log formats shift between versions, these patterns cover the common ones
  // Premier packs: "PackCards":"id,id,..."  Quick draft packs: "DraftPack":["id","id",...]
  // Picks: "GrpIds":[id], older "GrpId":id, quick draft "PickGrpId":id
  // Arena nests draft payloads as escaped JSON strings, so quotes may appear as \"
  static final _packRe = RegExp(r'\\?"PackCards\\?"\s*:\s*\\?"([0-9,\s]+)\\?"');
  static final _draftPackRe = RegExp(r'\\?"DraftPack\\?"\s*:\s*\[([^\]]*)\]');
  static final _pickedCardsRe = RegExp(r'\\?"PickedCards\\?"\s*:\s*\[([^\]]*)\]');
  static final _pickCtxRe = RegExp(r'DraftMakePick|BotDraft_DraftPick|PickGrpId');
  static final _pickListRe = RegExp(r'\\?"(?:Pick)?GrpIds\\?"\s*:\s*\[([0-9,\s]+)\]');
  static final _pickRe = RegExp(r'\\?"(?:PickGrpId|GrpId|CardId)\\?"\s*:\s*(\d+)');
  // Event names like PremierDraft_DFT_20260721 or QuickDraft_OTJ appear in draft payloads
  // Set codes are strictly uppercase, which filters out quest strings like Draft_Quest_
  static final _eventRe = RegExp(r'(PremierDraft|QuickDraft|TradDraft|BotDraft|CompDraft)_([A-Z0-9]{3,6})(?:_|\\?"|\s|$)');
  // Deck submissions carry MainDeck/Sideboard, in-match GRE messages use deckCards/sideboardCards
  // Deck payloads look like "MainDeck":[{"cardId":90553,"quantity":2},...]
  // Nested objects hold no ], so capturing up to the closing bracket is safe
  static final _deckMainRe = RegExp(
      r'\\?"(?:MainDeck|deckCards|CardsInDeck)\\?"\s*:\s*\[([^\]]*)\]',
      caseSensitive: false);
  static final _deckSideRe = RegExp(
      r'\\?"(?:Sideboard|sideboardCards|CardsInSideboard)\\?"\s*:\s*\[([^\]]*)\]',
      caseSensitive: false);
  static final _numRe = RegExp(r'\d+');
  // One deck entry, quantity decides how many copies the card appears as
  static final _entryRe = RegExp(r'cardId\\?"?\s*:\s*(\d+)\s*,\s*\\?"?quantity\\?"?\s*:\s*(\d+)', caseSensitive: false);
  // Any flat array, used when deck key names don't match the known ones
  static final _arrayRe = RegExp(r'\[([^\]]*)\]');

  void _parse(String chunk) {
    for (final m in _eventRe.allMatches(chunk)) {
      _controller.add(DraftInfoEvent(m.group(1)!, m.group(2)!.toUpperCase()));
    }
    for (final m in _packRe.allMatches(chunk)) {
      final ids = [for (final s in m.group(1)!.split(',')) int.tryParse(s.trim()) ?? 0];
      final valid = ids.where((i) => i > 0).toList();
      if (valid.isNotEmpty) _controller.add(PackEvent(valid));
    }
    // Quick draft sends the pack as an array of id strings
    for (final m in _draftPackRe.allMatches(chunk)) {
      final ids = [for (final n in _numRe.allMatches(m.group(1)!)) int.parse(n.group(0)!)];
      final valid = ids.where((i) => i > 0).toList();
      if (valid.isNotEmpty) _controller.add(PackEvent(valid));
    }
    // Quick draft repeats the whole pool, which is safer than counting single picks
    for (final m in _pickedCardsRe.allMatches(chunk)) {
      final ids = [for (final n in _numRe.allMatches(m.group(1)!)) int.parse(n.group(0)!)];
      if (ids.isNotEmpty) _controller.add(PoolEvent(ids.where((i) => i > 0).toList()));
    }
    for (final line in chunk.split('\n')) {
      if (!_pickCtxRe.hasMatch(line)) continue;
      final list = _pickListRe.firstMatch(line);
      if (list != null) {
        for (final s in list.group(1)!.split(',')) {
          final id = int.tryParse(s.trim());
          if (id != null && id > 0) _controller.add(PickEvent(id));
        }
        continue;
      }
      final m = _pickRe.firstMatch(line);
      if (m != null) _controller.add(PickEvent(int.parse(m.group(1)!)));
    }
    // Deck submissions come last so the main/sideboard split isn't overwritten by pool events
    for (final line in chunk.split('\n')) {
      final main = _deckMainRe.firstMatch(line);
      final side = _deckSideRe.firstMatch(line);
      // A sideboard alone still tells us the split, an empty one means everything is maindeck
      if (main == null && side == null) continue;
      _controller.add(DeckEvent(_expand(main), _expand(side)));
    }    // Key names for decks change between Arena versions, so also scan any deck line
    // for id arrays and let the cubit decide which ones are actually cards
    for (final line in chunk.split('\n')) {
      if (!line.toLowerCase().contains('deck')) continue;
      final arrays = [
        for (final m in _arrayRe.allMatches(line)) _expand(m),
      ].where((a) => a.length >= 10).toList();
      // Show the deck payload itself in diagnostics rather than the start of the line
      final keyAt = line.toLowerCase().indexOf(RegExp(r'maindeck|cardsindeck|deckcards'));
      final from = keyAt > 0 ? keyAt : 0;
      final excerpt = line.substring(from, from + 600 > line.length ? line.length : from + 600);
      deckLines.add(excerpt);
      if (deckLines.length > 25) deckLines.removeAt(0);
      if (arrays.isNotEmpty) _controller.add(DeckCandidateEvent(arrays));
    }
  }

  // Turns cardId/quantity entries into one id per copy, falls back to plain ids
  List<int> _expand(Match? m) {
    if (m == null) return const [];
    final body = m.group(1)!;
    final entries = _entryRe.allMatches(body).toList();
    if (entries.isEmpty) {
      return [for (final n in _numRe.allMatches(body)) int.parse(n.group(0)!)];
    }
    final ids = <int>[];
    for (final e in entries) {
      final id = int.parse(e.group(1)!);
      final qty = int.parse(e.group(2)!);
      for (var i = 0; i < qty; i++) {
        ids.add(id);
      }
    }
    return ids;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}