import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() {
  runApp(const KamsBotApp());
}

class KamsBotApp extends StatelessWidget {
  const KamsBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kams Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE53935),
          surface: Color(0xFF0A0A0A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}
