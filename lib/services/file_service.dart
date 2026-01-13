import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class FileService {
  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  static Future<void> encryptAndSplitFile({
    required String sourceFilePath,
    required String destinationFolderPath,
    required String token,
    required Function(double progress, String remainingTime) onProgress,
    required Function(String log) onLog,
  }) async {
    final stopwatch = Stopwatch()..start();
    final file = File(sourceFilePath);
    final int totalFileSize = await file.length();
    
    final keyBytes = sha256.convert(utf8.encode(token)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    // 일관성을 위해 랜덤 IV 대신 고정 IV 사용
    final iv = encrypt.IV(Uint8List(16));
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final dir = Directory(destinationFolderPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final raf = await file.open();
    const int readChunkSize = 5 * 1024 * 1024; 
    int bytesProcessed = 0;
    int chunkIdx = 0;

    onLog("로컬 스트리밍 처리 시작...");

    try {
      while (bytesProcessed < totalFileSize) {
        final Uint8List buffer = await raf.read(readChunkSize);
        if (buffer.isEmpty) break;

        final compressed = zlib.encode(buffer);
        // 고정 IV 적용
        final encrypted = encrypter.encryptBytes(compressed, iv: iv);
        
        final chunkFile = File('$destinationFolderPath\\$chunkIdx.txt');
        await chunkFile.writeAsString("${iv.base64}:${encrypted.base64}");
        
        bytesProcessed += buffer.length;
        chunkIdx++;
        
        double progress = bytesProcessed / totalFileSize;
        String remainingTime = "";
        if (progress > 0) {
          final elapsed = stopwatch.elapsed;
          final estimatedTotal = elapsed.inMilliseconds / progress;
          final remaining = Duration(milliseconds: (estimatedTotal - elapsed.inMilliseconds).toInt());
          remainingTime = formatDuration(remaining);
        }
        
        onProgress(progress, remainingTime);
        await Future.delayed(Duration.zero);
      }
    } finally {
      await raf.close();
    }
    
    stopwatch.stop();
    onLog("로컬 분할 및 암호화 완료.");
  }
}
