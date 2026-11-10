@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('streamed tar.gz roundtrips nested files and a large asset', () async {
    final base = Directory.systemTemp.createTempSync('archive-tgz-stream-');
    addTearDown(() => base.deleteSync(recursive: true));
    final source = Directory(p.join(base.path, 'source'))..createSync();
    Directory(p.join(source.path, 'nested')).createSync();

    final bytes = Uint8List(8 * 1024 * 1024);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i * 37 + i ~/ 1003) & 0xff;
    }
    File(p.join(source.path, 'large.bin')).writeAsBytesSync(bytes);
    File(p.join(source.path, 'nested', 'hebrew.txt'))
        .writeAsStringSync('שלום');

    final out = p.join(base.path, 'books.tar.gz');
    await TarFileEncoder().tarDirectory(source,
        compression: TarFileEncoder.gzip, filename: out);

    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(File(out).readAsBytesSync(), verify: true),
      verify: true,
    );
    expect(archive.findFile('source/large.bin')?.readBytes(), bytes);
    expect(archive.findFile('source/nested/hebrew.txt')?.readBytes(),
        File(p.join(source.path, 'nested', 'hebrew.txt')).readAsBytesSync());
  });

  test('streamed tar.gz preserves filter semantics and compression level',
      () async {
    final base = Directory.systemTemp.createTempSync('archive-tgz-filter-');
    addTearDown(() => base.deleteSync(recursive: true));
    final source = Directory(p.join(base.path, 'source'))..createSync();
    File(p.join(source.path, 'keep.txt')).writeAsStringSync('keep');
    File(p.join(source.path, 'skip.txt')).writeAsStringSync('skip');
    final observed = <double>[];
    for (final level in [1, 6, 9]) {
      final out = p.join(base.path, 'filtered-$level.tgz');
      await TarFileEncoder().tarDirectory(source,
          compression: TarFileEncoder.gzip,
          level: level,
          filename: out,
          filter: (file, progress) {
            observed.add(progress);
            return p.basename(file.path) == 'skip.txt'
                ? ZipFileOperation.skip
                : ZipFileOperation.include;
          });
      final archive = TarDecoder().decodeBytes(
          GZipDecoder().decodeBytes(File(out).readAsBytesSync(), verify: true));
      expect(archive.findFile('source/keep.txt')?.readBytes(),
          'keep'.codeUnits);
      expect(archive.findFile('source/skip.txt'), isNull);
    }
    expect(observed, isNotEmpty);
    expect(observed.last, 1.0);
  });

  test('compression errors remove partial archive', () async {
    final base = Directory.systemTemp.createTempSync('archive-tgz-failed-');
    addTearDown(() => base.deleteSync(recursive: true));
    final source = Directory(p.join(base.path, 'source'))..createSync();
    File(p.join(source.path, 'ok.txt')).writeAsStringSync('ok');
    final out = p.join(base.path, 'failed.tar.gz');
    await expectLater(
      TarFileEncoder().tarDirectory(source,
          compression: TarFileEncoder.gzip,
          filename: out,
          filter: (file, progress) => throw StateError('abort')),
      throwsA(isA<StateError>()),
    );
    expect(File(out).existsSync(), isFalse);
  });
}
