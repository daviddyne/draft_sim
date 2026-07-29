import 'dart:io';

// Reads Arena's log from disk, only used on desktop
class LogReader {
  static bool get available => true;

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

  static bool exists(String path) => File(path).existsSync();

  static int length(String path) => File(path).lengthSync();

  // Reads the part of the file that hasn't been seen yet
  static String read(String path, int from, int to) {
    final raf = File(path).openSync();
    raf.setPositionSync(from);
    final bytes = raf.readSync(to - from);
    raf.closeSync();
    return String.fromCharCodes(bytes);
  }
}