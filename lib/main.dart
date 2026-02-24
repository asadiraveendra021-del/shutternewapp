import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MaterialApp(home: ShutterHomePage()));

class ShutterHomePage extends StatefulWidget {
  const ShutterHomePage({super.key});
  @override
  State<ShutterHomePage> createState() => _ShutterHomePageState();
}

class _ShutterHomePageState extends State<ShutterHomePage> {
  String status = "Ready";
  bool isBusy = false;
  List<String> liveLogs = ["Initializing system...", "Waiting for connection..."];
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    // Start fetching "Live Logs" every 10 seconds
    _startLiveLogs();
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    super.dispose();
  }

  // Dummy API fetch for the Live Log box
  Future<void> _startLiveLogs() async {
    _logTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final response = await http.get(Uri.parse('https://jsonplaceholder.typicode.com/posts/${timer.tick % 10 + 1}'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            String timestamp = DateTime.now().toString().substring(11, 19);
            liveLogs.insert(0, "[$timestamp] System Status: ${data['title'].toString().substring(0, 15)}...");
            if (liveLogs.length > 10) liveLogs.removeLast();
          });
        }
      } catch (e) {
        debugPrint("Log fetch error: $e");
      }
    });
  }

  // YOUR EXISTING WORKING FUNCTIONALITY (Unchanged)
  Future<void> triggerAction(String action) async {
    final DateTime requestStartTime = DateTime.now();
    setState(() { isBusy = true; status = "Starting $action..."; });

    try {
      await http.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: jsonEncode({'action': action}),
      );

      String? foundOtp;
      int attempts = 0;
      while (attempts < 12 && foundOtp == null) {
        attempts++;
        setState(() => status = "Waiting for email (Attempt $attempts/12)...");
        final client = ImapClient(isLogEnabled: false);
        try {
          await client.connectToServer('imap.gmail.com', 993, isSecure: true);
          await client.login('asadiraveendra021@gmail.com', 'iiwq aetl lmsg kkfe');
          await client.selectInbox();
          final fetchResult = await client.fetchRecentMessages(messageCount: 3);
          for (final message in fetchResult.messages) {
            final DateTime emailDate = message.decodeDate() ?? DateTime(2000);
            if (emailDate.isAfter(requestStartTime.subtract(const Duration(seconds: 2)))) {
              final body = message.decodeTextPlainPart() ?? "";
              final otpMatch = RegExp(r'\b\d{4,6}\b').firstMatch(body);
              if (otpMatch != null) { foundOtp = otpMatch.group(0); break; }
            }
          }
        } finally { await client.logout(); }
        if (foundOtp == null) await Future.delayed(const Duration(seconds: 10));
      }

      if (foundOtp != null) {
        setState(() => status = "OTP Found: $foundOtp. Verifying...");
        await http.post(Uri.parse('https://jsonplaceholder.typicode.com/posts'), body: jsonEncode({'otp': foundOtp}));
        setState(() => status = "Success! Shutter $action Verified.");
      } else {
        setState(() => status = "No new email found within 2 minutes.");
      }
    } catch (e) {
      setState(() => status = "Error: $e");
    } finally { setState(() => isBusy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0), // Light grey background like your reference
      appBar: AppBar(
        title: const Text("Control the Shutter", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 1. Image-based Shutter Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildShutterButton("Open Shutter", "https://img.icons8.com/plasticine/200/window.png", "ON"),
              _buildShutterButton("Close Shutter", "https://img.icons8.com/plasticine/200/blind.png", "OFF"),
            ],
          ),
          const SizedBox(height: 30),
          // 2. Status Text
          Text(status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
          const Spacer(),
          // 3. Live Log Window (as seen in image_612432.png)
          Container(
            margin: const EdgeInsets.all(15),
            padding: const EdgeInsets.all(10),
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              itemCount: liveLogs.length,
              itemBuilder: (context, index) => Text(
                liveLogs[index],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildShutterButton(String label, String imgUrl, String action) {
    return GestureDetector(
      onTap: isBusy ? null : () => triggerAction(action),
      child: Column(
        children: [
          Opacity(
            opacity: isBusy ? 0.5 : 1.0,
            child: Image.network(imgUrl, width: 120, height: 120, fit: BoxFit.contain),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
