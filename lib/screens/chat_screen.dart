import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_viewmodel.dart';
import '../models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _vm = ChatViewModel();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onStateChange);
    _vm.initialize();
  }

  void _onStateChange() {
    setState(() {});
    if (_vm.state == AppState.chat && _vm.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _send() {
    _vm.setInput(_textController.text);
    _vm.send();
    _textController.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _vm.removeListener(_onStateChange);
    _vm.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: switch (_vm.state) {
        AppState.checking || AppState.starting => _buildStatus(
            Icons.circle_outlined,
            'Starting Kams Bot...',
            null,
          ),
        AppState.noBackend => _buildStatus(
            Icons.warning_amber_rounded,
            'AI backend unavailable',
            'Could not start the AI engine. Please restart the app.',
            action: TextButton(
              onPressed: _vm.retry,
              child: const Text('Retry', style: TextStyle(color: Color(0xFFE53935))),
            ),
          ),
        AppState.downloading => _buildDownloading(),
        AppState.chat => _buildChat(),
        AppState.error => _buildStatus(
            Icons.error_outline,
            'Something went wrong',
            _vm.errorMessage,
            action: TextButton(
              onPressed: _vm.retry,
              child: const Text('Retry', style: TextStyle(color: Color(0xFFE53935))),
            ),
          ),
      },
    );
  }

  // ── Status screen ─────────────────────────────────────────────────────────

  Widget _buildStatus(IconData icon, String title, String? subtitle, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.white38),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }

  // ── Download screen ───────────────────────────────────────────────────────

  Widget _buildDownloading() {
    final pct = _vm.downloadProgress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Kams Bot',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              const Text('Downloading AI model — this only happens once',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 32),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pct > 0 ? pct : null,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                pct > 0 ? '${(pct * 100).toStringAsFixed(0)}%' : 'Starting...',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat screen ───────────────────────────────────────────────────────────

  Widget _buildChat() {
    return Column(
      children: [
        _buildTopBar(),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _vm.messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _vm.messages.length,
                  itemBuilder: (_, i) => _MessageBubble(message: _vm.messages[i]),
                ),
        ),
        const Divider(height: 1, color: Colors.white12),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Kams Bot',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _vm.modelName,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Kams Bot',
              style: TextStyle(
                  color: Colors.white24,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Ask me anything',
              style: TextStyle(color: Colors.white24, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  if (!_vm.isGenerating && _textController.text.trim().isNotEmpty) {
                    _send();
                  }
                }
              },
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask something...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _vm.setInput,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (_vm.isGenerating || _textController.text.trim().isEmpty)
                ? null
                : _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (_vm.isGenerating || _textController.text.trim().isEmpty)
                    ? Colors.white12
                    : const Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser
                    ? const Color(0xFFE53935)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SelectableText(
                message.text.isEmpty ? '...' : message.text,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              ),
            ),
          ),
          if (message.isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
