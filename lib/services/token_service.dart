import 'package:shared_preferences/shared_preferences.dart';

class TokenService {
  static const String _tokenKey = 'discord_token';
  static const String _storageChannelKey = 'storage_channel_id';
  static const String _listChannelKey = 'list_channel_id';
  
  // 다운로드용 키 추가
  static const String _dlTokenKey = 'dl_discord_token';
  static const String _dlStorageChannelKey = 'dl_storage_channel_id';
  static const String _dlListChannelKey = 'dl_list_channel_id';

  static Future<Map<String, String>> loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString(_tokenKey) ?? '',
      'storage_channel': prefs.getString(_storageChannelKey) ?? '',
      'list_channel': prefs.getString(_listChannelKey) ?? '',
      'dl_token': prefs.getString(_dlTokenKey) ?? '',
      'dl_storage_channel': prefs.getString(_dlStorageChannelKey) ?? '',
      'dl_list_channel': prefs.getString(_dlListChannelKey) ?? '',
    };
  }

  static Future<void> saveAllData({
    required String token,
    required String storageChannel,
    required String listChannel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_storageChannelKey, storageChannel);
    await prefs.setString(_listChannelKey, listChannel);
  }

  static Future<void> saveDownloadData({
    required String token,
    required String storageChannel,
    required String listChannel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dlTokenKey, token);
    await prefs.setString(_dlStorageChannelKey, storageChannel);
    await prefs.setString(_dlListChannelKey, listChannel);
  }
}
