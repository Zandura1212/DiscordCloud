import 'package:shared_preferences/shared_preferences.dart';

class TokenService {
  static Future<Map<String, String>> loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString('discord_token') ?? '',
      'storage_channel': prefs.getString('storage_channel_id') ?? '',
      'list_channel': prefs.getString('list_channel_id') ?? '',
      'dl_token': prefs.getString('dl_discord_token') ?? '',
      'dl_storage_channel': prefs.getString('dl_storage_channel_id') ?? '',
      'dl_list_channel': prefs.getString('dl_list_channel_id') ?? '',
    };
  }

  static Future<void> save(bool isUpload, String t, String s, String l) async {
    final prefs = await SharedPreferences.getInstance();
    final p = isUpload ? '' : 'dl_';
    await prefs.setString('${p}discord_token', t);
    await prefs.setString('${p}storage_channel_id', s);
    await prefs.setString('${p}list_channel_id', l);
  }
}
