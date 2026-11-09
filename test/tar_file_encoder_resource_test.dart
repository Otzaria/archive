@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('async TAR directory traversal keeps all files without a filter',
      () async {
    final dir = Directory.systemTemp.createTempSync('archive-tar-lazy-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = Directory(p.join(dir.path, 'source'))..createSync();
    Directory(p.join(source.path, 'sub')).createSync();
    File(p.join(source.path, 'a.txt')).writeAsStringSync('alpha');
    File(p.join(source.path, 'sub', 'b.txt')).writeAsStringSync('beta');

    final output = p.join(dir.path, 'all.tar');
    await TarFileEncoder().tarDirectory(source, filename: output);

    final archive = TarDecoder().decodeBytes(File(output).readAsBytesSync());
    expect(archive.findFile('source/a.txt')?.readBytes(), 'alpha'.codeUnits);
    expect(archive.findFile('source/sub/b.txt')?.readBytes(),
        'beta'.codeUnits);
  });

  test('async TAR traversal retains filtering and accurate progress',
      () async {
    final dir = Directory.systemTemp.createTempSync('archive-tar-filter-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = Directory(p.join(dir.path, 'source'))..createSync();
    File(p.join(source.path, 'keep.txt')).writeAsStringSync('keep');
    File(p.join(source.path, 'skip.txt')).writeAsStringSync('skip');

    final progress = <double>[];
    final output = p.join(dir.path, 'filtered.tar');
    await TarFileEncoder().tarDirectory(source, filename: output,
        filter: (file, fraction) {
      progress.add(fraction);
      return p.basename(file.path) == 'skip.txt'
          ? ZipFileOperation.skip
          : ZipFileOperation.include;
    });

    final archive = TarDecoder().decodeBytes(File(output).readAsBytesSync());
    expect(archive.findFile('source/keep.txt')?.readBytes(), 'keep'.codeUnits);
    expect(archive.findFile('source/skip.txt'), isNull);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });
}
