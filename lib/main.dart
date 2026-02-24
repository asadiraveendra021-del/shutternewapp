import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────
//  CONFIG — Change these for your hardware
// ─────────────────────────────────────────────
const String kEmail = 'asadiraveendra021@gmail.com';
const String kAppPassword = 'iiwq aetl lmsg kkfe';
const String kImapHost = 'imap.gmail.com';
const int kImapPort = 993;
const String kSenderFilter = 'ravindraravi86814@gmail.com';

// Replace these with your REAL shutter control URLs
const String kTriggerApiUrl = 'https://jsonplaceholder.typicode.com/posts';
const String kVerifyApiUrl = 'https://jsonplaceholder.typicode.com/posts';

const int kPollIntervalSeconds = 5;
const int kMaxPollAttempts = 24; 
// ─────────────────────────────────────────────

void main() => runApp(const ShutterApp());

class ShutterApp extends StatelessWidget {
  const ShutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shutter Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFB2),
          secondary: Color(0xFFFF4C6E),
          surface: Color(0xFF12121A),
        ),
      ),
      home: const ShutterHomePage(),
    );
  }
}

class ShutterHomePage extends StatefulWidget {
  const ShutterHomePage({super.key});
  @override
  State<ShutterHomePage> createState() => _ShutterHomePageState();
}

enum _LogLevel { info, success, warning, error }

class _LogEntry {
  final String timestamp;
  final String message;
  final _LogLevel level;
  _LogEntry({required this.timestamp, required this.message, required this.level});
}

class _ShutterHomePageState extends State<ShutterHomePage> with SingleTickerProviderStateMixin {
  final List<_LogEntry> _logs = [];
  bool _busy = false;
  String? _lastOtp;
  Timer? _pollTimer;
  int _pollCount = 0;
  String _action = '';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _log('System Ready. Waiting for input...', _LogLevel.info);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _log(String message, _LogLevel level) {
    setState(() {
      _logs.add(_LogEntry(
        timestamp: _timeNow(),
        message: message,
        level: level,
      ));
    });
  }

  String _timeNow() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  Future<void> _onButtonPressed(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _action = action;
      _lastOtp = null;
      _logs.clear();
    });
    _log('► Initiating $action sequence...', _LogLevel.info);

    try {
      await _callTriggerApi(action);
      final otp = await _pollForOtp();

      if (otp == null) {
        _log('✗ TIMEOUT: No OTP detected in 2 mins.', _LogLevel.error);
      } else {
        await _callVerifyApi(action, otp);
        _log('✓ SHUTTER $action COMMAND EXECUTED.', _LogLevel.success);
      }
    } catch (e) {
      _log('✗ CRITICAL ERROR: $e', _LogLevel.error);
    } finally {
      _pollTimer?.cancel();
      setState(() => _busy = false);
    }
  }

  Future<void> _callTriggerApi(String action) async {
    _log('Sending Trigger Signal...', _LogLevel.info);
    final response = await http.post(
      Uri.parse(kTriggerApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    _log('Trigger Response: ${response.statusCode}', _LogLevel.info);
  }

  Future<String?> _pollForOtp() async {
    _pollCount = 0;
    final completer = Completer<String?>();

    _pollTimer = Timer.periodic(const Duration(seconds: kPollIntervalSeconds), (timer) async {
      _pollCount++;
      _log('Scanning Gmail (Attempt $_pollCount/$kMaxPollAttempts)...', _LogLevel.info);

      try {
        final otp = await _fetchLatestOtp();
        if (otp != null) {
          timer.cancel();
          completer.complete(otp);
        } else if (_pollCount >= kMaxPollAttempts) {
          timer.cancel();
          completer.complete(null);
        }
      } catch (e) {
        _log('IMAP Sync Error: $e', _LogLevel.error);
        timer.cancel();
        completer.complete(null);
      }
    });

    return completer.future;
  }

  // FIXED THIS FUNCTION TO AVOID CODEMAGIC ERRORS
  Future<String?> _fetchLatestOtp() async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(kImapHost, kImapPort, isSecure: true);
      await client.login(kEmail, kAppPassword);
      await client.selectInbox();

      // We use fetchRecentMessages instead of searchMessages to avoid SearchQueryType errors
      final fetchResult = await client.fetchRecentMessages(messageCount: 5, criteria: 'UNSEEN');

      if (fetchResult.messages.isEmpty) {
        await client.logout();
        return null;
      }

      for (final msg in fetchResult.messages) {
        final sender = msg.fromEmail ?? "";
        if (sender.contains(kSenderFilter)) {
          final body = msg.decodeTextPlainPart() ?? '';
          final otpMatch = RegExp(r'\b(\d{6})\b').firstMatch(body);
          if (otpMatch != null) {
            final otp = otpMatch.group(1)!;
            setState(() => _lastOtp = otp);
            await client.logout();
            return otp;
          }
        }
      }
      await client.logout();
      return null;
    } catch (e) {
      await client.logout().catchError((_) {});
      rethrow;
    }
  }

  Future<void> _callVerifyApi(String action, String otp) async {
    _log('Verifying OTP $otp with Control Server...', _LogLevel.info);
    final response = await http.post(
      Uri.parse(kVerifyApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'otp': otp, 'actionType': action}),
    );
    _log('Server Response: ${response.statusCode}', _LogLevel.info);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildStatusBadge(),
              const SizedBox(height: 20),
              _buildButtons(),
              const SizedBox(height: 20),
              _buildTerminal(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, color: Color(0xFF00FFB2), size: 28),
            const SizedBox(width: 10),
            Text('SHUTTER CONTROL', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white)),
          ],
        ),
        Text('ENCRYPTED GATEWAY v1.1', style: TextStyle(fontSize: 11, letterSpacing: 3, color: Colors.white.withOpacity(0.3))),
      ],
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF12121A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.amber : Colors.green),
            ),
          ),
          const SizedBox(width: 10),
          Text(_busy ? 'ACTIVE: POLLING GMAIL...' : 'SYSTEM IDLE', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(child: _ShutterBtn(label: 'ON', color: const Color(0xFF00FFB2), enabled: !_busy, onPressed: () => _onButtonPressed('ON'))),
        const SizedBox(width: 16),
        Expanded(child: _ShutterBtn(label: 'OFF', color: const Color(0xFFFF4C6E), enabled: !_busy, onPressed: () => _onButtonPressed('OFF'))),
      ],
    );
  }

  Widget _buildTerminal() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (_, i) {
            final log = _logs[i];
            return Text('[${log.timestamp}] ${log.message}', style: TextStyle(color: log.level == _LogLevel.error ? Colors.red : Colors.greenAccent, fontFamily: 'monospace', fontSize: 12));
          },
        ),
      ),
    );
  }
}

class _ShutterBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;
  const _ShutterBtn({required this.label, required this.color, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color.withOpacity(0.2), side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 20)),
      onPressed: enabled ? onPressed : null,
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
    );
  }
}
