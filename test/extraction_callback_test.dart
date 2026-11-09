@TestOn('vm')
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  for (final extension in ['zip', 'tar']) {
    test('$extension only calls extraction callback for written files',
        () async {
      final dir = Directory.systemTemp.createTempSync('archive-callback-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = Directory(p.join(dir.path, 'out'))..createSync();
      final archive = Archive()
        ..addFile(ArchiveFile.string('../outside.txt', 'should not write'))
        ..addFile(ArchiveFile.string('nested/inside.txt', 'written'));
      final bytes = extension == 'zip'
          ? ZipEncoder().encodeBytes(archive)
          : TarEncoder().encodeBytes(archive);
      final sourceFile = File(p.join(dir.path, 'in.$extension'))
        ..writeAsBytesSync(bytes);

      final observed = <String>[];
      await extractFileToDisk(sourceFile.path, out.path,
          callback: (entry) => observed.add(entry.name));

      expect(observed, ['nested/inside.txt']);
      expect(File(p.join(dir.path, 'outside.txt')).existsSync(), isFalse);
      expect(
        File(p.join(out.path, 'nested', 'inside.txt')).readAsStringSync(),
        'written',
      );
    });
  }
}
