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

  String _encName(String n, String t) {
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
    await login(token);
    try {
      final channel = await _client!.channels.get(Snowflake.parse(listChannelId)) as TextChannel;
      onLog("동기화 시작...");
      final List<Map<String, dynamic>> list = [];
      final me = await _client!.users.fetchCurrentUser();
      Snowflake? lastId;
      bool more = true;

      while (more) {
        final messages = await channel.messages.fetchMany(before: lastId, limit: 100);
        if (messages.isEmpty) break;
        for (final m in messages) {
          if (m.author.id != me.id || !m.content.contains('_')) continue;
          final parts = m.content.split('_');
          final name = _decName(parts[0], token);
          if (name != "Error") {
            list.add({"display_name": name, "encrypted_name": parts[0], "count": parts[1], "time": m.timestamp.toIso8601String()});
          }
        }
        lastId = messages.last.id;
        if (messages.length < 100) more = false;
      }
      final String? path = Platform.environment['APPDATA'];
      if (path != null) await File('$path\\DiscordCloud\\list.json').writeAsString(jsonEncode(list));
      onLog("동기화 완료 (${list.length}개)");
    } catch (e) { onLog("실패: $e"); } finally { await logout(); }
  }

  Future<void> downloadChunks({required String storageChannelId, required String encryptedName, required int totalChunks, required String downloadPath, required String token, required Function(String log) onLog, required Function(double progress) onProgress}) async {
    await login(token);
    try {
      final channel = await _client!.channels.get(Snowflake.parse(storageChannelId)) as TextChannel;
      final Map<int, String> urls = {};
      onLog("청크 검색 중...");
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
      if (urls.length < totalChunks) throw "일부 조각 누락";
      if (!await Directory(downloadPath).exists()) await Directory(downloadPath).create(recursive: true);
      final client = HttpClient();
      for (int i = 0; i < totalChunks; i++) {
        final res = await (await client.getUrl(Uri.parse(urls[i]!))).close();
        await File('$downloadPath\\$i.txt').writeAsBytes(await res.fold<List<int>>([], (p, e) => p..addAll(e)));
        onProgress((i + 1) / totalChunks);
        if (i % 5 == 0) onLog("다운로드: $i/$totalChunks");
      }
      client.close();
    } finally { await logout(); }
  }

  Future<void> uploadChunks({required String storageChannelId, required String listChannelId, required String folderPath, required String originalFileName, required String token, required String uploadTime, required Function(String log) onLog, required Function(double progress) onProgress}) async {
    await login(token);
    try {
      final files = Directory(folderPath).listSync().whereType<File>().toList();
      files.sort((a, b) => int.parse(a.path.split('\\').last.split('.').first).compareTo(int.parse(b.path.split('\\').last.split('.').first)));
      final encName = _encName(originalFileName, token);
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
      final String? path = Platform.environment['APPDATA'];
      if (path != null) {
        final file = File('$path\\DiscordCloud\\list.json');
        List history = [];
        if (await file.exists()) history = jsonDecode(await file.readAsString());
        history.add({"display_name": originalFileName, "encrypted_name": encName, "count": files.length.toString(), "time": uploadTime});
        await file.writeAsString(jsonEncode(history));
      }
    } finally { await logout(); }
  }

  Future<void> logout() async { if (_client != null) { await _client!.close(); _client = null; } }
}
