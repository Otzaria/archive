import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

/// A source that can be read in bounded chunks but refuses eager reads.
class _NoEagerInput extends InputMemoryStream {
  _NoEagerInput(super.bytes);

  @override
  int get length => throw StateError('length would decode a lazy source');

  @override
  Uint8List toUint8List() => throw StateError('unexpected eager conversion');
}

class _CopyStreamDecoder extends ChunkDecoder {
  _CopyStreamDecoder(this.source);

  final InputStream source;
  bool _ran = false;

  @override
  bool decodeChunk(OutputStream output) {
    if (_ran) return false;
    _ran = true;
    output.writeStream(source);
    return false;
  }
}

Uint8List _fixture() =>
    Uint8List.fromList(List<int>.generate(512 * 1024, (i) => (i * 37) & 255));

void main() {
  test('OutputMemoryStream streams input without querying lazy length', () {
    final data = _fixture();
    final input = _NoEagerInput(data)..skip(17);
    final output = OutputMemoryStream();
    output.writeBytes([1, 2, 3]);
    output.writeStream(input);

    expect(output.getBytes(), [1, 2, 3, ...data.skip(17)]);
    expect(input.position, 17, reason: 'writeStream must preserve position');
  });

  test('InputDecodeStream output copies large source in bounded chunks', () {
    final data = _fixture();
    final source = _NoEagerInput(data)..skip(31);
    final decoded = InputDecodeStream(_CopyStreamDecoder(source));
    final got = decoded.toUint8List();
    expect(got, data.sublist(31));
    expect(source.position, 31, reason: 'writeStream preserves source');
    decoded.closeSync();
  });

  test('OutputMemoryStream accepts lazy gzip output without draining source', () {
    final content = _fixture();
    final gz = GZipEncoder().encodeBytes(content);
    final source = GZipDecoder().decodeLazy(InputMemoryStream(gz));
    final out = OutputMemoryStream()..writeStream(source);
    expect(out.getBytes(), content);
  });
}
