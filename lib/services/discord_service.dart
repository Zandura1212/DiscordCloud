import 'dart:convert';
import 'dart:io';
import 'package:nyxx/nyxx.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as pkg;
import 'dart:typed_data';

class DiscordService {
  NyxxGateway? _client;

  Future<void> login(String t) async {
    if (_client != null) return;
    _client = await Nyxx.connectGateway(t, GatewayIntents.allUnprivileged);
  }

  // 에러 발생 시 자동으로 5번 재시도하는 공용 래퍼
  Future<T> _retry<T>(Future<T> Function() action, {required Function(String) onLog, String task = "작업"}) async {
    int count = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        count++;
        if (count >= 5) {
          onLog("$task 실패 (최종): $e");
          rethrow;
        }
        final delay = count * 2;
        onLog("$task 오류. ${delay}초 후 재시도 ($count/5)...");
        await Future.delayed(Duration(seconds: delay));
        if (e.toString().contains("session")) await logout();
      }
    }
  }

  String encryptName(String n, String t) {
    final key = pkg.Key(Uint8List.fromList(sha256.convert(utf8.encode(t)).bytes));
    final iv = pkg.IV(Uint8List(16));
    return pkg.Encrypter(pkg.AES(key, mode: pkg.AESMode.cbc)).encrypt(n, iv: iv).base64;
  }

  String _decName(String b, String t) {
    try {
      final key = pkg.Key(Uint8List.fromList(sha256.convert(utf8.encode(t)).bytes));
      final iv = pkg.IV(Uint8List(16));
      return pkg.Encrypter(pkg.AES(key, mode: pkg.AESMode.cbc)).decrypt64(b, iv: iv);
    } catch (_) { return "Error"; }
  }

  Future<void> fetchFileList({required String listChannelId, required String token, required Function(String log) onLog}) async {
    await _retry(() async {
      await login(token);
      final channel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;
      onLog("서버 목록 동기화 중...");
      
      final List<Map<String, dynamic>> list = [];
      final me = await _client!.users.fetchCurrentUser();
      Snowflake? lastId;
      bool more = true;

      while (more) {
        final messages = await channel.messages.fetchMany(before: lastId, limit: 100);
        if (messages.isEmpty) break;
        for (final m in messages) {
          if (m.author.id != me.id || !m.content.contains('_') || m.content.endsWith('.del')) continue;
          final parts = m.content.split('_');
          final name = _decName(parts[0], token);
          if (name != "Error") {
            list.add({"display_name": name, "encrypted_name": parts[0], "count": parts[1], "time": m.timestamp.toIso8601String()});
          }
        }
        lastId = messages.last.id;
        if (messages.length < 100) more = false;
      }
      
      final path = Platform.environment['APPDATA'];
      if (path != null) {
        final dir = Directory('$path\\DiscordCloud');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('${dir.path}\\list.json').writeAsString(jsonEncode(list));
      }
      onLog("동기화 완료 (${list.length}개)");
    }, onLog: onLog, task: "목록 동기화");
    await logout();
  }

  Future<void> deleteFileMark({required String listChannelId, required String encryptedName, required String token, required Function(String log) onLog}) async {
    await _retry(() async {
      await login(token);
      final channel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;
      final me = await _client!.users.fetchCurrentUser();
      onLog("삭제할 기록 검색 중...");
      
      Snowflake? lastId;
      while (true) {
        final messages = await channel.messages.fetchMany(before: lastId, limit: 100);
        if (messages.isEmpty) break;
        for (final m in messages) {
          if (m.author.id == me.id && m.content.startsWith("${encryptedName}_") && !m.content.endsWith('.del')) {
            await channel.messages.update(m.id, MessageUpdateBuilder(content: "${m.content}.del"));
            onLog("서버 삭제 표시(.del) 완료.");
            return;
          }
        }
        lastId = messages.last.id;
        if (messages.length < 100) break;
      }
    }, onLog: onLog, task: "삭제 처리");
    await logout();
  }

  Future<bool> checkAndRestore({required String listChannelId, required String encryptedName, required String token, required Function(String log) onLog}) async {
    return await _retry(() async {
      await login(token);
      final channel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;
      final me = await _client!.users.fetchCurrentUser();
      onLog("서버 기록 조회 중...");
      
      Snowflake? lastId;
      while (true) {
        final messages = await channel.messages.fetchMany(before: lastId, limit: 100);
        if (messages.isEmpty) break;
        for (final m in messages) {
          if (m.author.id == me.id && m.content.startsWith("${encryptedName}_")) {
            if (m.content.endsWith('.del')) {
              onLog("과거 삭제 기록 발견. 복구 중...");
              await channel.messages.update(m.id, MessageUpdateBuilder(content: m.content.replaceFirst('.del', '')));
              onLog("삭제 기록이 복구되었습니다.");
              return true;
            }
            onLog("이미 서버에 존재하는 파일입니다.");
            return true;
          }
        }
        lastId = messages.last.id;
        if (messages.length < 100) break;
      }
      return false;
    }, onLog: onLog, task: "기록 체크");
  }

  Future<void> downloadChunks({required String storageChannelId, required String encryptedName, required int totalChunks, required String downloadPath, required String token, required Function(String log) onLog, required Function(double progress) onProgress}) async {
    await _retry(() async {
      await login(token);
      final channel = await _client!.channels.get(Snowflake.parse(storageChannelId)) as TextChannel;
      final Map<int, String> urls = {};
      onLog("청크 데이터 찾는 중...");
      
      Snowflake? lastId;
      while (urls.length < totalChunks) {
        final messages = await channel.messages.fetchMany(before: lastId, limit: 100);
        if (messages.isEmpty) break;
        for (final m in messages) {
          if (m.content.startsWith("${encryptedName}_")) {
            for (var a in m.attachments) {
              final idx = int.tryParse(a.fileName.split('.').first);
              if (idx != null) urls[idx] = a.url.toString();
            }
          }
        }
        lastId = messages.last.id;
        if (messages.length < 100) break;
      }
      
      if (urls.length < totalChunks) throw "조각 누락";
      if (!await Directory(downloadPath).exists()) await Directory(downloadPath).create(recursive: true);
      
      final client = HttpClient();
      for (int i = 0; i < totalChunks; i++) {
        final res = await (await client.getUrl(Uri.parse(urls[i]!))).close();
        await File('$downloadPath\\$i.txt').writeAsBytes(await res.fold<List<int>>([], (p, e) => p..addAll(e)));
        onProgress((i + 1) / totalChunks);
      }
      client.close();
    }, onLog: onLog, task: "다운로드");
    await logout();
  }

  Future<void> uploadChunks({required String storageChannelId, required String listChannelId, required String folderPath, required String originalFileName, required String token, required String uploadTime, required Function(String log) onLog, required Function(double progress) onProgress}) async {
    await _retry(() async {
      await login(token);
      final encName = encryptName(originalFileName, token);
      final files = Directory(folderPath).listSync().whereType<File>().toList();
      files.sort((a, b) => int.parse(a.path.split('\\').last.split('.').first).compareTo(int.parse(b.path.split('\\').last.split('.').first)));
      
      final sChan = await _client!.channels.get(Snowflake.parse(storageChannelId)) as TextChannel;
      final lChan = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;

      for (int i = 0; i < files.length; i += 10) {
        final group = files.sublist(i, (i + 10 < files.length) ? i + 10 : files.length);
        final List<AttachmentBuilder> atts = [];
        for (var f in group) atts.add(AttachmentBuilder(data: await f.readAsBytes(), fileName: f.path.split('\\').last));
        await sChan.sendMessage(MessageBuilder(content: "${encName}_${i ~/ 10}", attachments: atts));
        onLog("업로드 중... (${i + group.length}/${files.length})");
        onProgress((i + group.length) / files.length);
      }
      await lChan.sendMessage(MessageBuilder(content: "${encName}_${files.length}"));
    }, onLog: onLog, task: "업로드");
    await logout();
  }

  Future<void> logout() async {
    if (_client != null) {
      await _client!.close();
      _client = null;
    }
  }
}
