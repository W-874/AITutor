import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

void main() {
  runApp(const NotebookLMApp());
}

class NotebookLMApp extends StatelessWidget {
  const NotebookLMApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotebookLM Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF131314), // 涓昏儗鏅壊
        primaryColor: const Color(0xFFA8C7FA), // Google 钃濊壊绯?
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA8C7FA),
          surface: Color(0xFF1E1F20), // 闈㈡澘鑳屾櫙鑹?
        ),
        fontFamily: 'Microsoft YaHei', // Windows 榛樿鍙嬪ソ瀛椾綋
      ),
      home: const NotebookHome(),
    );
  }
}

class NotebookHome extends StatefulWidget {
  const NotebookHome({Key? key}) : super(key: key);

  @override
  State<NotebookHome> createState() => _NotebookHomeState();
}

enum CenterViewMode { chat, document, learning, quiz, studioGraph, studioText }

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> references;
  ChatMessage({required this.text, required this.isUser, this.references = const []});
}

// 鏂板绗旇鏈暟鎹ā鍨?
class Notebook {
  final String id;
  String title;
  Notebook({required this.id, required this.title});
}

class _NotebookHomeState extends State<NotebookHome> {
  // 鏂板 Scaffold 鍏ㄥ眬 Key锛岀敤浜庢帶鍒舵娊灞夊脊鍑?
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  
  // 鏂板寮傛璇锋眰鐨勭姸鎬侀攣
  bool _isThinking = false; // 鎺у埗鑱婂ぉ绛夊緟鐘舵€?
  bool _isUploading = false; // 鎺у埗鏂囦欢涓婁紶鐘舵€?  bool _isGeneratingStudio = false; // 鎺у埗 Studio 闈㈡澘鐢熸垚鐘舵€?  String? _activeStudioTool; // 璁板綍褰撳墠姝ｅ湪鐢熸垚鍝釜宸ュ叿
  CenterViewMode _centerMode = CenterViewMode.chat;
  String _qaMode = 'mix';
  bool _includeReferences = false;

  List<Map<String, dynamic>> _documents = [];
  Map<String, dynamic>? _selectedDocument;
  List<Map<String, dynamic>> _documentKnowledgeNodes = [];
  bool _isLoadingDocuments = false;
  bool _isLoadingDocumentDetail = false;
  int _documentsPage = 1;
  int _documentsTotal = 0;
  bool _documentsHasNext = false;
  bool _documentsHasPrev = false;
  String? _documentsStatusFilter;
  Map<String, int> _statusCounts = {};
  Map<String, dynamic>? _pipelineStatus;

  List<Map<String, dynamic>> _skillNodes = [];
  bool _isLoadingSkillNodes = false;
  String? _learningNodeName;
  String? _learningContent;
  Map<String, dynamic>? _studioGraphPayload;
  String? _studioGraphLabel;
  String? _studioTextTitle;
  String? _studioTextType;
  String? _studioTextTopic;
  String? _studioTextContent;
  final GlobalKey _graphExportKey = GlobalKey();
  bool _isExportingGraph = false;

  bool _isGeneratingQuiz = false;
  bool _isSubmittingQuiz = false;
  int _quizQuestionCount = 5;
  String? _quizNodeId;
  String? _quizNodeName;
  List<Map<String, dynamic>> _quizQuestions = [];
  Map<String, dynamic> _quizAnswers = {};
  Map<String, dynamic>? _quizResult;

  // 鏂板绗旇鏈垪琛ㄧ浉鍏崇姸鎬?
  List<Notebook> _notebooks = [];
  Notebook? _currentNotebook;
  bool _isLoadingNotebooks = false; // 鎺у埗鍒楄〃鎷夊彇绛夊緟鐘舵€?
  bool _isCreatingNotebook = false; // 鎺у埗鏂板缓绗旇鏈瓑寰呯姸鎬?  final String _apiBaseUrl = _resolveApiBaseUrl();

