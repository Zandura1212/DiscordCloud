import 'dart:convert';
import 'dart:io';
import 'package:nyxx/nyxx.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'dart:typed_data';

class DiscordService {
  NyxxGateway? _client;

  // 봇 로그인
  Future<void> login(String token) async {
    if (_client != null) return;
    _client = await Nyxx.connectGateway(
      token,
      GatewayIntents.allUnprivileged,
    );
  }

  // 파일명 암호화 유틸리티 (일관성을 위해 고정 IV 사용)
  String _encryptFileName(String fileName, String token) {
    final keyBytes = sha256.convert(utf8.encode(token)).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt_pkg.IV(Uint8List(16)); // 고정 IV (전부 0)
    final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
    return encrypter.encrypt(fileName, iv: iv).base64;
  }

  // 파일명 복호화 유틸리티 (일관성을 위해 고정 IV 사용)
  String _decryptFileName(String encryptedBase64, String token) {
    try {
      final keyBytes = sha256.convert(utf8.encode(token)).bytes;
      final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
      final iv = encrypt_pkg.IV(Uint8List(16)); // 고정 IV
      final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc));
      return encrypter.decrypt64(encryptedBase64, iv: iv);
    } catch (e) {
      return "Decryption Error";
    }
  }

  // 리스트 채널에서 모든 과거 메시지 불러오기
  Future<void> fetchFileList({
    required String listChannelId,
    required String token,
    required Function(String log) onLog,
  }) async {
    await login(token);
    
    try {
      final channel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;
      onLog("리스트 채널 전체 내역 동기화 시작...");

      final List<Map<String, dynamic>> fetchedList = [];
      final me = await _client!.users.fetchCurrentUser();
      
      Snowflake? lastMessageId;
      bool hasMore = true;

      while (hasMore) {
        final List<Message> messages = await channel.messages.fetchMany(
          before: lastMessageId,
          limit: 100,
        );

        if (messages.isEmpty) {
          hasMore = false;
          break;
        }

        for (final message in messages) {
          if (message.author.id != me.id) continue;

          final content = message.content;
          final lastUnderscore = content.lastIndexOf('_');
          
          if (lastUnderscore == -1) continue;

          // 구분자(_) 앞부분만 정확히 추출
          final encPart = content.substring(0, lastUnderscore);
          final countPart = content.substring(lastUnderscore + 1);
          
          if (int.tryParse(countPart) == null) continue;

          // 앞부분 해독
          final displayName = _decryptFileName(encPart, token);
          
          if (displayName != "Decryption Error") {
            fetchedList.add({
              "display_name": displayName,
              "encrypted_name": encPart,
              "count": countPart,
              "time": message.timestamp.toIso8601String(),
            });
          }
        }

        lastMessageId = messages.last.id;
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (messages.length < 100) {
          hasMore = false;
        }
      }

      final String? appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final listFile = File('$appData\\DiscordCloud\\list.json');
        await listFile.writeAsString(jsonEncode(fetchedList));
        onLog("동기화 완료: 총 ${fetchedList.length}개의 파일을 찾았습니다.");
      }

      await logout();
    } catch (e) {
      onLog("리스트 불러오기 실패: $e");
      rethrow;
    }
  }

  // 파일 업로드 로직
  Future<void> uploadChunks({
    required String storageChannelId,
    required String listChannelId,
    required String folderPath,
    required String originalFileName,
    required String token,
    required String uploadTime,
    required Function(String log) onLog,
    required Function(double progress) onProgress,
  }) async {
    if (_client == null) throw Exception("봇이 로그인되어 있지 않습니다.");

    try {
      final directory = Directory(folderPath);
      final List<File> files = directory.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList();
      
      files.sort((a, b) {
        int aIdx = int.parse(a.path.split(Platform.pathSeparator).last.split('.').first);
        int bIdx = int.parse(b.path.split(Platform.pathSeparator).last.split('.').first);
        return aIdx.compareTo(bIdx);
      });

      final String encryptedName = _encryptFileName(originalFileName, token);
      final storageChannel = await _client!.channels.get(Snowflake.parse(storageChannelId)) as TextChannel;
      final listChannel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;

      onLog("디스코드 업로드 시작: 10개씩 묶음 처리 중...");

      for (int i = 0; i < files.length; i += 10) {
        final int end = (i + 10 < files.length) ? i + 10 : files.length;
        final List<File> chunkGroup = files.sublist(i, end);
        final int groupIdx = i ~/ 10;

        final List<AttachmentBuilder> attachments = [];
        for (var f in chunkGroup) {
          final bytes = await f.readAsBytes();
          attachments.add(AttachmentBuilder(
            data: bytes,
            fileName: f.path.split(Platform.pathSeparator).last,
          ));
        }

        await storageChannel.sendMessage(
          MessageBuilder(
            content: "${encryptedName}_$groupIdx",
            attachments: attachments,
          ),
        );

        onLog("메시지 업로드 중 (${i + chunkGroup.length}/${files.length})");
        onProgress((i + chunkGroup.length) / files.length);
      }

      await listChannel.sendMessage(
        MessageBuilder(
          content: "${encryptedName}_${files.length}",
        ),
      );
      
      onLog("리스트 채널 기록 완료: ${encryptedName}_${files.length}");

      try {
        final String? appData = Platform.environment['APPDATA'];
        if (appData != null) {
          final listFile = File('$appData\\DiscordCloud\\list.json');
          List<dynamic> history = [];
          if (await listFile.exists()) {
            try {
              final String content = await listFile.readAsString();
              if (content.isNotEmpty) {
                final decoded = jsonDecode(content);
                if (decoded is List) history = decoded;
              }
            } catch (e) {}
          }

          history.add({
            "display_name": originalFileName,
            "encrypted_name": encryptedName,
            "count": files.length.toString(),
            "time": uploadTime
          });

          await listFile.writeAsString(jsonEncode(history));
        }
      } catch (e) {}
      
      onLog("모든 전송이 완료되어 봇을 종료합니다.");
      await logout();
      
    } catch (e) {
      onLog("업로드 중 오류 발생: $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    if (_client != null) {
      await _client!.close();
      _client = null;
    }
  }
}
