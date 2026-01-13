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

  // 파일 업로드용 암호화/분할
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
    final iv = encrypt.IV(Uint8List(16)); // 고정 IV
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
        final buffer = await raf.read(readChunkSize);
        if (buffer.isEmpty) break;

        final compressed = zlib.encode(buffer);
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

  // 다운로드한 조각들을 원본 파일로 복원하는 함수
  static Future<void> mergeAndDecryptFile({
    required String sourceFolderPath,
    required String targetFilePath,
    required String token,
    required int totalChunks,
    required Function(double progress) onProgress,
    required Function(String log) onLog,
  }) async {
    final outputFile = File(targetFilePath);
    final outputSink = outputFile.openWrite();
    
    final keyBytes = sha256.convert(utf8.encode(token)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    onLog("파일 복원 및 복호화 시작...");

    try {
      for (int i = 0; i < totalChunks; i++) {
        final chunkFile = File('$sourceFolderPath\\$i.txt');
        if (!await chunkFile.exists()) throw Exception("조각 #$i 파일을 찾을 수 없습니다.");

        final String content = await chunkFile.readAsString();
        final parts = content.split(':');
        if (parts.length != 2) throw Exception("조각 #$i 형식이 잘못되었습니다.");

        final iv = encrypt.IV.fromBase64(parts[0]);
        final encryptedData = encrypt.Encrypted.fromBase64(parts[1]);

        // 복호화
        final decryptedBytes = encrypter.decryptBytes(encryptedData, iv: iv);
        
        // 압축 해제
        final decompressedBytes = zlib.decode(decryptedBytes);
        
        // 원본 파일에 쓰기
        outputSink.add(decompressedBytes);
        
        onProgress((i + 1) / totalChunks);
        if (i % 5 == 0) onLog("복원 중: $i / $totalChunks 조각 완료");
        await Future.delayed(Duration.zero);
      }
    } finally {
      await outputSink.close();
    }
    
    onLog("성공: 원본 파일 복원 완료 ($targetFilePath)");
  }
}
