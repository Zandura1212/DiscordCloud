import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../services/file_service.dart';
import '../services/token_service.dart';
import '../services/discord_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  final PageController _pageController = PageController();
  final TextEditingController _t1 = TextEditingController(), _s1 = TextEditingController(), _l1 = TextEditingController();
  final TextEditingController _t2 = TextEditingController(), _s2 = TextEditingController(), _l2 = TextEditingController();
  final FocusNode _f1 = FocusNode(), _fs1 = FocusNode(), _fl1 = FocusNode();
  final FocusNode _f2 = FocusNode(), _fs2 = FocusNode(), _fl2 = FocusNode();
  final ScrollController _sc1 = ScrollController(), _sc2 = ScrollController();
  final DiscordService _ds = DiscordService();
  
  final List<String> _logs = [], _dlLogs = [];
  List<Map<String, dynamic>> _fileList = [];
  List<Map<String, dynamic>> _downloadQueue = []; 
  
  String? _selId; 
  List<String> _selectedFilePaths = []; 
  int _curr = 0;
  bool _obs1 = true, _obs2 = true, _isUp = false, _isDown = false;
  double _prog1 = 0.0, _prog2 = 0.0;
  String _etr1 = "", _etr2 = "";

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initData();
    _loadFileList();
    void update() => setState(() {});
    [_t1, _s1, _l1, _t2, _s2, _l2].forEach((c) => c.addListener(update));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    [_f1, _fs1, _fl1, _f2, _fs2, _fl2, _t1, _s1, _l1, _t2, _s2, _l2, _pageController, _sc1, _sc2].forEach((o) => o.dispose());
    _ds.logout();
    super.dispose();
  }

  Future<void> _initData() async {
    final d = await TokenService.loadAllData();
    _t1.text = d['token']!; _s1.text = d['storage_channel']!; _l1.text = d['list_channel']!;
    _t2.text = d['dl_token']!; _s2.text = d['dl_storage_channel']!; _l2.text = d['dl_list_channel']!;
  }

  void _addLog(bool isUp, String msg) {
    final list = isUp ? _logs : _dlLogs;
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    if (mounted) setState(() { list.add("[$time] $msg"); if (list.length > 500) list.removeAt(0); });
    final sc = isUp ? _sc1 : _sc2;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (sc.hasClients) sc.jumpTo(sc.position.maxScrollExtent); });
  }

  Future<void> _loadFileList() async {
    final path = Platform.environment['APPDATA'];
    if (path == null) return;
    final file = File('$path\\DiscordCloud\\list.json');
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) setState(() {
        final Map<String, Map<String, dynamic>> unique = {};
        for (var item in decoded) unique[item['encrypted_name']] = Map<String, dynamic>.from(item);
        _fileList = unique.values.toList();
        if (_selId != null && !_fileList.any((f) => f['encrypted_name'] == _selId)) _selId = null;
      });
    }
  }

  Future<void> _clean() async {
    final path = Platform.environment['APPDATA'];
    if (path == null) return;
    final dir = Directory('$path\\DiscordCloud');
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is Directory) await e.delete(recursive: true);
        else if (e is File && !e.path.endsWith('list.json')) await e.delete();
      }
    }
  }

  @override void onWindowClose() async { await _clean(); await windowManager.destroy(); }

  Future<void> _up() async {
    if (_selectedFilePaths.isEmpty || _isUp) return;
    setState(() { _isUp = true; _prog1 = 0.0; _etr1 = "준비 중..."; });
    try {
      final path = Platform.environment['APPDATA']!;
      for (int i = 0; i < _selectedFilePaths.length; i++) {
        final currentPath = _selectedFilePaths[i];
        final originalName = currentPath.split(Platform.pathSeparator).last;
        final folder = '$path\\DiscordCloud\\${originalName.replaceAll('.', '_')}';
        final time = DateTime.now().toIso8601String();
        _addLog(true, "처리 중 (${i + 1}/${_selectedFilePaths.length}): $originalName");
        await FileService.encryptAndSplitFile(sourceFilePath: currentPath, destinationFolderPath: folder, token: _t1.text, onLog: (m) => _addLog(true, m), onProgress: (p, e) => setState(() { _prog1 = ((i / _selectedFilePaths.length) + (p * 0.3 / _selectedFilePaths.length)).clamp(0.0, 1.0); _etr1 = e; }));
        await _ds.login(_t1.text);
        await _ds.uploadChunks(storageChannelId: _s1.text, listChannelId: _l1.text, folderPath: folder, originalFileName: originalName, token: _t1.text, uploadTime: time, onLog: (m) => _addLog(true, m), onProgress: (p) => setState(() { _prog1 = ((i / _selectedFilePaths.length) + ((0.3 + p * 0.7) / _selectedFilePaths.length)).clamp(0.0, 1.0); _etr1 = "업로드 중"; }));
        await _clean();
      }
      await _loadFileList(); _selectedFilePaths = []; _addLog(true, "모든 업로드 완료.");
    } catch (e) { _addLog(true, "에러: $e"); } finally { setState(() { _isUp = false; _prog1 = 1.0; _etr1 = "완료"; }); }
  }

  Future<void> _startQueueDownload() async {
    if (_downloadQueue.isEmpty || _isDown) return;
    
    // 1. 저장할 폴더 딱 한 번만 선택
    String? outputDir = await FilePicker.platform.getDirectoryPath(dialogTitle: '파일들을 저장할 폴더를 선택하세요');
    if (outputDir == null) return;

    setState(() => _isDown = true);
    while (_downloadQueue.isNotEmpty) {
      final fileData = _downloadQueue.first;
      final targetPath = '$outputDir\\${fileData['display_name']}';
      
      setState(() { _prog2 = 0.0; _etr2 = "준비 중..."; });
      try {
        final temp = '${Platform.environment['APPDATA']}\\DiscordCloud\\temp_dl';
        _addLog(false, "작업 시작 (${_downloadQueue.length}개 남음): ${fileData['display_name']}");
        final int count = int.tryParse(fileData['count'].toString()) ?? 0;
        
        await _ds.downloadChunks(storageChannelId: _s2.text, encryptedName: fileData['encrypted_name'], totalChunks: count, downloadPath: temp, token: _t2.text, onLog: (m) => _addLog(false, m), onProgress: (p) => setState(() { _prog2 = (p * 0.7).clamp(0.0, 1.0); _etr2 = "수신 중"; }));
        await FileService.mergeAndDecryptFile(sourceFolderPath: temp, targetFilePath: targetPath, token: _t2.text, totalChunks: count, onLog: (m) => _addLog(false, m), onProgress: (p) => setState(() { _prog2 = (0.7 + (p * 0.3)).clamp(0.0, 1.0); _etr2 = "복원 중"; }));
        
        final d = Directory(temp); if (await d.exists()) await d.delete(recursive: true);
        _addLog(false, "완료: $targetPath");
      } catch (e) { _addLog(false, "에러 (${fileData['display_name']}): $e"); }
      
      setState(() { _downloadQueue.removeAt(0); _prog2 = 0.0; });
    }
    setState(() => _isDown = false);
    _addLog(false, "모든 다운로드 작업이 종료되었습니다.");
  }

  void _addToQueue() {
    if (_selId == null) return;
    final file = _fileList.firstWhere((f) => f['encrypted_name'] == _selId);
    if (!_downloadQueue.any((f) => f['encrypted_name'] == file['encrypted_name'])) {
      setState(() => _downloadQueue.add(file));
      _addLog(false, "대기열 추가: ${file['display_name']}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: () => FocusScope.of(context).unfocus(), child: Scaffold(backgroundColor: const Color(0xFF1E1F22), body: Center(child: Container(width: 800, height: 800, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: const Color(0xFF2B2D31), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15)]), child: Column(children: [Expanded(child: PageView(controller: _pageController, physics: const NeverScrollableScrollPhysics(), children: [_page(true), _page(false)])), const SizedBox(height: 16), _nav()])))));
  }

  Widget _page(bool up) {
    final bool same = (up ? _s1 : _s2).text.isNotEmpty && (up ? _s1 : _s2).text == (up ? _l1 : _l2).text;
    final bool ready = (up ? _t1 : _t2).text.isNotEmpty && (up ? _s1 : _s2).text.isNotEmpty && (up ? _l1 : _l2).text.isNotEmpty && !same && (up ? _selectedFilePaths.isNotEmpty : _downloadQueue.isNotEmpty) && !(up ? _isUp : _isDown);
    
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(up ? 'Upload Bot Settings' : 'Download Bot Settings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      _field(up ? _t1 : _t2, up ? _f1 : _f2, up ? _obs1 : _obs2, (v) => setState(() => up ? _obs1 = v : _obs2 = v)),
      const SizedBox(height: 12),
      _channels(up),
      if (same) const Padding(padding: EdgeInsets.only(top: 4), child: Text('⚠️ 채널 ID는 서로 달라야 합니다.', style: TextStyle(color: Colors.redAccent, fontSize: 12))),
      const SizedBox(height: 24),
      Text(up ? 'File Upload' : 'Download Queue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      if (up) _upPicker() else _queueArea(),
      const SizedBox(height: 20),
      _btn(ready, up ? '업로드 시작' : '선택 폴더로 모두 다운로드', up ? _up : _startQueueDownload, up ? _isUp : _isDown),
      const SizedBox(height: 24),
      Text(up ? 'Logs' : 'Download Logs', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      Expanded(child: _logBox(up ? _sc1 : _sc2, up ? _logs : _dlLogs)),
      if (up ? (_isUp || _prog1 > 0) : (_isDown || _prog2 > 0)) _progress(up ? _prog1 : _prog2, up ? _etr1 : _etr2),
    ]);
  }

  Widget _queueArea() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _dlPicker(),
      const SizedBox(height: 8),
      Container(
        height: 120, // 대기열 높이 고정
        decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: _downloadQueue.isEmpty 
          ? const Center(child: Text("대기열이 비어 있습니다.", style: TextStyle(color: Colors.grey, fontSize: 12)))
          : ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _downloadQueue.length,
              onReorder: (o, n) {
                if (_isDown && (o == 0 || n == 0)) return;
                setState(() { if (n > o) n -= 1; _downloadQueue.insert(n, _downloadQueue.removeAt(o)); });
              },
              itemBuilder: (context, index) {
                final f = _downloadQueue[index]; final isCur = _isDown && index == 0;
                return ListTile(
                  key: ValueKey(f['encrypted_name']),
                  dense: true,
                  leading: Text("${index + 1}.", style: TextStyle(color: isCur ? const Color(0xFF5865F2) : Colors.white70, fontWeight: FontWeight.bold)),
                  title: Text(f['display_name'], style: TextStyle(color: isCur ? const Color(0xFF5865F2) : Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: isCur ? null : () => setState(() => _downloadQueue.removeAt(index))),
                );
              },
            ),
      ),
    ]);
  }

  Widget _field(TextEditingController c, FocusNode f, bool obs, Function(bool) toggle) => Container(height: 50, child: TextField(controller: c, focusNode: f, obscureText: obs, enableInteractiveSelection: true, decoration: InputDecoration(hintText: '봇 토큰 입력', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: const Color(0xFF1E1F22), contentPadding: const EdgeInsets.symmetric(horizontal: 16), suffixIcon: IconButton(icon: Icon(obs ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: () => toggle(!obs)))));

  Widget _channels(bool up) => Row(children: [
    Expanded(child: Container(height: 50, child: TextField(controller: up ? _s1 : _s2, focusNode: up ? _fs1 : _fs2, enableInteractiveSelection: true, decoration: InputDecoration(hintText: '저장 채널 ID', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: const Color(0xFF1E1F22), contentPadding: const EdgeInsets.symmetric(horizontal: 16))))),
    const SizedBox(width: 12),
    Expanded(child: Container(height: 50, child: TextField(controller: up ? _l1 : _l2, focusNode: up ? _fl1 : _fl2, enableInteractiveSelection: true, decoration: InputDecoration(hintText: '리스트 채널 ID', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: const Color(0xFF1E1F22), contentPadding: const EdgeInsets.symmetric(horizontal: 16))))),
    const SizedBox(width: 12),
    ElevatedButton(onPressed: () { TokenService.save(up, (up ? _t1 : _t2).text, (up ? _s1 : _s2).text, (up ? _l1 : _l2).text); _addLog(up, "설정 저장됨"); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4E5058), fixedSize: const Size(80, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('저장', style: TextStyle(fontSize: 13)))
  ]);

  Widget _upPicker() => MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: _isUp ? null : () async { 
    FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true); 
    if (r != null) setState(() { _selectedFilePaths = r.paths.whereType<String>().toList(); _prog1 = 0.0; }); 
  }, child: AnimatedContainer(duration: const Duration(milliseconds: 250), height: 60, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: _selectedFilePaths.isNotEmpty ? const Color(0xFF5865F2) : Colors.white.withOpacity(0.1))), child: Row(children: [Icon(Icons.insert_drive_file, color: _selectedFilePaths.isNotEmpty ? const Color(0xFF5865F2) : Colors.grey, size: 20), const SizedBox(width: 12), Expanded(child: Text(_selectedFilePaths.isEmpty ? '파일들을 선택하세요' : '${_selectedFilePaths.length}개의 파일 선택됨', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))]))));

  Widget _dlPicker() => Row(children: [
    Expanded(child: Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _selId, hint: const Text('파일 선택', style: TextStyle(fontSize: 13)), isExpanded: true, dropdownColor: const Color(0xFF1E1F22), items: _fileList.map((f) => DropdownMenuItem(value: f['encrypted_name'] as String, child: Text('${f['display_name']} (${f['count']} 조각)', style: const TextStyle(fontSize: 12)))).toList(), onChanged: _isDown ? null : (v) => setState(() => _selId = v))))),
    const SizedBox(width: 12),
    ElevatedButton(onPressed: (_isDown || _selId == null) ? null : _addToQueue, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4E5058), fixedSize: const Size(80, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('추가', style: TextStyle(fontSize: 13))),
    const SizedBox(width: 8),
    IconButton(onPressed: (_isUp || _isDown) ? null : () async { await TokenService.save(false, _t2.text, _s2.text, _l2.text); await _ds.fetchFileList(listChannelId: _l2.text, token: _t2.text, onLog: (m) => _addLog(false, m)); await _loadFileList(); }, icon: const Icon(Icons.refresh, size: 20), color: Colors.white)
  ]);

  Widget _btn(bool en, String label, VoidCallback on, bool work) => AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: en ? 1.0 : 0.5, child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: en ? on : null, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(work ? '처리 중...' : label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))));

  Widget _logBox(ScrollController sc, List<String> logs) => Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12)), child: ListView.builder(controller: sc, itemCount: logs.length, itemBuilder: (c, i) => Text(logs[i], style: const TextStyle(color: Color(0xFF23A559), fontFamily: 'monospace', fontSize: 12))));

  Widget _progress(double p, String etr) => Column(children: [const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(etr, style: const TextStyle(color: Colors.white70, fontSize: 11)), Text('${(p * 100).toInt()}%', style: const TextStyle(color: Color(0xFF5865F2), fontSize: 11, fontWeight: FontWeight.bold))]), const SizedBox(height: 6), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: p.clamp(0.0, 1.0), backgroundColor: const Color(0xFF1E1F22), minHeight: 6))]);

  Widget _nav() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    IconButton(icon: Icon(Icons.arrow_back, color: (_curr == 1 && !_isUp && !_isDown) ? Colors.white : Colors.transparent), onPressed: () { if (_curr == 1) { _pageController.animateToPage(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutQuart); setState(() => _curr = 0); } }),
    const Text('@Zandura1212', style: TextStyle(color: Colors.grey, fontSize: 12)),
    IconButton(icon: Icon(Icons.arrow_forward, color: (_curr == 0 && !_isUp && !_isDown) ? Colors.white : Colors.transparent), onPressed: () { if (_curr == 0) { _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutQuart); setState(() => _curr = 1); } }),
  ]);
}
