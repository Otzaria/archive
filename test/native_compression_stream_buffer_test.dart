@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:test/test.dart';

class _ChunkOnlyInput extends InputMemoryStream {
  _ChunkOnlyInput(super.bytes);

  int calls = 0;

  @override
  int get length => throw StateError('eager length requested');

  @override
  InputStream readBytes(int count) =>
      throw StateError('eager readBytes($count) requested');

  @override
  int readInto(Uint8List into, int at, int count) {
    calls++;
    return super.readInto(into, at, count);
  }
}

Uint8List _payload(int length) {
  var state = 0x127bc921;
  return Uint8List.fromList(List<int>.generate(length, (_) {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return state >> 16 & 255;
  }));
}

void main() {
  test('GZip native encoder consumes input in bounded chunks', () {
    final bytes = _payload(2 * 1024 * 1024);
    final source = _ChunkOnlyInput(bytes);
    final packed = OutputMemoryStream();
    GZipEncoder().encodeStream(source, packed, level: 1);

    expect(source.calls, greaterThan(10));
    expect(source.position, bytes.length);
    expect(GZipDecoder().decodeBytes(packed.getBytes(), verify: true), bytes);
  });

  test('ZLib native encoder consumes input in bounded chunks', () {
    final bytes = _payload(2 * 1024 * 1024);
    final source = _ChunkOnlyInput(bytes);
    final packed = OutputMemoryStream();
    ZLibEncoder().encodeStream(source, packed, level: 1);

    expect(source.calls, greaterThan(10));
    expect(source.position, bytes.length);
    expect(ZLibDecoder().decodeBytes(packed.getBytes(), verify: true), bytes);
  });

  test('small chunks and empty inputs remain valid compressed streams', () {
    for (final data in <List<int>>[
      [],
      [0],
      [1, 2, 3, 4, 5],
    ]) {
      final gz = OutputMemoryStream();
      GZipEncoder().encodeStream(_ChunkOnlyInput(data), gz);
      expect(GZipDecoder().decodeBytes(gz.getBytes(), verify: true), data);

      final z = OutputMemoryStream();
      ZLibEncoder().encodeStream(_ChunkOnlyInput(data), z);
      expect(ZLibDecoder().decodeBytes(z.getBytes(), verify: true), data);
    }
  });
}
