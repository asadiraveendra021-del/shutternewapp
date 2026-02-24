import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────
//  CONFIG — change these to suit your setup
// ─────────────────────────────────────────────
const String kEmail = 'asadiraveendra021@gmail.com';
const String kAppPassword = 'iiwq aetl lmsg kkfe';
const String kImapHost = 'imap.gmail.com';
const int kImapPort = 993;
const String kSenderFilter = 'ravindraravi86814@gmail.com';

// Trigger API — a harmless free endpoint used as a placeholder
const String kTriggerApiUrl = 'https://jsonplaceholder.typicode.com/posts';
// Verify API — replace with your real URL
const String kVerifyApiUrl = 'https://jsonplaceholder.typicode.com/posts';

const int kPollIntervalSeconds = 5;
const int kMaxPollAttempts = 24; // 24 × 5 s = 2 min timeout
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

// ─────────────────────────────────────────────
//  Home Page
// ─────────────────────────────────────────────
class ShutterHomePage extends StatefulWidget {
  const ShutterHomePage({super.key});

  @override
  State<ShutterHomePage> createState() => _ShutterHomePageState();
}

class _ShutterHomePageState extends State<ShutterHomePage>
    with SingleTickerProviderStateMixin {
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
    _log('Waiting for action...', _LogLevel.info);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Logging ──────────────────────────────────
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
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  // ── Main Flow ─────────────────────────────────
  Future<void> _onButtonPressed(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _action = action;
      _lastOtp = null;
      _logs.clear();
    });
    _log('► Action: $action pressed', _LogLevel.info);

    try {
      // Step 1 — Trigger API
      await _callTriggerApi(action);

      // Step 2/3/4 — Poll Gmail for OTP
      final otp = await _pollForOtp();

      if (otp == null) {
        _log('✗ Timed out — no OTP found.', _LogLevel.error);
        setState(() => _busy = false);
        return;
      }

      // Step 5 — Verify API
      await _callVerifyApi(action, otp);

      // Step 6 — Done
      _log('✓ Success! OTP $otp verified for $action.', _LogLevel.success);
    } catch (e) {
      _log('✗ Error: $e', _LogLevel.error);
    } finally {
      _pollTimer?.cancel();
      setState(() => _busy = false);
    }
  }

  // Step 1
  Future<void> _callTriggerApi(String action) async {
    _log('Calling trigger API...', _LogLevel.info);
    final response = await http.post(
      Uri.parse(kTriggerApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    _log(
      'Trigger API → HTTP ${response.statusCode}',
      response.statusCode == 201 || response.statusCode == 200
          ? _LogLevel.success
          : _LogLevel.warning,
    );
  }

  // Steps 2‑4 — Poll loop
  Future<String?> _pollForOtp() async {
    _pollCount = 0;
    final completer = Completer<String?>();

    _pollTimer = Timer.periodic(
      const Duration(seconds: kPollIntervalSeconds),
      (timer) async {
        _pollCount++;
        _log(
          'Searching email... (attempt $_pollCount/$kMaxPollAttempts)',
          _LogLevel.info,
        );

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
          _log('IMAP error: $e', _LogLevel.error);
          timer.cancel();
          completer.complete(null);
        }
      },
    );

    // Also run once immediately (don't wait for first tick)
    _log(
      'Searching email... (attempt 0/$kMaxPollAttempts)',
      _LogLevel.info,
    );
    try {
      final otp = await _fetchLatestOtp();
      if (otp != null) {
        _pollTimer?.cancel();
        return otp;
      }
    } catch (_) {}

    return completer.future;
  }

  Future<String?> _fetchLatestOtp() async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        kImapHost,
        kImapPort,
        isSecure: true,
      );
      await client.login(kEmail, kAppPassword);
      await client.selectInbox();

      // Search for emails from the sender
      final searchResult = await client.searchMessages(
        SearchQueryBuilder.from(
          kSenderFilter,
          SearchQueryType.recent,
        ),
      );

      if (searchResult.isEmpty) {
        await client.logout();
        return null;
      }

      // Fetch the most recent matching message
      final sequence = MessageSequence.fromIds(
        [searchResult.last],
        isUid: true,
      );
      final fetchResult = await client.fetchMessages(
        sequence,
        '(UID BODY[TEXT] BODY[HEADER.FIELDS (FROM DATE)])',
        isUidFetch: true,
      );

      await client.logout();

      if (fetchResult.messages.isEmpty) return null;

      final msg = fetchResult.messages.last;
      final body = msg.decodeTextPlainPart() ??
          msg.decodeTextHtmlPart() ??
          '';

      _log('Email body snippet: ${body.substring(0, body.length.clamp(0, 80))}...', _LogLevel.info);

      // Extract 6-digit OTP
      final otpMatch = RegExp(r'\b(\d{6})\b').firstMatch(body);
      if (otpMatch != null) {
        final otp = otpMatch.group(1)!;
        setState(() => _lastOtp = otp);
        _log('🔑 OTP Found: $otp', _LogLevel.success);
        return otp;
      }

      return null;
    } catch (e) {
      await client.logout().catchError((_) {});
      rethrow;
    }
  }

  // Step 5
  Future<void> _callVerifyApi(String action, String otp) async {
    _log('Calling verify API with OTP $otp...', _LogLevel.info);
    final response = await http.post(
      Uri.parse(kVerifyApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'otp': otp, 'actionType': action}),
    );
    _log(
      'Verify API → HTTP ${response.statusCode}',
      response.statusCode == 200 || response.statusCode == 201
          ? _LogLevel.success
          : _LogLevel.warning,
    );
  }

  // ─────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────
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
            const Icon(
              Icons.camera_outlined,
              color: Color(0xFF00FFB2),
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              'SHUTTER CONTROL',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: const Color(0xFF00FFB2).withOpacity(0.6),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'OTP GATEWAY v1.0',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 3,
            color: Colors.white.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
    Color dotColor;
    String statusText;

    if (_busy) {
      dotColor = const Color(0xFFFFCC00);
      statusText = 'Processing $_action...';
    } else if (_lastOtp != null) {
      dotColor = const Color(0xFF00FFB2);
      statusText = 'OTP $_lastOtp — $_action Verified ✓';
    } else {
      dotColor = Colors.white24;
      statusText = 'Ready';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy
                    ? dotColor.withOpacity(0.4 + 0.6 * _pulseController.value)
                    : dotColor,
                boxShadow: _busy
                    ? [
                        BoxShadow(
                          color: dotColor.withOpacity(0.6),
                          blurRadius: 8 * _pulseController.value,
                        )
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: _ShutterButton(
            label: 'ON',
            icon: Icons.power_settings_new,
            color: const Color(0xFF00FFB2),
            enabled: !_busy,
            onPressed: () => _onButtonPressed('ON'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _ShutterButton(
            label: 'OFF',
            icon: Icons.power_off_outlined,
            color: const Color(0xFFFF4C6E),
            enabled: !_busy,
            onPressed: () => _onButtonPressed('OFF'),
          ),
        ),
      ],
    );
  }

  Widget _buildTerminal() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF06060C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00FFB2).withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Terminal title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F1A),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(
                  bottom: BorderSide(
                      color: const Color(0xFF00FFB2).withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  _dot(const Color(0xFFFF5F57)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFFFFBD2E)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFF28CA41)),
                  const SizedBox(width: 12),
                  Text(
                    'terminal — shutter_log',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.3),
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _logs.clear()),
                    child: Text(
                      'clear',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.25),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Log lines
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                itemCount: _logs.length,
                reverse: false,
                itemBuilder: (_, i) => _buildLogLine(_logs[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _buildLogLine(_LogEntry entry) {
    Color textColor;
    String prefix;
    switch (entry.level) {
      case _LogLevel.success:
        textColor = const Color(0xFF00FFB2);
        prefix = '✓';
        break;
      case _LogLevel.error:
        textColor = const Color(0xFFFF4C6E);
        prefix = '✗';
        break;
      case _LogLevel.warning:
        textColor = const Color(0xFFFFCC00);
        prefix = '⚠';
        break;
      case _LogLevel.info:
      default:
        textColor = Colors.white60;
        prefix = '›';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '[${entry.timestamp}] ',
              style: TextStyle(color: Colors.white.withOpacity(0.2)),
            ),
            TextSpan(
              text: '$prefix ',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: entry.message,
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Reusable Button Widget
// ─────────────────────────────────────────────
class _ShutterButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _ShutterButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final opacity = widget.enabled ? 1.0 : 0.35;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Opacity(
          opacity: opacity,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: widget.color.withOpacity(0.08),
              border: Border.all(
                color: widget.color.withOpacity(_pressed ? 0.9 : 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(_pressed ? 0.3 : 0.1),
                  blurRadius: _pressed ? 24 : 12,
                  spreadRadius: _pressed ? 2 : 0,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: widget.color, size: 30),
                const SizedBox(height: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Models
// ─────────────────────────────────────────────
enum _LogLevel { info, success, warning, error }

class _LogEntry {
  final String timestamp;
  final String message;
  final _LogLevel level;
  _LogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });
}
