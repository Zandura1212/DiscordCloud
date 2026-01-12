import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:io';
import 'dart:typed_data';

class MaskedTokenController extends TextEditingController {
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (text.isEmpty) return TextSpan(text: '', style: style);
    String display = text.length <= 2 ? text : text[0] + '*' * (text.length - 2) + text[text.length - 1];
    return TextSpan(text: display, style: style);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const WindowOptions windowOptions = WindowOptions(
    size: Size(900, 900),
    center: true,
    backgroundColor: Colors.black,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: "Discord Cloud",
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle("Discord Cloud");
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Discord Cloud',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5865F2), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final PageController _pageController = PageController();
  final TextEditingController _tokenController = MaskedTokenController();
  final ScrollController _logScrollController = ScrollController();
  final List<String> _logs = [];
  String? _selectedFilePath;
  int _currentPage = 0;
  
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  String _remainingTime = "";

  @override
  void initState() {
    super.initState();
    _loadToken();
    _addLog("애플리케이션이 시작되었습니다.");
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  // 스트리밍 방식으로 대용량 파일을 처리하는 함수
  Future<void> _encryptAndSplitFile(String sourceFilePath, String destinationFolderPath, String token) async {
    final stopwatch = Stopwatch()..start();
    final file = File(sourceFilePath);
    final int totalFileSize = await file.length();
    
    final keyBytes = sha256.convert(utf8.encode(token)).bytes;
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final dir = Directory(destinationFolderPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    // 파일을 조각내어 읽기 위한 열기
    final raf = await file.open();
    
    // 조각당 원본 크기 (약 5MB를 읽으면 압축/암호화/Base64 후 약 7-9MB가 됨)
    const int readChunkSize = 5 * 1024 * 1024; 
    int bytesProcessed = 0;
    int chunkIdx = 0;

    _addLog("대용량 스트리밍 처리 시작...");

    try {
      while (bytesProcessed < totalFileSize) {
        // 1. 일정량만 읽기 (메모리 보호)
        final Uint8List buffer = await raf.read(readChunkSize);
        if (buffer.isEmpty) break;

        // 2. 해당 조각 압축
        final compressed = zlib.encode(buffer);
        
        // 3. 해당 조각 암호화
        final iv = encrypt.IV.fromSecureRandom(16);
        final encrypted = encrypter.encryptBytes(compressed, iv: iv);
        
        // 4. 즉시 파일로 저장 (iv:data 형식)
        final chunkFile = File('$destinationFolderPath\\$chunkIdx.txt');
        await chunkFile.writeAsString("${iv.base64}:${encrypted.base64}");
        
        bytesProcessed += buffer.length;
        chunkIdx++;
        
        // 진행률 및 예상 시간 업데이트
        if (mounted) {
          setState(() {
            _uploadProgress = bytesProcessed / totalFileSize;
            if (_uploadProgress > 0) {
              final elapsed = stopwatch.elapsed;
              final estimatedTotal = elapsed.inMilliseconds / _uploadProgress;
              final remaining = Duration(milliseconds: (estimatedTotal - elapsed.inMilliseconds).toInt());
              _remainingTime = _formatDuration(remaining);
            }
          });
        }
        
        // 이벤트 루프에 양보하여 UI 응답성 유지
        await Future.delayed(Duration.zero);
      }
    } finally {
      await raf.close();
    }
    
    stopwatch.stop();
    _addLog("총 $chunkIdx개의 분할 파일 생성 완료. (소요 시간: ${_formatDuration(stopwatch.elapsed)})");
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _tokenController.text = prefs.getString('discord_token') ?? '');
  }

  Future<void> _saveToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('discord_token', _tokenController.text);
    _addLog("디스코드 토큰이 저장되었습니다.");
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && mounted) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _uploadProgress = 0.0;
        });
        final winPath = result.files.single.path?.replaceAll('/', '\\');
        _addLog("파일 선택됨: $winPath");
      }
    } catch (e) {
      _addLog("파일 선택 에러: $e");
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFilePath == null || _isUploading) return;
    setState(() { _isUploading = true; _uploadProgress = 0.0; _remainingTime = "계산 중..."; });

    try {
      String? appData = Platform.environment['APPDATA'];
      final customDirPath = '$appData\\DiscordCloud';
      final originalFileName = _selectedFilePath!.split(Platform.pathSeparator).last;
      final fileFolder = originalFileName.replaceAll('.', '_');
      final destinationFolderPath = '$customDirPath\\$fileFolder';

      final configFilePath = '$customDirPath\\config.json';
      final configFile = File(configFilePath);

      List<dynamic> history = [];
      if (await configFile.exists()) {
        try {
          String content = await configFile.readAsString();
          history = jsonDecode(content);
        } catch (e) { history = []; }
      }

      Map<String, dynamic> uploadData = {
        'discord_token': _tokenController.text,
        'folder_location': destinationFolderPath,
        'original_file_name': originalFileName,
        'upload_at': DateTime.now().toIso8601String(),
        'is_streaming': true,
      };

      history.add(uploadData);
      await configFile.writeAsString(jsonEncode(history));
      await _encryptAndSplitFile(_selectedFilePath!, destinationFolderPath, _tokenController.text);
    } catch (e) {
      _addLog("에러 발생: $e");
    } finally {
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  void _navigateToPage(int index) {
    if (_currentPage == index || _isUploading) return;
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutQuart);
    setState(() => _currentPage = index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tokenController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: (_currentPage == 1 && !_isUploading) ? 1.0 : 0.0,
                    child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 36), onPressed: (_currentPage == 1 && !_isUploading) ? () => _navigateToPage(0) : null),
                  ),
                  const Text('@Zandura1212', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w300)),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: (_currentPage == 0 && !_isUploading) ? 1.0 : 0.0,
                    child: IconButton(icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 36), onPressed: (_currentPage == 0 && !_isUploading) ? () => _navigateToPage(1) : null),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPage() {
    return ListenableBuilder(
      listenable: _tokenController,
      builder: (context, child) {
        final bool isUploadEnabled = _tokenController.text.isNotEmpty && _selectedFilePath != null && !_isUploading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Token', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _tokenController, enabled: !_isUploading, decoration: InputDecoration(hintText: '디스코드 토큰을 입력하세요', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), fillColor: const Color(0xFF1E1F22), filled: true))),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _isUploading ? null : _saveToken, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4E5058), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('저장')),
              ],
            ),
            const SizedBox(height: 32),
            const Text('File Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
            const SizedBox(height: 12),
            MouseRegion(
              cursor: _isUploading ? SystemMouseCursors.basic : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _isUploading ? null : _pickFile,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250), height: 64, padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: _selectedFilePath != null ? const Color(0xFF5865F2) : Colors.grey.withOpacity(0.2), width: _selectedFilePath != null ? 2 : 1)),
                  child: Row(children: [Icon(_selectedFilePath != null ? Icons.check_circle : Icons.insert_drive_file, size: 20, color: _selectedFilePath != null ? const Color(0xFF5865F2) : Colors.grey), const SizedBox(width: 12), Expanded(child: Text(_selectedFilePath?.split(Platform.pathSeparator).last ?? '파일을 선택하세요', style: TextStyle(color: _selectedFilePath != null ? Colors.white : Colors.white54, fontSize: 14), overflow: TextOverflow.ellipsis))]),
                ),
              ),
            ),
            const SizedBox(height: 32),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200), opacity: isUploadEnabled ? 1.0 : 0.5,
              child: SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: isUploadEnabled ? _handleUpload : null, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5865F2), foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFF5865F2).withOpacity(0.3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(_isUploading ? '처리 중...' : '업로드', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
            ),
            const SizedBox(height: 40),
            const Text('Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            const SizedBox(height: 12),
            Expanded(
              child: Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E1F22), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))), child: ListView.builder(controller: _logScrollController, itemCount: _logs.length, itemBuilder: (context, index) => Text(_logs[index], style: const TextStyle(color: Color(0xFF23A559), fontFamily: 'monospace', fontSize: 13)))),
            ),
            if (_isUploading || _uploadProgress > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('남은 시간: $_remainingTime', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('${(_uploadProgress * 100).toInt()}%', style: const TextStyle(color: Color(0xFF5865F2), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _uploadProgress, backgroundColor: const Color(0xFF1E1F22), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5865F2)), minHeight: 8)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDownloadPage() => const Center(child: Opacity(opacity: 0.5, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.construction, size: 64), SizedBox(height: 16), Text('다운로드 기능 구현 예정입니다')])));
}
