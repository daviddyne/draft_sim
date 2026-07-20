import 'dart:async';
import 'dart:io';

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

// A deck submission after the draft, the authoritative main/sideboard split
class DeckEvent extends ArenaDraftEvent {
  final List<int> mainIds;
  final List<int> sideIds;

  DeckEvent(this.mainIds, this.sideIds);
}

class ArenaLogService {
  Timer? _timer;
  int _offset = 0;
  final _controller = StreamController<ArenaDraftEvent>.broadcast();

  Stream<ArenaDraftEvent> get events => _controller.stream;

  // Looks for Player.log in the usual Heroic and Wine prefix locations
  // Heroic (also as Flatpak) nests prefixes two levels deep: Prefixes/<config>/<game>
  static String? findLog() {
    final home = Platform.environment['HOME'] ?? '';
    const tails = [
      'AppData/LocalLow/Wizards Of The Coast/MTGA/Player.log',
      'AppData/LocalLow/Wizards Of The Coast/MTGA/player.log',
    ];
    final roots = <Directory>[];
    final prefixRoot = Directory('$home/Games/Heroic/Prefixes');
    if (prefixRoot.existsSync()) {
      for (final level1 in prefixRoot.listSync().whereType<Directory>()) {
        roots.add(level1);
        for (final level2 in level1.listSync().whereType<Directory>()) {
          roots.add(level2);
        }
      }
    }
    final candidates = <String>[];
    for (final root in roots) {
      for (final pfx in ['${root.path}/pfx', root.path]) {
        final users = Directory('$pfx/drive_c/users');
        if (!users.existsSync()) continue;
        for (final u in users.listSync().whereType<Directory>()) {
          for (final tail in tails) {
            candidates.add('${u.path}/$tail');
          }
        }
      }
    }
    final user = Platform.environment['USER'] ?? '';
    for (final tail in tails) {
      candidates.add('$home/.wine/drive_c/users/$user/$tail');
    }
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  // Parses the whole current session first (Arena wipes the log per restart),
  // then keeps tailing new lines. Huge logs are capped to the newest chunk.
  void start(String path) {
    stop();
    final file = File(path);
    _offset = 0;
    if (file.existsSync()) {
      const cap = 32 * 1024 * 1024;
      final len = file.lengthSync();
      if (len > cap) _offset = len - cap;
      _poll(file);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll(file));
  }

  void _poll(File file) {
    if (!file.existsSync()) return;
    final len = file.lengthSync();
    // Arena restarted and truncated the log
    if (len < _offset) _offset = 0;
    if (len == _offset) return;
    final raf = file.openSync();
    raf.setPositionSync(_offset);
    final chunk = String.fromCharCodes(raf.readSync(len - _offset));
    raf.closeSync();
    _offset = len;
    _parse(chunk);
  }

  // Arena log formats shift between versions, these patterns cover the common ones
  // Packs arrive as "PackCards":"id,id,..." in Draft.Notify and BotDraft payloads
  // Picks arrive as GrpId/CardId numbers or PickGrpIds arrays in pick payloads
  // Arena nests draft payloads as escaped JSON strings, so quotes may appear as \"
  // Packs: "PackCards":"id,id,..."  Picks: "GrpIds":[id] or older "GrpId":id
  static final _packRe = RegExp(r'\\?"PackCards\\?"\s*:\s*\\?"([0-9,\s]+)\\?"');
  static final _pickCtxRe = RegExp(r'DraftMakePick|BotDraft_DraftPick');
  static final _pickListRe = RegExp(r'\\?"(?:Pick)?GrpIds\\?"\s*:\s*\[([0-9,\s]+)\]');
  static final _pickRe = RegExp(r'\\?"(?:GrpId|CardId)\\?"\s*:\s*(\d+)');
  // Event names like PremierDraft_DFT_20260721 appear in every draft payload
  // Set codes are strictly uppercase, which filters out quest strings like Draft_Quest_
  static final _eventRe = RegExp(r'(PremierDraft|QuickDraft|TradDraft|BotDraft|CompDraft)_([A-Z0-9]{3,6})_');
  // Deck submissions carry MainDeck and Sideboard arrays, non-id numbers are filtered later
  static final _deckMainRe = RegExp(r'\\?"MainDeck\\?"\s*:\s*\[([^\]]*)\]');
  static final _deckSideRe = RegExp(r'\\?"Sideboard\\?"\s*:\s*\[([^\]]*)\]');
  static final _numRe = RegExp(r'\d+');

  void _parse(String chunk) {
    for (final m in _eventRe.allMatches(chunk)) {
      _controller.add(DraftInfoEvent(m.group(1)!, m.group(2)!.toUpperCase()));
    }
    for (final line in chunk.split('\n')) {
      final main = _deckMainRe.firstMatch(line);
      final side = _deckSideRe.firstMatch(line);
      if (main == null || side == null) continue;
      List<int> ids(Match m) => [for (final n in _numRe.allMatches(m.group(1)!)) int.parse(n.group(0)!)];
      _controller.add(DeckEvent(ids(main), ids(side)));
    }
    for (final m in _packRe.allMatches(chunk)) {
      final ids = [for (final s in m.group(1)!.split(',')) int.tryParse(s.trim()) ?? 0];
      final valid = ids.where((i) => i > 0).toList();
      if (valid.isNotEmpty) _controller.add(PackEvent(valid));
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