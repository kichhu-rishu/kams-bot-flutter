import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'ai_service.dart';

/// Desktop backend (macOS, Windows) — talks to a local Ollama server.
class OllamaService implements AiService {
  static const _base = 'http://localhost:11434';
  static const _model = 'qwen2.5:1.5b';

  static const _systemPrompt =
      'You are Kams Bot, a factual offline AI assistant. '
      'Answer only what you are confident about. '
      'Keep answers short and to the point. '
      'Never invent facts, dates, names, or statistics. '
      'If unsure, say "I don\'t know" instead of guessing.';

  @override
  String get modelName => _model;

  /// Starts the bundled Ollama binary (if not already running).
  @override
  Future<void> start() async {
    if (await isRunning()) return;
    final binary = _bundledOllamaPath();
    if (binary == null) return;
    final dir = File(binary).parent.path;
    await Process.start(
      binary,
      ['serve'],
      workingDirectory: dir,
      environment: {
        ...Platform.environment,
        'DYLD_LIBRARY_PATH': dir,       // macOS
        'PATH': '${Platform.environment['PATH'] ?? ''}:$dir',
      },
      mode: ProcessStartMode.detached,
    );
  }

  @override
  Future<bool> isRunning() async {
    try {
      final resp = await http.get(Uri.parse(_base)).timeout(const Duration(seconds: 2));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasModel() async {
    try {
      final resp = await http.get(Uri.parse('$_base/api/tags'));
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final models = (json['models'] as List).cast<Map<String, dynamic>>();
      return models.any((m) => (m['name'] as String).startsWith(_model));
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<double> pullModel() async* {
    final request = http.Request('POST', Uri.parse('$_base/api/pull'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'name': _model, 'stream': true});
    final response = await request.send();
    await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        final json = jsonDecode(chunk) as Map<String, dynamic>;
        final total = json['total'] as int?;
        final completed = json['completed'] as int?;
        if (total != null && completed != null && total > 0) {
          yield completed / total;
        }
        if (json['status'] == 'success') return;
      } catch (_) {}
    }
  }

  @override
  Stream<String> chat(List<Map<String, String>> history) async* {
    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      ...history,
    ];
    final request = http.Request('POST', Uri.parse('$_base/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': _model,
        'messages': messages,
        'stream': true,
        'options': {
          'temperature': 0.15,
          'top_p': 0.75,
          'top_k': 30,
          'repeat_penalty': 1.15,
          'num_predict': 300,
        },
      });
    final response = await request.send();
    await for (final chunk in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        final json = jsonDecode(chunk) as Map<String, dynamic>;
        final token = (json['message'] as Map<String, dynamic>?)?['content'] as String?;
        if (token != null) yield token;
        if (json['done'] == true) return;
      } catch (_) {}
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String? _bundledOllamaPath() {
    // macOS: binary is next to the app executable
    if (Platform.isMacOS) {
      final exe = Platform.resolvedExecutable; // .../KamsBot.app/Contents/MacOS/kams_bot
      final resourcesDir = File(exe).parent.parent.path + '/Resources/ollama';
      final path = '$resourcesDir/ollama';
      if (File(path).existsSync()) return path;
    }
    // Windows: binary is in the same folder as the exe
    if (Platform.isWindows) {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final path = '$dir\\ollama\\ollama.exe';
      if (File(path).existsSync()) return path;
    }
    // Fallback to system install
    for (final p in ['/opt/homebrew/bin/ollama', '/usr/local/bin/ollama']) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }
}
