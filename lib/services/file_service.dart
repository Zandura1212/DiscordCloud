import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class FileService {
  static String _fmt(Duration d) => "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

  static Future<void> encryptAndSplitFile({
    required String sourceFilePath,
    required String destinationFolderPath,
    required String token,
    required Function(double progress, String remainingTime) onProgress,
    required Function(String log) onLog,
  }) async {
    final stopwatch = Stopwatch()..start();
    final file = File(sourceFilePath);
    final int totalSize = await file.length();
    final key = encrypt.Key(Uint8List.fromList(sha256.convert(utf8.encode(token)).bytes));
    final iv = encrypt.IV(Uint8List(16));
    final enc = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    if (!await Directory(destinationFolderPath).exists()) await Directory(destinationFolderPath).create(recursive: true);

    final raf = await file.open();
    const int chunkSize = 5 * 1024 * 1024;
    int processed = 0, idx = 0;

    onLog("로컬 스트리밍 처리 시작...");
    try {
      while (processed < totalSize) {
        final buffer = await raf.read(chunkSize);
        if (buffer.isEmpty) break;
        final encrypted = enc.encryptBytes(zlib.encode(buffer), iv: iv);
        await File('$destinationFolderPath\\$idx.txt').writeAsString("${iv.base64}:${encrypted.base64}");
        processed += buffer.length;
        double prog = processed / totalSize;
        onProgress(prog, prog > 0 ? _fmt(Duration(milliseconds: (stopwatch.elapsed.inMilliseconds / prog - stopwatch.elapsed.inMilliseconds).toInt())) : "계산 중");
        idx++;
        await Future.delayed(Duration.zero);
      }
    } finally {
      await raf.close();
    }
    onLog("로컬 분할 및 암호화 완료.");
  }

  static Future<void> mergeAndDecryptFile({
    required String sourceFolderPath,
    required String targetFilePath,
    required String token,
    required int totalChunks,
    required Function(double progress) onProgress,
    required Function(String log) onLog,
  }) async {
    final outputSink = File(targetFilePath).openWrite();
    final key = encrypt.Key(Uint8List.fromList(sha256.convert(utf8.encode(token)).bytes));
    final enc = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    onLog("파일 복원 시작...");
    try {
      for (int i = 0; i < totalChunks; i++) {
        final parts = (await File('$sourceFolderPath\\$i.txt').readAsString()).split(':');
        outputSink.add(zlib.decode(enc.decryptBytes(encrypt.Encrypted.fromBase64(parts[1]), iv: encrypt.IV.fromBase64(parts[0]))));
        onProgress((i + 1) / totalChunks);
        if (i % 5 == 0) onLog("복원 중: $i / $totalChunks 조각 완료");
        await Future.delayed(Duration.zero);
      }
    } finally {
      await outputSink.close();
    }
    onLog("성공: 원본 파일 복원 완료.");
  }
}
