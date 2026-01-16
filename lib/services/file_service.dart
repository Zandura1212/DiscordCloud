import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class FileService {
  static String _formatDuration(Duration d) =>
      "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";

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
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    if (!await Directory(destinationFolderPath).exists()) {
      await Directory(destinationFolderPath).create(recursive: true);
    }

    final raf = await file.open();
    const int chunkSize = 5 * 1024 * 1024;
    int processed = 0, index = 0;

    onLog("로컬 데이터 처리 시작...");
    try {
      while (processed < totalSize) {
        final buffer = await raf.read(chunkSize);
        if (buffer.isEmpty) break;

        final encrypted = encrypter.encryptBytes(zlib.encode(buffer), iv: iv);
        await File('$destinationFolderPath\\$index.txt').writeAsString("${iv.base64}:${encrypted.base64}");

        processed += buffer.length;
        double progress = processed / totalSize;
        String etr = progress > 0 
            ? _formatDuration(Duration(milliseconds: (stopwatch.elapsed.inMilliseconds / progress - stopwatch.elapsed.inMilliseconds).toInt())) 
            : "계산 중";

        onProgress(progress, etr);
        index++;
        await Future.delayed(Duration.zero);
      }
    } finally {
      await raf.close();
    }
    onLog("로컬 데이터 암호화 완료.");
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
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    onLog("파일 복원 및 복호화 시작...");
    try {
      for (int i = 0; i < totalChunks; i++) {
        final content = await File('$sourceFolderPath\\$i.txt').readAsString();
        final parts = content.split(':');
        
        final decrypted = encrypter.decryptBytes(encrypt.Encrypted.fromBase64(parts[1]), iv: encrypt.IV.fromBase64(parts[0]));
        outputSink.add(zlib.decode(decrypted));

        onProgress((i + 1) / totalChunks);
        if (i % 5 == 0) onLog("복원 진행 중: $i / $totalChunks");
        await Future.delayed(Duration.zero);
      }
    } finally {
      await outputSink.close();
    }
    onLog("원본 파일 복원 완료.");
  }
}
