import 'dart:async';
import 'package:flutter/services.dart';
import 'ai_service.dart';

/// Mobile backend (Android, iOS) — calls native llama.cpp via MethodChannel.
class NativeAiService implements AiService {
  static const _channel = MethodChannel('com.kamsbot/llama');
  static const _tokenChannel = EventChannel('com.kamsbot/llama_tokens');

  static const _modelUrl =
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF'
      '/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';

  static const _systemPrompt =
      'You are Kams Bot, a factual offline AI assistant. '
      'Keep answers short and to the point. '
      'Never invent facts. If unsure, say "I don\'t know".';

  @override
  String get modelName => 'TinyLlama 1.1B';

  @override
  Future<void> start() async {}  // No-op: native engine starts on demand

  @override
  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isLoaded') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasModel() async {
    try {
      return await _channel.invokeMethod<bool>('hasModel') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<double> pullModel() {
    final controller = StreamController<double>();
    _channel.invokeMethod('downloadModel', {'url': _modelUrl}).then((_) {
      // Progress comes via a separate event channel
    });
    const progressChannel = EventChannel('com.kamsbot/download_progress');
    progressChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is double) controller.add(event);
        if (event == 1.0) controller.close();
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    return controller.stream;
  }

  @override
  Stream<String> chat(List<Map<String, String>> history) {
    final controller = StreamController<String>();
    final prompt = _buildPrompt(history);
    _channel.invokeMethod('generate', {'prompt': prompt});
    _tokenChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is String) {
          if (event == '[DONE]') {
            controller.close();
          } else {
            controller.add(event);
          }
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    return controller.stream;
  }

  String _buildPrompt(List<Map<String, String>> history) {
    final buf = StringBuffer();
    buf.write('<|system|>\n$_systemPrompt</s>\n');
    for (final msg in history) {
      final role = msg['role']!;
      final content = msg['content']!;
      if (role == 'user') {
        buf.write('<|user|>\n$content</s>\n');
      } else if (role == 'assistant') {
        buf.write('<|assistant|>\n$content</s>\n');
      }
    }
    buf.write('<|assistant|>\n');
    return buf.toString();
  }
}
