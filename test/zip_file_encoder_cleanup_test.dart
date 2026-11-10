@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('failed ZIP directory creation deletes a partially written archive',
      () async {
    final root = Directory.systemTemp.createTempSync('archive-zip-failure-');
    addTearDown(() => root.deleteSync(recursive: true));
    final input = Directory(p.join(root.path, 'source'))..createSync();
    File(p.join(input.path, 'a.txt')).writeAsStringSync('data');
    File(p.join(input.path, 'b.txt')).writeAsStringSync('data');
    final out = p.join(root.path, 'archive.zip');

    await expectLater(
      ZipFileEncoder().zipDirectory(input, filename: out,
          filter: (entry, progress) => throw StateError('test failure')),
      throwsA(isA<StateError>()),
    );
    expect(File(out).existsSync(), isFalse);
  });

  test('ZIP cancellation still completes as a valid partial archive',
      () async {
    final root = Directory.systemTemp.createTempSync('archive-zip-cancel-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    File(p.join(source.path, 'a.txt')).writeAsStringSync('a');
    final out = p.join(root.path, 'cancelled.zip');

    await ZipFileEncoder().zipDirectory(source, filename: out,
        filter: (entry, progress) => ZipFileOperation.cancel);
    expect(File(out).existsSync(), isTrue);
    expect(ZipDecoder().decodeBytes(File(out).readAsBytesSync()), isEmpty);
  });

  test('successful ZIP directory still preserves all entries', () async {
    final root = Directory.systemTemp.createTempSync('archive-zip-success-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    File(p.join(source.path, 'a.txt')).writeAsStringSync('hello');
    final out = p.join(root.path, 'complete.zip');
    await ZipFileEncoder().zipDirectory(source, filename: out);
    expect(ZipDecoder().decodeBytes(File(out).readAsBytesSync())
        .findFile('a.txt')?.readBytes(), 'hello'.codeUnits);
  });
}
