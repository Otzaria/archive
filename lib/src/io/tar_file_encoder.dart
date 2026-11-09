import 'dart:io';

import 'package:path/path.dart' as path;

import '../archive/archive_file.dart';
import '../codecs/gzip_encoder.dart';
import '../codecs/tar_encoder.dart';
import '../codecs/zstd_encoder.dart';
import '../util/input_file_stream.dart';
import '../util/output_file_stream.dart';
import 'zip_file_progress.dart';

class TarFileEncoder {
  late String tarPath;
  late OutputFileStream _output;
  late TarEncoder _encoder;

  static const store = 0;
  static const gzip = 1;
  static const zstd = 2;

  Future<void> tarDirectory(Directory dir,
      {int compression = store,
      String? filename,
      bool followLinks = true,
      int? level,
      ZipFileProgress? filter}) async {
    final dirPath = dir.path;
    var tarPath = filename ?? '$dirPath.tar';
    final tgzPath = filename ?? '$dirPath.tar.gz';
    final tzstPath = filename ?? '$dirPath.tar.zst';

    Directory? tempDir;
    if (compression == gzip || compression == zstd) {
      tempDir = await Directory.systemTemp.createTemp('dart_archive');
      tarPath = '${tempDir.path}/temp.tar';
    }

    // Encode a directory from disk to disk, no memory
    try {
      open(tarPath);
      try {
        await addDirectory(Directory(dirPath),
            followLinks: followLinks, filter: filter);
      } finally {
        await close();
      }

      if (compression == gzip) {
        InputFileStream? input;
        OutputFileStream? output;
        try {
          input = InputFileStream(tarPath);
          output = OutputFileStream(tgzPath);
          GZipEncoder().encodeStream(input, output, level: level ?? 6);
        } finally {
          await input?.close();
          await output?.close();
        }
      } else if (compression == zstd) {
        InputFileStream? input;
        OutputFileStream? output;
        try {
          input = InputFileStream(tarPath);
          output = OutputFileStream(tzstPath);
          ZstdEncoder()
              .encodeStream(input, output, level: level, checksum: true);
        } finally {
          await input?.close();
          await output?.close();
        }
      }
    } finally {
      await tempDir?.delete(recursive: true);
    }
  }

  void open(String tarPath) => create(tarPath);

  void create(String tarPath) {
    this.tarPath = tarPath;
    _output = OutputFileStream(tarPath);
    _encoder = TarEncoder();
    _encoder.start(_output);
  }

  Future<void> addDirectory(Directory dir,
      {bool followLinks = true,
      bool includeDirName = true,
      ZipFileProgress? filter}) async {
    // Enumerate lazily rather than allocating a list for every file in a
    // large directory. Count asynchronously only when the filter needs the
    // progress fraction.
    var numFiles = 0;
    if (filter != null) {
      await for (final _ in
          dir.list(recursive: true, followLinks: followLinks)) {
        numFiles++;
      }
    }

    final dirName = path.basename(dir.path);
    var fileCount = 0;
    await for (final file in
        dir.list(recursive: true, followLinks: followLinks)) {
      final progress = numFiles == 0 ? 0.0 : ++fileCount / numFiles;
      if (filter != null) {
        final operation = filter(file, progress);
        if (operation == ZipFileOperation.cancel) {
          break;
        }
        if (operation == ZipFileOperation.skip) {
          continue;
        }
      }
      if (file is Directory) {
        var filename = path.relative(file.path, from: dir.path);
        filename = includeDirName ? '$dirName/$filename' : filename;
        final af = ArchiveFile.directory('$filename/');
        af.mode = (await file.stat()).mode;
        _encoder.add(af);
      } else if (file is File) {
        final dirName = path.basename(dir.path);
        final relPath = path.relative(file.path, from: dir.path);
        await addFile(file, includeDirName ? '$dirName/$relPath' : relPath);
      }
    }
  }

  Future<void> addFile(File file, [String? filename]) async {
    final fileStream = InputFileStream(file.path);
    try {
      final f =
          ArchiveFile.stream(filename ?? path.basename(file.path), fileStream);
      f.lastModTime = (await file.lastModified()).millisecondsSinceEpoch ~/ 1000;
      f.mode = (await file.stat()).mode;
      _encoder.add(f);
    } finally {
      // A stat or encoding error must not retain an open file descriptor.
      await fileStream.close();
    }
  }

  Future<void> close() async {
    try {
      _encoder.finish();
    } finally {
      await _output.close();
    }
  }
}
