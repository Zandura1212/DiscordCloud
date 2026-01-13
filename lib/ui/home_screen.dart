import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _storageChannelController = TextEditingController();
  final TextEditingController _listChannelController = TextEditingController();
  
  final TextEditingController _dlTokenController = TextEditingController();
  final TextEditingController _dlStorageChannelController = TextEditingController();
  final TextEditingController _dlListChannelController = TextEditingController();
  
  final FocusNode _tokenFocus = FocusNode();
  final FocusNode _storageFocus = FocusNode();
  final FocusNode _listFocus = FocusNode();
  final FocusNode _dlTokenFocus = FocusNode();
  final FocusNode _dlStorageFocus = FocusNode();
  final FocusNode _dlListFocus = FocusNode();
  
  final ScrollController _logScrollController = ScrollController();
  final ScrollController _dlLogScrollController = ScrollController();
  final DiscordService _discordService = DiscordService();
  
  final List<String> _logs = [];
  final List<String> _dlLogs = [];
  List<Map<String, dynamic>> _fileList = [];
  Map<String, dynamic>? _selectedFile;
  
  String? _selectedFilePath;
  int _currentPage = 0;
  
  bool _isObscured = true;
  bool _isDlObscured = true;
  
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  String _remainingTime = "";

  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String _dlRemainingTime = "";

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initData();
    _loadFileList();
    _addLog("애플리케이션이 시작되었습니다.");
    
    _tokenController.addListener(_updateState);
    _storageChannelController.addListener(_updateState);
    _listChannelController.addListener(_updateState);
    _dlTokenController.addListener(_updateState);
    _dlStorageChannelController.addListener(_updateState);
    _dlListChannelController.addListener(_updateState);
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tokenFocus.dispose();
    _storageFocus.dispose();
    _listFocus.dispose();
    _dlTokenFocus.dispose();
    _dlStorageFocus.dispose();
    _dlListFocus.dispose();
    _tokenController.dispose();
    _storageChannelController.dispose();
    _listChannelController.dispose();
    _dlTokenController.dispose();
    _dlStorageChannelController.dispose();
    _dlListChannelController.dispose();
    _pageController.dispose();
    _logScrollController.dispose();
    _dlLogScrollController.dispose();
    _discordService.logout();
    super.dispose();
  }

  Future<void> _cleanUpFolders() async {
    try {
      String? appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final customDirPath = '$appData\\DiscordCloud';
        final directory = Directory(customDirPath);
        if (await directory.exists()) {
          final List<FileSystemEntity> entities = await directory.list().toList();
          for (var entity in entities) {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else if (entity is File && !entity.path.endsWith('config.json') && !entity.path.endsWith('list.json')) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint("폴더 정리 중 에러: $e");
    }
  }

  @override
  void onWindowClose() async {
    await _cleanUpFolders();
    await windowManager.destroy();
  }

  Future<void> _initData() async {
    final data = await TokenService.loadAllData();
    if (mounted) {
      setState(() {
        _tokenController.text = data['token']!;
        _storageChannelController.text = data['storage_channel']!;
        _listChannelController.text = data['list_channel']!;
        _dlTokenController.text = data['dl_token']!;
        _dlStorageChannelController.text = data['dl_storage_channel']!;
        _dlListChannelController.text = data['dl_list_channel']!;
      });
    }
  }

  Future<void> _loadFileList() async {
    try {
      final String? appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final listFile = File('$appData\\DiscordCloud\\list.json');
        if (await listFile.exists()) {
          final String content = await listFile.readAsString();
          if (content.isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              setState(() {
                final List<Map<String, dynamic>> rawList = List<Map<String, dynamic>>.from(decoded);
                final Map<String, Map<String, dynamic>> uniqueMap = {};
                for (var item in rawList) {
                  // 암호화된 이름을 고유 키로 사용하여 중복 제거
                  uniqueMap[item['encrypted_name']] = item;
                }
                _fileList = uniqueMap.values.toList();
                
                // 에러 방지: 선택된 파일이 리스트에서 사라졌다면 null 처리
                if (_selectedFile != null) {
                  bool stillExists = _fileList.any((f) => 
                    f['encrypted_name'] == _selectedFile!['encrypted_name']);
                  if (!stillExists) _selectedFile = null;
                }
              });
            }
          }
        }
      }
    } catch (e) {
      _addDlLog("리스트 로드 오류: $e");
    }
  }

  void _addLog(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    if (mounted) setState(() => _logs.add("[$time] $message"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(_logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  void _addDlLog(String message) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    if (mounted) setState(() => _dlLogs.add("[$time] $message"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dlLogScrollController.hasClients) {
        _dlLogScrollController.animateTo(_dlLogScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _handleSaveUploadConfig() async {
    await TokenService.saveAllData(
      token: _tokenController.text,
      storageChannel: _storageChannelController.text,
      listChannel: _listChannelController.text,
    );
    _addLog("업로드 설정이 저장되었습니다.");
  }

  Future<void> _handleSaveDownloadConfig() async {
    await TokenService.saveDownloadData(
      token: _dlTokenController.text,
      storageChannel: _dlStorageChannelController.text,
      listChannel: _dlListChannelController.text,
    );
    _addDlLog("다운로드 설정이 저장되었습니다.");
  }

  Future<void> _handleLoadDiscordList() async {
    if (_isDownloading) return;
    
    setState(() => _isDownloading = true);
    _addDlLog("디스코드에서 파일 리스트를 불러오는 중...");
    
    try {
      await _discordService.fetchFileList(
        listChannelId: _dlListChannelController.text,
        token: _dlTokenController.text,
        onLog: _addDlLog,
      );
      await _loadFileList(); 
      _addDlLog("리스트 동기화 완료.");
    } catch (e) {
      _addDlLog("리스트 불러오기 에러: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _handlePickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && mounted) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _uploadProgress = 0.0;
        });
        _addLog("파일 선택됨: ${_selectedFilePath?.split(Platform.pathSeparator).last}");
      }
    } catch (e) {
      _addLog("파일 선택 에러: $e");
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFilePath == null || _isUploading) return;
    
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _remainingTime = "준비 중...";
    });

    try {
      String? appData = Platform.environment['APPDATA'];
      if (appData == null) throw Exception("APPDATA 경로를 찾을 수 없습니다.");
      
      final customDirPath = '$appData\\DiscordCloud';
      final originalFileName = _selectedFilePath!.split(Platform.pathSeparator).last;
      final fileFolder = originalFileName.replaceAll('.', '_');
      final destinationFolderPath = '$customDirPath\\$fileFolder';
      final uploadTime = DateTime.now().toIso8601String();

      final configFilePath = '$customDirPath\\config.json';
      final configFile = File(configFilePath);
      
      List<dynamic> history = [{
        'discord_token': _tokenController.text,
        'storage_channel_id': _storageChannelController.text,
        'list_channel_id': _listChannelController.text,
        'folder_location': destinationFolderPath,
        'original_file_name': originalFileName,
        'upload_at': uploadTime,
        'is_streaming': true,
      }];

      if (!await Directory(customDirPath).exists()) {
        await Directory(customDirPath).create(recursive: true);
      }
      await configFile.writeAsString(jsonEncode(history));

      _addLog("로컬 파일 분할 및 암호화 시작...");
      await FileService.encryptAndSplitFile(
        sourceFilePath: _selectedFilePath!,
        destinationFolderPath: destinationFolderPath,
        token: _tokenController.text,
        onProgress: (progress, remaining) {
          if (mounted) setState(() {
            _uploadProgress = progress * 0.3;
            _remainingTime = "로컬 처리 중 ($remaining)";
          });
        },
        onLog: _addLog,
      );

      _addLog("디스코드 봇 로그인 중...");
      await _discordService.login(_tokenController.text);
      
      _addLog("디스코드 채널로 업로드 및 list.json 작성...");
      await _discordService.uploadChunks(
        storageChannelId: _storageChannelController.text,
        listChannelId: _listChannelController.text,
        folderPath: destinationFolderPath,
        originalFileName: originalFileName,
        token: _tokenController.text,
        uploadTime: uploadTime,
        onLog: _addLog,
        onProgress: (progress) {
          if (mounted) setState(() {
            _uploadProgress = 0.3 + (progress * 0.7);
            _remainingTime = "디스코드 업로드 중...";
          });
        },
      );
      
      _addLog("업로드 완료, 임시 폴더를 삭제합니다.");
      await _cleanUpFolders();
      await _loadFileList();
      
      _addLog("모든 과정이 완료되었습니다.");
    } catch (e) {
      _addLog("치명적 에러 발생: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_selectedFile == null || _isDownloading) return;
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _dlRemainingTime = "준비 중...";
    });

    _addDlLog("다운로드 시작: ${_selectedFile!['display_name'] ?? _selectedFile!['name']}");
    await Future.delayed(const Duration(seconds: 2));
    _addDlLog("다운로드 기능은 현재 개발 중입니다.");
    
    setState(() => _isDownloading = false);
  }

  void _navigateToPage(int index) {
    if (_currentPage == index || _isUploading || _isDownloading) return;
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutQuart);
    setState(() => _currentPage = index);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1F22),
        body: Center(
          child: Container(
            width: 800, height: 800, padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: const Color(0xFF2B2D31), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, spreadRadius: 2)]),
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_buildUploadPage(), _buildDownloadPage()],
                  ),
                ),
                const SizedBox(height: 20),
                _buildNavigationButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    bool isWorking = _isUploading || _isDownloading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: (_currentPage == 1 && !isWorking) ? 1.0 : 0.0,
          child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 36), onPressed: (_currentPage == 1 && !isWorking) ? () => _navigateToPage(0) : null),
        ),
        const Text('@Zandura1212', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w300)),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: (_currentPage == 0 && !isWorking) ? 1.0 : 0.0,
          child: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 36), onPressed: (_currentPage == 0 && !isWorking) ? () => _navigateToPage(1) : null),
        ),
      ],
    );
  }

  Widget _buildUploadPage() {
    final bool isChannelsSame = _storageChannelController.text.isNotEmpty && 
                               _listChannelController.text.isNotEmpty &&
                               _storageChannelController.text == _listChannelController.text;

    final bool isUploadEnabled = _tokenController.text.isNotEmpty && 
                                 _storageChannelController.text.isNotEmpty &&
                                 _listChannelController.text.isNotEmpty &&
                                 !isChannelsSame &&
                                 _selectedFilePath != null && !_isUploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upload Bot Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 12),
        _buildTokenField(_tokenController, _tokenFocus, _isObscured, (val) => setState(() => _isObscured = val)),
        const SizedBox(height: 16),
        _buildChannelInputs(_storageChannelController, _storageFocus, _listChannelController, _listFocus, _handleSaveUploadConfig, isChannelsSame, _isUploading),
        const SizedBox(height: 32),
        const Text('File Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 12),
        _buildFilePicker(),
        const SizedBox(height: 32),
        _buildActionButton(isUploadEnabled, '업로드', _handleUpload, _isUploading),
        const SizedBox(height: 40),
        const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        const SizedBox(height: 12),
        _buildLogWindow(_logScrollController, _logs),
        if (_isUploading || _uploadProgress > 0) _buildProgressBar(_uploadProgress, _remainingTime),
      ],
    );
  }

  Widget _buildDownloadPage() {
    final bool isChannelsSame = _dlStorageChannelController.text.isNotEmpty && 
                               _dlListChannelController.text.isNotEmpty &&
                               _dlStorageChannelController.text == _dlListChannelController.text;

    final bool isConfigFilled = _dlTokenController.text.isNotEmpty && 
                                _dlStorageChannelController.text.isNotEmpty &&
                                _dlListChannelController.text.isNotEmpty &&
                                !isChannelsSame;

    final bool isDownloadEnabled = isConfigFilled && _selectedFile != null && !_isDownloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Download Bot Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 12),
        _buildTokenField(_dlTokenController, _dlTokenFocus, _isDlObscured, (val) => setState(() => _isDlObscured = val)),
        const SizedBox(height: 16),
        _buildChannelInputs(_dlStorageChannelController, _dlStorageFocus, _dlListChannelController, _dlListFocus, _handleSaveDownloadConfig, isChannelsSame, _isDownloading),
        const SizedBox(height: 32),
        const Text('File List', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 12),
        _buildFileListWithLoad(isConfigFilled),
        const SizedBox(height: 32),
        _buildActionButton(isDownloadEnabled, '다운로드', _handleDownload, _isDownloading),
        const SizedBox(height: 40),
        const Text('Download Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        const SizedBox(height: 12),
        _buildLogWindow(_dlLogScrollController, _dlLogs),
        if (_isDownloading || _downloadProgress > 0) _buildProgressBar(_downloadProgress, _dlRemainingTime),
      ],
    );
  }

  Widget _buildFileListWithLoad(bool isEnabled) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1F22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, dynamic>>(
                value: _selectedFile,
                hint: const Text('파일을 선택하세요', style: TextStyle(color: Colors.white54, fontSize: 14)),
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1F22),
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                items: _fileList.map((file) {
                  final String name = file['display_name'] ?? file['name'] ?? 'Unknown File';
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: file,
                    child: Text(
                      '$name (${file['count']} chunks)',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (_isUploading || _isDownloading) ? null : (value) {
                  setState(() {
                    _selectedFile = value;
                    _downloadProgress = 0.0;
                  });
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: (isEnabled && !_isUploading && !_isDownloading) ? _handleLoadDiscordList : null,
          icon: const Icon(Icons.refresh),
          label: const Text('불러오기'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4E5058),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildTokenField(TextEditingController controller, FocusNode node, bool obscured, Function(bool) onToggle) {
    return TextField(
      controller: controller,
      focusNode: node,
      enabled: !_isUploading && !_isDownloading,
      obscureText: obscured,
      enableInteractiveSelection: true,
      decoration: InputDecoration(
        hintText: '디스코드 봇 토큰을 입력하세요', 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), 
        fillColor: const Color(0xFF1E1F22), 
        filled: true,
        suffixIcon: IconButton(
          icon: Icon(obscured ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
          onPressed: () => onToggle(!obscured),
        ),
      )
    );
  }

  Widget _buildChannelInputs(TextEditingController c1, FocusNode f1, TextEditingController c2, FocusNode f2, VoidCallback onSave, bool isSame, bool isWorking) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: c1, focusNode: f1, enabled: !isWorking,
                enableInteractiveSelection: true,
                decoration: InputDecoration(
                  hintText: '저장 채널 ID',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  fillColor: const Color(0xFF1E1F22), filled: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: c2, focusNode: f2, enabled: !isWorking,
                enableInteractiveSelection: true,
                decoration: InputDecoration(
                  hintText: '리스트 채널 ID',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  fillColor: const Color(0xFF1E1F22), filled: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: isWorking ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4E5058),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('저장'),
            ),
          ],
        ),
        if (isSame)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '⚠️ 저장 채널과 리스트 채널 ID는 서로 달라야 합니다.',
              style: TextStyle(color: Colors.redAccent.shade200, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildFilePicker() {
    bool isWorking = _isUploading || _isDownloading;
    return MouseRegion(
      cursor: isWorking ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isWorking ? null : _handlePickFile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250), height: 64, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: _selectedFilePath != null ? const Color(0xFF5865F2) : Colors.grey.withOpacity(0.2), width: _selectedFilePath != null ? 2 : 1)),
          child: Row(children: [Icon(_selectedFilePath != null ? Icons.check_circle : Icons.insert_drive_file, size: 20, color: _selectedFilePath != null ? const Color(0xFF5865F2) : Colors.grey), const SizedBox(width: 12), Expanded(child: Text(_selectedFilePath?.split(Platform.pathSeparator).last ?? '파일을 선택하세요', style: TextStyle(color: _selectedFilePath != null ? Colors.white : Colors.white54, fontSize: 14), overflow: TextOverflow.ellipsis))]),
        ),
      ),
    );
  }

  Widget _buildLogWindow(ScrollController controller, List<String> logs) {
    return Expanded(
      child: Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))), child: ListView.builder(controller: controller, itemCount: logs.length, itemBuilder: (context, index) => Text(logs[index], style: const TextStyle(color: Color(0xFF23A559), fontFamily: 'monospace', fontSize: 13)))),
    );
  }

  Widget _buildProgressBar(double progress, String remainingTime) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('작업 상태: $remainingTime', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF5865F2), fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFF1E1F22), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5865F2)), minHeight: 8)),
      ],
    );
  }

  Widget _buildActionButton(bool enabled, String label, VoidCallback onPressed, bool isWorking) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200), opacity: enabled ? 1.0 : 0.5,
      child: SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: enabled ? onPressed : null, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2), foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFF5865F2).withOpacity(0.3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(isWorking ? '처리 중...' : label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
    );
  }
}