  static String _resolveApiBaseUrl() {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return defined;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchDocuments(resetPage: true),
      _refreshSkillNodes(),
      _refreshPipelineStatus(silent: true),
    ]);
  }

  Future<void> _refreshPipelineStatus({bool silent = false}) async {
    try {
      final result = await _apiGet('/api/documents/pipeline-status');
      if (!mounted) return;
      setState(() {
        _pipelineStatus = result;
      });
    } catch (error) {
      if (!silent) {
        await _showError(error);
      }
    }
  }

  String _stringOf(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  double _doubleOf(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _intOf(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  String _shortFileName(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');
    if (!normalized.contains('/')) return normalized;
    return normalized.split('/').last;
  }

  String _statusText(String status) {
    switch (status.toLowerCase()) {
      case 'processed':
        return '宸插鐞?;
      case 'processing':
        return '澶勭悊涓?;
      case 'pending':
        return '绛夊緟涓?;
      case 'failed':
        return '澶辫触';
      case 'preprocessed':
        return '棰勫鐞?;
      case 'completed':
        return '宸插畬鎴?;
      case 'learning':
        return '瀛︿範涓?;
      case 'available':
        return '鍙涔?;
      case 'locked':
        return '鏈В閿?;
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'processed':
      case 'completed':
        return Colors.greenAccent;
      case 'processing':
      case 'learning':
        return Colors.orangeAccent;
      case 'failed':
        return Colors.redAccent;
      case 'available':
        return Colors.lightBlueAccent;
      case 'locked':
        return Colors.grey;
      default:
        return Colors.white60;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'processed':
      case 'completed':
        return Icons.check_circle;
      case 'processing':
      case 'learning':
        return Icons.autorenew;
      case 'failed':
        return Icons.error;
      case 'pending':
        return Icons.schedule;
      case 'preprocessed':
        return Icons.tune;
      case 'available':
        return Icons.play_circle;
      case 'locked':
        return Icons.lock;
      default:
        return Icons.info;
    }
  }

  Future<Map<String, dynamic>> _apiGet(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_apiBaseUrl$path').replace(queryParameters: query);
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET $path 澶辫触: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }

  Future<List<dynamic>> _apiGetList(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_apiBaseUrl$path').replace(queryParameters: query);
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GET $path 澶辫触: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      return decoded['data'] as List;
    }
    return [];
  }

  Future<Map<String, dynamic>> _apiPost(String path, {Object? body}) async {
    final uri = Uri.parse('$_apiBaseUrl$path');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('POST $path 澶辫触: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> _apiDelete(String path) async {
    final uri = Uri.parse('$_apiBaseUrl$path');
    final response = await http.delete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('DELETE $path 澶辫触: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> _uploadSingleFile(
    String filename,
    List<int> bytes,
    String? mimeType,
  ) async {
    final uri = Uri.parse('$_apiBaseUrl/api/documents/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('涓婁紶 $filename 澶辫触: ${response.statusCode} $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> _fetchDocuments({bool resetPage = false}) async {
    if (resetPage) {
      _documentsPage = 1;
    }
    setState(() {
      _isLoadingDocuments = true;
      _isLoadingNotebooks = true;
    });
    try {
      final result = await _apiPost('/api/documents/paginated', body: {
        'page': _documentsPage,
        'page_size': 12,
        'status_filter': _documentsStatusFilter,
        'sort_field': 'updated_at',
        'sort_direction': 'desc',
      });
      final docs = (result['documents'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final pagination = Map<String, dynamic>.from(result['pagination'] as Map? ?? {});
      final countsRaw = Map<String, dynamic>.from(result['status_counts'] as Map? ?? {});
      final notebooks = docs.map((doc) {
        final id = _stringOf(doc['id'], fallback: DateTime.now().microsecondsSinceEpoch.toString());
        final title = _shortFileName(_stringOf(doc['file_path'], fallback: id));
        return Notebook(id: id, title: title);
      }).toList();

      if (!mounted) return;
      setState(() {
        _documents = docs;
        _documentsTotal = _intOf(pagination['total_count']);
        _documentsHasNext = pagination['has_next'] == true;
        _documentsHasPrev = pagination['has_prev'] == true;
        _statusCounts = countsRaw.map((k, v) => MapEntry(k, _intOf(v)));
        _notebooks = notebooks;
        if (_selectedDocument != null) {
          final selectedId = _stringOf(_selectedDocument!['id']);
          final refreshed = _documents.firstWhere(
            (d) => _stringOf(d['id']) == selectedId,
            orElse: () => {},
          );
          _selectedDocument = refreshed.isEmpty ? null : refreshed;
        }
        if (_selectedDocument == null && _documents.isNotEmpty) {
          _selectedDocument = _documents.first;
        }
        _currentNotebook = _selectedDocument == null
            ? null
            : Notebook(
                id: _stringOf(_selectedDocument!['id']),
                title: _shortFileName(_stringOf(_selectedDocument!['file_path'], fallback: 'Untitled')),
              );
        _isLoadingDocuments = false;
        _isLoadingNotebooks = false;
      });
      await _refreshPipelineStatus(silent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingDocuments = false;
        _isLoadingNotebooks = false;
      });
      await _showError(error);
    }
  }

  // 鏂板缓绗旇鏈?(棰勭暀鍚庣鎺ュ彛)
  Future<void> _createNewNotebook() async {
    if (_isCreatingNotebook) return;
    setState(() => _isCreatingNotebook = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _isCreatingNotebook = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('鍚庣鏆傛棤 Notebook 瀹炰綋锛岃閫氳繃鈥滄坊鍔犳潵婧愨€濆垱寤哄唴瀹?)),
    );
  }

  Future<void> _loadDocumentDetail(Map<String, dynamic> doc) async {
    final docId = _stringOf(doc['id']);
    if (docId.isEmpty) return;
    setState(() {
      _selectedDocument = doc;
      _currentNotebook = Notebook(
        id: docId,
        title: _shortFileName(_stringOf(doc['file_path'], fallback: docId)),
      );
      _isLoadingDocumentDetail = true;
      _centerMode = CenterViewMode.document;
    });

    try {
      final detail = await _apiGet('/api/documents/track/$docId');
      final docs = detail['documents'];
      if (docs is List && docs.isNotEmpty && docs.first is Map) {
        _selectedDocument = Map<String, dynamic>.from(docs.first as Map);
      }
    } catch (_) {}

    try {
      final knowledge = await _apiGet('/api/documents/$docId/knowledge');
      final nodes = (knowledge['knowledge_nodes'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      if (!mounted) return;
      setState(() {
        _documentKnowledgeNodes = nodes;
        _isLoadingDocumentDetail = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingDocumentDetail = false);
      await _showError(error);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> doc) async {
    final docId = _stringOf(doc['id']);
    if (docId.isEmpty) return;
    try {
      await _apiDelete('/api/documents/$docId');
      if (_selectedDocument != null && _stringOf(_selectedDocument!['id']) == docId) {
        setState(() {
          _selectedDocument = null;
          _documentKnowledgeNodes = [];
          if (_centerMode == CenterViewMode.document) {
            _centerMode = CenterViewMode.chat;
          }
        });
      }
      await _fetchDocuments();
      await _refreshSkillNodes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('鏂囨。宸插垹闄?)),
      );
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _refreshSkillNodes() async {
    setState(() => _isLoadingSkillNodes = true);
    try {
      final result = await _apiGetList('/api/skill-tree/nodes');
      final nodes = result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _skillNodes = nodes;
        _isLoadingSkillNodes = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingSkillNodes = false);
      await _showError(error);
    }
  }

  Future<void> _startLearning(Map<String, dynamic> node) async {
    final nodeId = _stringOf(node['id']);
    if (nodeId.isEmpty) return;
    try {
      final result = await _apiGet('/api/skill-tree/nodes/$nodeId/learning-content');
      if (!mounted) return;
      setState(() {
        _learningNodeName = _stringOf(node['name'], fallback: '瀛︿範鍐呭');
        _learningContent = _stringOf(result['content'], fallback: '鏈繑鍥炲涔犲唴瀹?);
        _centerMode = CenterViewMode.learning;
      });
      await _refreshSkillNodes();
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _completeLearning(Map<String, dynamic> node) async {
    final nodeId = _stringOf(node['id']);
    if (nodeId.isEmpty) return;
    try {
      await _apiPost('/api/skill-tree/nodes/$nodeId/complete');
      await _refreshSkillNodes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('宸叉爣璁颁负瀹屾垚')),
      );
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _generateQuizForNode(Map<String, dynamic> node) async {
    final nodeId = _stringOf(node['id']);
    if (nodeId.isEmpty) return;
    setState(() {
      _isGeneratingQuiz = true;
      _quizNodeId = nodeId;
    });
    try {
      final result = await _apiGet(
        '/api/quiz/generate/$nodeId',
        query: {'num_questions': '$_quizQuestionCount'},
      );
      final questions = (result['questions'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _quizNodeId = nodeId;
        _quizNodeName = _stringOf(result['node_name'], fallback: _stringOf(node['name']));
        _quizQuestions = questions;
        _quizAnswers = {};
        _quizResult = null;
        _centerMode = CenterViewMode.quiz;
        _isGeneratingQuiz = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isGeneratingQuiz = false);
      await _showError(error);
    }
  }

  Future<void> _submitQuiz() async {
    if (_quizNodeId == null || _quizQuestions.isEmpty) return;
    if (_quizAnswers.length < _quizQuestions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('璇峰厛鍥炵瓟鎵€鏈夐鐩?)),
      );
      return;
    }
    setState(() => _isSubmittingQuiz = true);
    try {
      final result = await _apiPost('/api/quiz/submit/${_quizNodeId!}', body: {
        'questions': _quizQuestions,
        'user_answers': _quizAnswers,
      });
      if (!mounted) return;
      setState(() {
        _quizResult = Map<String, dynamic>.from(result);
        _isSubmittingQuiz = false;
      });
      await _refreshSkillNodes();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmittingQuiz = false);
      await _showError(error);
    }
  }

  // 鍒囨崲閫変腑绗旇鏈?(棰勭暀鍚庣鎺ュ彛)
  Future<void> _switchNotebook(Notebook nb) async {
    final doc = _documents.firstWhere(
      (d) => _stringOf(d['id']) == nb.id,
      orElse: () => {},
    );
    if (doc.isNotEmpty) {
      await _loadDocumentDetail(doc);
    }
    if (!mounted) return;
    _scaffoldKey.currentState?.closeDrawer();
  }

  // 鍞よ捣鏈湴鏂囦欢涓婁紶绐楀彛
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result != null) {
        setState(() {
          _isUploading = true;
        });
        final uploadedNames = <String>[];
        var failedCount = 0;
        for (final file in result.files) {
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) {
            failedCount += 1;
            continue;
          }
          try {
            await _uploadSingleFile(file.name, bytes, file.extension);
            uploadedNames.add(file.name);
          } catch (_) {
            failedCount += 1;
          }
        }
        await _fetchDocuments(resetPage: true);
        await _refreshSkillNodes();
        if (!mounted) return;
        setState(() {
          _isUploading = false;
          if (uploadedNames.isNotEmpty) {
            _messages.add(ChatMessage(
              text: "鉁?宸叉垚鍔熶笂浼犲苟瑙ｆ瀽: ${uploadedNames.join(', ')}",
              isUser: true,
            ));
          }
          if (failedCount > 0) {
            _messages.add(ChatMessage(
              text: "鈿狅笍 $failedCount 涓枃浠朵笂浼犲け璐ワ紝璇锋鏌ュ悗绔垨 LightRAG 鐘舵€併€?,
              isUser: false,
            ));
          }
        });
        _scrollToBottom();
        if (uploadedNames.isNotEmpty) {
          _simulateBackendResponse("鏂囦欢宸叉帴鏀跺苟鍏ュ簱銆備綘鐜板湪鍙互鐩存帴鎻愰棶鏂囨。鍐呭銆?);
        }
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      debugPrint("鏂囦欢閫夋嫨鍑洪敊: $e");
    }
  }

  // 鍙戦€佹秷鎭苟璋冪敤澶фā鍨?API (棰勭暀鎺ュ彛)
  // 鍙戦€佹秷鎭苟璋冪敤澶фā鍨?API (棰勭暀鎺ュ彛)
  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _chatController.clear();
      _isThinking = true; // 寮€鍚璇濈瓑寰呮皵娉?      _centerMode = CenterViewMode.chat;
    });
    _scrollToBottom();

    _queryAssistant(text);
  }

  Future<void> _queryAssistant(String text) async {
    try {
      final result = await _apiGet(
        '/api/learning/query',
        query: {
          'query': text,
          'mode': _qaMode,
          'include_references': _includeReferences ? 'true' : 'false',
        },
      );
      final reply = (result['response'] ?? '').toString();
      final refs = (result['references'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => _shortFileName(_stringOf(entry['file_path'], fallback: 'Unknown')))
          .toList();
      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(
          text: reply.isEmpty ? '鍚庣宸插搷搴旓紝浣嗘湭杩斿洖鍐呭銆? : reply,
          isUser: false,
          references: refs,
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(
          text: "璇锋眰澶辫触锛?e",
          isUser: false,
        ));
      });
      _scrollToBottom();
    }
  }

  // 妯℃嫙鍚庣寤惰繜鍥炲 (寮傛澶勭悊)
  Future<void> _simulateBackendResponse(String responseText) async {
    // 妯℃嫙绛夊緟妯″瀷鐢熸垚鏂囨湰鐨勮€楁椂
    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(ChatMessage(text: responseText, isUser: false));
      });
      _scrollToBottom();
    }
  }

  // 澶勭悊鍙充晶 Studio 鍔熻兘鎸夐敭鐨勫紓姝ヨ姹?
  String _resolveGraphLabel() {
    if (_selectedDocument != null) {
      final path = _stringOf(_selectedDocument!['file_path']);
      final shortName = _shortFileName(path);
      if (shortName.isNotEmpty) {
        return shortName.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    }
    for (var index = _messages.length - 1; index >= 0; index -= 1) {
      final msg = _messages[index];
      if (msg.isUser && msg.text.trim().isNotEmpty) {
        return msg.text.trim();
      }
    }
    return 'knowledge';
  }

  String _studioActionLabel(String action) {
    const mapping = {
      'audio_overview': '闊抽姒傝',
      'video_overview': '瑙嗛姒傝',
      'mindmap': '鎬濈淮瀵煎浘',
      'report': '鎶ュ憡',
      'flashcards': '闂崱',
      'quiz': '娴嬮獙',
      'infographic': '淇℃伅鍥?,
      'presentation': '婕旂ず鏂囩',
      'table': '鏁版嵁琛ㄦ牸',
    };
    return mapping[action] ?? action;
  }

    Future<void> _handleStudioAction(String action) async {
    if (_isGeneratingStudio) return;

    setState(() {
      _isGeneratingStudio = true;
      _activeStudioTool = _studioActionLabel(action);
    });

    try {
      if (action == 'mindmap' || action == 'infographic') {
        final label = _resolveGraphLabel();
        final graphResult = await _apiGet(
          '/api/learning/graph',
          query: {
            'label': label,
            'max_depth': '3',
            'max_nodes': action == 'infographic' ? '80' : '120',
          },
        );
        if (!mounted) return;
        setState(() {
          _isGeneratingStudio = false;
          _activeStudioTool = null;
          _studioGraphPayload = graphResult;
          _studioGraphLabel = label;
          _centerMode = CenterViewMode.studioGraph;
        });
        return;
      }

      final topic = _resolveGraphLabel();
      final result = await _apiPost(
        '/api/learning/studio/generate',
        body: {
          'action': action,
          'topic': topic,
          'mode': _qaMode,
        },
      );

      final reply = (result['content'] ?? '').toString();
      final note = (result['capability_note'] ?? '').toString();

      if (!mounted) return;
      setState(() {
        _isGeneratingStudio = false;
        _activeStudioTool = null;
        _studioTextTitle = (result['title'] ?? _studioActionLabel(action)).toString();
        _studioTextType = (result['delivery_type'] ?? '').toString();
        _studioTextTopic = (result['topic'] ?? topic).toString();
        _studioTextContent = reply.isEmpty ? '（模型未返回正文）' : '$note\n\n$reply';
        _centerMode = CenterViewMode.studioText;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGeneratingStudio = false;
        _activeStudioTool = null;
      });
      await _showError(e);
    }
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(), // 鎺ュ叆鎶藉眽浣滀负绗旇鏈垪琛?
      body: Column(
        children: [
          _buildTopAppBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 宸︿晶 - 鏉ユ簮闈㈡澘
                  Expanded(flex: 2, child: _buildLeftPanel()),
                  const SizedBox(width: 12),
                  // 涓棿 - 瀵硅瘽闈㈡澘
                  Expanded(flex: 5, child: _buildCenterPanel()),
                  const SizedBox(width: 12),
                  // 鍙充晶 - Studio 闈㈡澘
                  Expanded(flex: 3, child: _buildRightPanel()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 椤堕儴瀵艰埅鏍?
  Widget _buildTopAppBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white70),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 14,
            backgroundColor: Colors.white24,
            child: Icon(Icons.auto_awesome_mosaic, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(
            _isLoadingNotebooks ? "鍔犺浇涓?.." : (_currentNotebook?.title ?? "Untitled notebook"),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          _buildTopButton(
            Icons.add, 
            _isCreatingNotebook ? "鍒涘缓涓?.." : "鍒涘缓绗旇鏈?, 
            onTap: _createNewNotebook,
            isLoading: _isCreatingNotebook,
          ),
          const SizedBox(width: 8),
          _buildTopButton(Icons.analytics_outlined, "鏂囨。", onTap: () => setState(() => _centerMode = CenterViewMode.document)),
          const SizedBox(width: 8),
          _buildTopButton(Icons.school_outlined, "瀛︿範", onTap: () => setState(() => _centerMode = CenterViewMode.learning)),
          const SizedBox(width: 8),
          _buildTopButton(Icons.quiz_outlined, "娴嬮獙", onTap: () => setState(() => _centerMode = CenterViewMode.quiz)),
          const SizedBox(width: 8),
          _buildTopButton(Icons.account_tree_outlined, "鍥捐氨", onTap: () => setState(() => _centerMode = CenterViewMode.studioGraph)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text("PRO", style: TextStyle(fontSize: 10, color: Colors.white70)),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.grid_view, color: Colors.white70),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blueAccent,
            child: Icon(Icons.person, size: 20, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTopButton(IconData icon, String label, {VoidCallback? onTap, bool isLoading = false}) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              )
            else
              Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // 绗旇鏈垪琛ㄤ晶杈规爮 (Drawer)
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1E1F20),
      child: Column(
        children: [
          Container(
            height: 120,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: const Text(
              "鎴戠殑绗旇鏈?,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          Expanded(
            child: _isLoadingNotebooks
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notebooks.length,
                    itemBuilder: (context, index) {
                      final nb = _notebooks[index];
                      final isSelected = nb.id == _currentNotebook?.id;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(
                            Icons.book, 
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white54
                          ),
                          title: Text(
                            nb.title, 
                            style: TextStyle(
                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          onTap: () => _switchNotebook(nb),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 宸︿晶闈㈡澘
  Widget _buildLeftPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("鏉ユ簮", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Icon(Icons.view_sidebar_outlined, color: Colors.white.withOpacity(0.6), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickFile,
              icon: _isUploading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.add, size: 18),
              label: Text(_isUploading ? "姝ｅ湪涓婁紶瑙ｆ瀽..." : "娣诲姞鏉ユ簮"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _documentsStatusFilter,
                  dropdownColor: const Color(0xFF282A2D),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('鍏ㄩ儴鐘舵€?)),
                    DropdownMenuItem<String?>(value: 'processed', child: Text('宸插鐞?)),
                    DropdownMenuItem<String?>(value: 'processing', child: Text('澶勭悊涓?)),
                    DropdownMenuItem<String?>(value: 'pending', child: Text('绛夊緟涓?)),
                    DropdownMenuItem<String?>(value: 'failed', child: Text('澶辫触')),
                    DropdownMenuItem<String?>(value: 'preprocessed', child: Text('棰勫鐞?)),
                  ],
                  onChanged: (value) async {
                    setState(() => _documentsStatusFilter = value);
                    await _fetchDocuments(resetPage: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  await _fetchDocuments();
                  await _refreshPipelineStatus(silent: true);
                },
                icon: const Icon(Icons.refresh, color: Colors.white70),
                style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('鍏?$_documentsTotal 鏉?, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await _refreshPipelineStatus();
                },
                icon: const Icon(Icons.sync, size: 14),
                label: const Text('闃熷垪', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusMetricCard('processed', '宸插鐞?),
                const SizedBox(width: 8),
                _buildStatusMetricCard('processing', '澶勭悊涓?),
                const SizedBox(width: 8),
                _buildStatusMetricCard('pending', '绛夊緟涓?),
                const SizedBox(width: 8),
                _buildStatusMetricCard('failed', '澶辫触'),
                const SizedBox(width: 8),
                _buildStatusMetricCard('preprocessed', '棰勫鐞?),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildPipelineCard(),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoadingDocuments
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                : _documents.isEmpty
                    ? Center(
                        child: Text('鏆傛棤鏂囨。鏉ユ簮', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                      )
                    : ListView.builder(
                        itemCount: _documents.length,
                        itemBuilder: (context, index) {
                          final doc = _documents[index];
                          final docId = _stringOf(doc['id']);
                          final selected = _selectedDocument != null && _stringOf(_selectedDocument!['id']) == docId;
                          final status = _stringOf(doc['status'], fallback: 'pending');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF2A2D31) : const Color(0xFF232527),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? Theme.of(context).colorScheme.primary : Colors.white10,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shortFileName(_stringOf(doc['file_path'], fallback: '鏈懡鍚嶆枃妗?)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _statusText(status),
                                  style: TextStyle(fontSize: 11, color: _statusColor(status)),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _loadDocumentDetail(doc),
                                        child: const Text('鏌ョ湅', style: TextStyle(fontSize: 11)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _deleteDocument(doc),
                                        child: const Text('鍒犻櫎', style: TextStyle(fontSize: 11)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _documentsHasPrev
                      ? () async {
                          _documentsPage -= 1;
                          await _fetchDocuments();
                        }
                      : null,
                  child: const Text('涓婁竴椤?),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _documentsHasNext
                      ? () async {
                          _documentsPage += 1;
                          await _fetchDocuments();
                        }
                      : null,
                  child: const Text('涓嬩竴椤?),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.7)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white.withOpacity(0.7)),
        ],
      ),
    );
  }

  // 涓棿闈㈡澘
  Widget _buildCenterPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text("宸ヤ綔鍖?, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const Spacer(),
                Wrap(
                  spacing: 8,
                  children: [
                    _modeChip('瀵硅瘽', _centerMode == CenterViewMode.chat, () => setState(() => _centerMode = CenterViewMode.chat)),
                    _modeChip('鏂囨。', _centerMode == CenterViewMode.document, () => setState(() => _centerMode = CenterViewMode.document)),
                    _modeChip('瀛︿範', _centerMode == CenterViewMode.learning, () => setState(() => _centerMode = CenterViewMode.learning)),
                    _modeChip('娴嬮獙', _centerMode == CenterViewMode.quiz, () => setState(() => _centerMode = CenterViewMode.quiz)),
                    _modeChip('鍥捐氨', _centerMode == CenterViewMode.studioGraph, () => setState(() => _centerMode = CenterViewMode.studioGraph)),
                    _modeChip('Studio', _centerMode == CenterViewMode.studioText, () => setState(() => _centerMode = CenterViewMode.studioText)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _buildCenterBody()),
          if (_centerMode == CenterViewMode.chat) _buildChatInputArea(),
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.18) : Colors.white10,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
      ),
    );
  }

  Widget _buildStatusMetricCard(String key, String label) {
    final count = _statusCounts[key] ?? 0;
    final color = _statusColor(key);
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon(key), size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineCard() {
    final pipeline = _pipelineStatus;
    if (pipeline == null || pipeline.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          '鏆傛棤澶勭悊闃熷垪鐘舵€?,
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6)),
        ),
      );
    }
    final busy = pipeline['busy'] == true;
    final curBatch = _intOf(pipeline['cur_batch']);
    final totalBatch = _intOf(pipeline['batchs'], fallback: 1);
    final progress = totalBatch <= 0 ? 0.0 : (curBatch / totalBatch).clamp(0.0, 1.0);
    final jobName = _stringOf(pipeline['job_name'], fallback: '鏈煡浠诲姟');
    final message = _stringOf(pipeline['latest_message'], fallback: '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                busy ? Icons.sync : Icons.check_circle_outline,
                size: 14,
                color: busy ? Colors.orangeAccent : Colors.greenAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  busy ? '澶勭悊涓細$jobName' : '澶勭悊闃熷垪绌洪棽',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (busy)
                Text(
                  '$curBatch/$totalBatch',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: busy ? progress : 1,
            minHeight: 6,
            backgroundColor: Colors.white10,
            color: busy ? Colors.orangeAccent : Colors.greenAccent,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenterBody() {
    switch (_centerMode) {
      case CenterViewMode.document:
        return _buildDocumentDetailView();
      case CenterViewMode.learning:
        return _buildLearningView();
      case CenterViewMode.quiz:
        return _buildQuizView();
      case CenterViewMode.studioGraph:
        return _buildStudioGraphView();
      case CenterViewMode.studioText:
        return _buildStudioTextView();
      case CenterViewMode.chat:
      default:
        return _buildChatView();
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
    return const [];
  }

  String _readStringByKeys(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  Map<String, dynamic> _getGraphRoot(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final graph = payload['graph'];
      if (graph is Map) {
        return Map<String, dynamic>.from(graph);
      }
      return payload;
    }
    return {};
  }

  List<_GraphNodeVm> _extractGraphNodes(Map<String, dynamic> graphRoot) {
    dynamic rawNodes;
    for (final key in ['nodes', 'vertices', 'entities', 'items']) {
      if (graphRoot.containsKey(key)) {
        rawNodes = graphRoot[key];
        break;
      }
    }
    final parsed = <_GraphNodeVm>[];
    final seen = <String>{};
    for (final item in _asMapList(rawNodes)) {
      final id = _readStringByKeys(item, ['id', 'node_id', 'name', 'label', 'entity']);
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      final label = _readStringByKeys(item, ['label', 'name', 'entity', 'title']);
      parsed.add(_GraphNodeVm(id: id, label: label.isEmpty ? id : label));
    }
    return parsed;
  }

  List<_GraphEdgeVm> _extractGraphEdges(Map<String, dynamic> graphRoot) {
    dynamic rawEdges;
    for (final key in ['edges', 'links', 'relations', 'relationships']) {
      if (graphRoot.containsKey(key)) {
        rawEdges = graphRoot[key];
        break;
      }
    }
    final parsed = <_GraphEdgeVm>[];
    for (final item in _asMapList(rawEdges)) {
      final source = _readStringByKeys(item, ['source', 'from', 'src', 'start', 'head']);
      final target = _readStringByKeys(item, ['target', 'to', 'dst', 'end', 'tail']);
      if (source.isEmpty || target.isEmpty) continue;
      final label = _readStringByKeys(item, ['label', 'type', 'relation', 'name']);
      parsed.add(_GraphEdgeVm(source: source, target: target, label: label));
    }
    return parsed;
  }

  Future<void> _exportGraphAsPng() async {
    if (_isExportingGraph) return;
    setState(() => _isExportingGraph = true);

    try {
      final boundary = _graphExportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('鏈壘鍒板彲瀵煎嚭鐨勫浘璋辩敾甯冦€?);
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('鍥捐氨瀵煎嚭澶辫触锛氭棤娉曠敓鎴愬浘鐗囧瓧鑺傛祦銆?);
      }
      final bytes = byteData.buffer.asUint8List();

      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filename = 'knowledge_graph_${_studioGraphLabel ?? 'export'}_$ts.png';

      final saveResult = await FilePicker.platform.saveFile(
        dialogTitle: '瀵煎嚭鐭ヨ瘑鍥捐氨',
        fileName: filename,
        bytes: bytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saveResult == null
                ? '宸插彇娑堝鍑?
                : '瀵煎嚭鎴愬姛锛?filename',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isExportingGraph = false);
      }
    }
  }

  Widget _buildStudioTextView() {
    final title = (_studioTextTitle ?? '').trim();
    final topic = (_studioTextTopic ?? '').trim();
    final type = (_studioTextType ?? '').trim();
    final content = (_studioTextContent ?? '').trim();

    if (content.isEmpty) {
      return Center(
        child: Text(
          '请在右侧 Studio 选择“报告 / 闪卡 / 测验 / 演示文稿 / 表格 / 音频 / 视频”生成文本结果',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Studio 输出' : title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (type.isNotEmpty) _buildMetaTag('类型: $type'),
              if (topic.isNotEmpty) _buildMetaTag('主题: $topic'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF171819),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }
  Widget _buildStudioGraphView() {
    final payload = _studioGraphPayload;
    if (payload == null) {
      return Center(
        child: Text(
          '璇峰湪鍙充晶 Studio 鐐瑰嚮銆屾€濈淮瀵煎浘銆嶆垨銆屼俊鎭浘銆嶇敓鎴愬浘璋?,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    final graphRoot = _getGraphRoot(payload);
    final nodes = _extractGraphNodes(graphRoot);
    final edges = _extractGraphEdges(graphRoot);

    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '鍥捐氨缁撴灉涓虹┖锛坙abel: ${_studioGraphLabel ?? ''}锛?,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '鍙皾璇曞厛涓婁紶鏂囨。骞剁瓑寰?LightRAG 澶勭悊瀹屾垚锛屽啀閲嶆柊鐢熸垚銆?,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }

    final size = const Size(1200, 760);
    final positions = _layoutCircular(nodes, size);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '鐭ヨ瘑鍥捐氨锛?{_studioGraphLabel ?? ''}锛堣妭鐐?${nodes.length} / 杈?${edges.length}锛?,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isExportingGraph ? null : _exportGraphAsPng,
                  icon: _isExportingGraph
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 16),
                  label: const Text('瀵煎嚭 PNG'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(0xFF171819),
                child: InteractiveViewer(
                  minScale: 0.3,
                  maxScale: 4,
                  constrained: false,
                  child: RepaintBoundary(
                    key: _graphExportKey,
                    child: CustomPaint(
                      size: size,
                      painter: _KnowledgeGraphPainter(
                        nodes: nodes,
                        edges: edges,
                        positions: positions,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Offset> _layoutCircular(List<_GraphNodeVm> nodes, Size size) {
    final map = <String, Offset>{};
    if (nodes.isEmpty) return map;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    for (var index = 0; index < nodes.length; index += 1) {
      final angle = (2 * math.pi * index) / nodes.length;
      map[nodes[index].id] = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
    }
    return map;
  }

  Widget _buildChatView() {
    if (_messages.isEmpty) return _buildEmptyChatState();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _messages.length + (_isThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) return _buildThinkingBubble();
        return _buildChatBubble(_messages[index]);
      },
    );
  }

  Widget _buildDocumentDetailView() {
    if (_selectedDocument == null) {
      return Center(
        child: Text('璇峰湪宸︿晶閫夋嫨鏂囨。', style: TextStyle(color: Colors.white.withOpacity(0.6))),
      );
    }
    if (_isLoadingDocumentDetail) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    final doc = _selectedDocument!;
    final status = _stringOf(doc['status'], fallback: 'pending');
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Text(
          _shortFileName(_stringOf(doc['file_path'], fallback: '鏈懡鍚嶆枃妗?)),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text('ID: ${_stringOf(doc['id'])}', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 4),
        Text('鐘舵€? ${_statusText(status)}', style: TextStyle(color: _statusColor(status))),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _metricCard('闀垮害', '${_intOf(doc['content_length'])} 瀛楃')),
            const SizedBox(width: 8),
            Expanded(child: _metricCard('鍒嗗潡', '${_intOf(doc['chunks_count'])}')),
            const SizedBox(width: 8),
            Expanded(child: _metricCard('鏇存柊', _stringOf(doc['updated_at']).replaceFirst('T', ' ').split('.').first)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            _stringOf(doc['content_summary'], fallback: '鏆傛棤鎽樿'),
            style: const TextStyle(height: 1.4, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('鍏宠仈鐭ヨ瘑鐐?, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('${_documentKnowledgeNodes.length} 涓?, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 8),
        if (_documentKnowledgeNodes.isEmpty)
          Text('鏆傛棤鐭ヨ瘑鐐?, style: TextStyle(color: Colors.white.withOpacity(0.5)))
        else
          ..._documentKnowledgeNodes.take(20).map(_knowledgeNodeTile),
      ],
    );
  }

  Widget _knowledgeNodeTile(Map<String, dynamic> node) {
    final mastery = _doubleOf(node['mastery']);
    final status = _stringOf(node['status']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_stringOf(node['name'], fallback: '鏈懡鍚嶇煡璇嗙偣'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_stringOf(node['description'], fallback: '鏆傛棤鎻忚堪'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (mastery.clamp(0, 100)) / 100,
            minHeight: 6,
            backgroundColor: Colors.white10,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 4),
          Text('${_statusText(status)} 路 ${mastery.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: _statusColor(status))),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 4),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildLearningView() {
    if (_learningContent == null || _learningContent!.isEmpty) {
      return Center(
        child: Text('璇峰湪鍙充晶鎶€鑳芥爲鐐瑰嚮鈥滃涔犫€?, style: TextStyle(color: Colors.white.withOpacity(0.6))),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Text(_learningNodeName ?? '瀛︿範鍐呭', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(_learningContent!, style: const TextStyle(height: 1.45, color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildQuizView() {
    if (_quizQuestions.isEmpty) {
      return Center(
        child: Text('璇峰湪鍙充晶鎶€鑳芥爲鐐瑰嚮鈥滃嚭棰樷€?, style: TextStyle(color: Colors.white.withOpacity(0.6))),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Text('娴嬮獙锛?{_quizNodeName ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ..._quizQuestions.asMap().entries.map((entry) {
          final index = entry.key;
          final question = entry.value;
          final qid = _stringOf(question['id'], fallback: 'q$index');
          final qType = _stringOf(question['type'], fallback: 'short_answer');
          final title = _stringOf(question['question'], fallback: '鏈彁渚涢骞?);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q${index + 1}. $title', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (qType == 'multiple_choice')
                  ...(question['options'] as List? ?? const []).map(
                    (option) => RadioListTile<String>(
                      dense: true,
                      value: option.toString(),
                      groupValue: _quizAnswers[qid]?.toString(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _quizAnswers[qid] = value);
                      },
                      title: Text(option.toString(), style: const TextStyle(fontSize: 13)),
                    ),
                  )
                else if (qType == 'true_false')
                  ...['瀵?, '閿?].map(
                    (option) => RadioListTile<String>(
                      dense: true,
                      value: option,
                      groupValue: _quizAnswers[qid]?.toString(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _quizAnswers[qid] = value);
                      },
                      title: Text(option, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                else
                  TextField(
                    onChanged: (value) => _quizAnswers[qid] = value.trim(),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: '杈撳叆浣犵殑绛旀',
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          );
        }),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSubmittingQuiz ? null : _submitQuiz,
            icon: _isSubmittingQuiz
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.check),
            label: const Text('鎻愪氦娴嬮獙'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_quizResult != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '寰楀垎锛?{_doubleOf((_quizResult!['grading_result'] as Map?)?['score']).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '鐘舵€侊細${_statusText(_stringOf(_quizResult!['new_status']))} 路 鎺屾彙搴?${_doubleOf(_quizResult!['new_mastery']).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 绌鸿亰澶╃姸鎬?
  Widget _buildEmptyChatState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF282A2D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.upload_file, size: 40, color: Color(0xFFA8C7FA)),
          ),
          const SizedBox(height: 24),
          const Text(
            "娣诲姞鏉ユ簮鍗冲彲寮€濮嬩娇鐢?,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text("涓婁紶鏉ユ簮"),
          ),
        ],
      ),
    );
  }

  // 鑱婂ぉ姘旀场
  Widget _buildChatBubble(ChatMessage message) {
    bool isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.35),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2E3135) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isUser ? null : Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.white.withOpacity(0.9),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (message.references.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '鏉ユ簮: ${message.references.join(', ')}',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text("姝ｅ湪鎬濊€?..", style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  // 搴曢儴杈撳叆妗?
  Widget _buildChatInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF282A2D),
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: "涓婁紶鏉ユ簮鍗冲彲寮€濮嬩娇鐢?,
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                Text("${_documents.length} 涓潵婧?, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _sendMessage,
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.arrow_forward, color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "NotebookLM 鎻愪緵鐨勫唴瀹规湭蹇呭噯纭紝鍥犳璇蜂粩缁嗘牳鏌ュ洖绛斿唴瀹广€?,
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // 鍙充晶闈㈡澘
  Widget _buildRightPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Studio", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Icon(Icons.view_sidebar_outlined, color: Colors.white.withOpacity(0.6), size: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _buildStudioTool(Icons.graphic_eq, "闊抽姒傝", () => _handleStudioAction("audio_overview")),
                _buildStudioTool(Icons.play_circle_outline, "瑙嗛姒傝", () => _handleStudioAction("video_overview")),
                _buildStudioTool(Icons.account_tree_outlined, "鎬濈淮瀵煎浘", () => _handleStudioAction("mindmap")),
                _buildStudioTool(Icons.description_outlined, "鎶ュ憡", () => _handleStudioAction("report")),
                _buildStudioTool(Icons.style_outlined, "闂崱", () => _handleStudioAction("flashcards")),
                _buildStudioTool(Icons.help_outline, "娴嬮獙", () => _handleStudioAction("quiz")),
                _buildStudioTool(Icons.insert_chart_outlined, "淇℃伅鍥?, () => _handleStudioAction("infographic")),
                _buildStudioTool(Icons.slideshow, "婕旂ず鏂囩", () => _handleStudioAction("presentation")),
                _buildStudioTool(Icons.table_chart_outlined, "鏁版嵁琛ㄦ牸", () => _handleStudioAction("table")),
              ],
            ),
          ),
          if (_isGeneratingStudio)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "姝ｅ湪鐢熸垚 $_activeStudioTool...",
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _panelTitle('闂瓟璁剧疆'),
                DropdownButtonFormField<String>(
                  value: _qaMode,
                  dropdownColor: const Color(0xFF282A2D),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  items: const ['mix', 'local', 'global', 'hybrid', 'naive', 'bypass']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _qaMode = value);
                  },
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _includeReferences,
                  onChanged: (value) => setState(() => _includeReferences = value ?? false),
                  title: const Text('鍖呭惈鍙傝€冩枃鐚?, style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('姣忔娴嬮獙棰樻暟', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _quizQuestionCount,
                      dropdownColor: const Color(0xFF282A2D),
                      items: [3, 4, 5, 6, 8, 10].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _quizQuestionCount = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _panelTitle('鎶€鑳芥爲'),
                if (_isLoadingSkillNodes)
                  Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                else if (_skillNodes.isEmpty)
                  Text('鏆傛棤鎶€鑳界偣', style: TextStyle(color: Colors.white.withOpacity(0.5)))
                else
                  ..._skillNodes.map(_buildSkillNodeCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _buildSkillNodeCard(Map<String, dynamic> node) {
    final status = _stringOf(node['status'], fallback: 'locked');
    final mastery = _doubleOf(node['mastery']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_stringOf(node['name'], fallback: '鏈懡鍚嶆妧鑳界偣'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(_statusText(status), style: TextStyle(fontSize: 11, color: _statusColor(status))),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (mastery.clamp(0, 100)) / 100,
            minHeight: 5,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 6),
          Text('鎺屾彙搴?${mastery.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (status == 'available' || status == 'learning')
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _startLearning(node),
                    child: const Text('瀛︿範', style: TextStyle(fontSize: 11)),
                  ),
                ),
              if (status == 'available' || status == 'learning') const SizedBox(width: 6),
              if (status == 'learning')
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _completeLearning(node),
                    child: const Text('瀹屾垚', style: TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isGeneratingQuiz ? null : () => _generateQuizForNode(node),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: _isGeneratingQuiz && _quizNodeId == _stringOf(node['id'])
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('鍑洪', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioTool(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.white.withOpacity(0.6)),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _GraphNodeVm {
  final String id;
  final String label;

  const _GraphNodeVm({
    required this.id,
    required this.label,
  });
}

class _GraphEdgeVm {
  final String source;
  final String target;
  final String label;

  const _GraphEdgeVm({
    required this.source,
    required this.target,
    this.label = '',
  });
}

class _KnowledgeGraphPainter extends CustomPainter {
  final List<_GraphNodeVm> nodes;
  final List<_GraphEdgeVm> edges;
  final Map<String, Offset> positions;

  const _KnowledgeGraphPainter({
    required this.nodes,
    required this.edges,
    required this.positions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = const Color(0xFF6EA8FE)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final start = positions[edge.source];
      final end = positions[edge.target];
      if (start == null || end == null) continue;
      canvas.drawLine(start, end, edgePaint);
    }

    for (final node in nodes) {
      final point = positions[node.id];
      if (point == null) continue;
      canvas.drawCircle(point, 24, nodePaint);
      canvas.drawCircle(point, 24, borderPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        maxLines: 2,
        ellipsis: '鈥?,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 130);

      textPainter.paint(
        canvas,
        Offset(
          point.dx - textPainter.width / 2,
          point.dy + 28,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.positions != positions;
  }
}
