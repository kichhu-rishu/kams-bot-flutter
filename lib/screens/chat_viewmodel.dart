import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/ollama_service.dart';
import '../services/native_service.dart';

enum AppState { checking, noBackend, starting, downloading, chat, error }

class ChatViewModel extends ChangeNotifier {
  AppState state = AppState.checking;
  String errorMessage = '';
  double downloadProgress = 0;
  List<ChatMessage> messages = [];
  String input = '';
  bool isGenerating = false;

  late final AiService _ai;

  ChatViewModel() {
    _ai = (Platform.isAndroid || Platform.isIOS)
        ? NativeAiService()
        : OllamaService();
  }

  String get modelName => _ai.modelName;

  Future<void> initialize() async {
    state = AppState.checking;
    notifyListeners();

    // Desktop: start Ollama if not running
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (!await _ai.isRunning()) {
        state = AppState.starting;
        notifyListeners();
        await _ai.start();
        // Wait up to 8s
        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (await _ai.isRunning()) break;
        }
        if (!await _ai.isRunning()) {
          state = AppState.noBackend;
          notifyListeners();
          return;
        }
      }
    }

    // Download model if needed
    if (!await _ai.hasModel()) {
      state = AppState.downloading;
      downloadProgress = 0;
      notifyListeners();
      try {
        await for (final progress in _ai.pullModel()) {
          downloadProgress = progress;
          notifyListeners();
        }
      } catch (e) {
        state = AppState.error;
        errorMessage = 'Download failed: $e';
        notifyListeners();
        return;
      }
    }

    // Mobile: load the model into memory
    if (Platform.isAndroid || Platform.isIOS) {
      state = AppState.starting;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    state = AppState.chat;
    notifyListeners();
  }

  void setInput(String value) {
    input = value;
    notifyListeners();
  }

  Future<void> send() async {
    final text = input.trim();
    if (text.isEmpty || isGenerating) return;
    input = '';
    isGenerating = true;

    messages.add(ChatMessage(text: text, isUser: true));
    messages.add(ChatMessage(text: '', isUser: false));
    notifyListeners();

    final history = messages
        .sublist(0, messages.length - 1)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
        .toList();

    try {
      await for (final token in _ai.chat(history)) {
        messages[messages.length - 1] =
            ChatMessage(text: messages.last.text + token, isUser: false);
        notifyListeners();
      }
    } catch (e) {
      messages[messages.length - 1] =
          ChatMessage(text: 'Error: $e', isUser: false);
    }

    isGenerating = false;
    notifyListeners();
  }

  Future<void> retry() => initialize();
}
