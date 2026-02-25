import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:google_sign_in/google_sign_in.dart'; // New Import
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
  List<String> liveLogs = ["System Booting...", "Establishing API Heartbeat..."];
  Timer? _logTimer;

  // Configure Google Sign In with Mail Read scope
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://mail.google.com/'], 
  );

  @override
  void initState() {
    super.initState();
    _startContinuousDataFetch(); // Dummy data caller
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    super.dispose();
  }

  // CONTINUOUS LOG FETCH (DUMMY API)
  void _startContinuousDataFetch() {
    _logTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        // Fetching random data to simulate a live sensor/log feed
        final response = await http.get(Uri.parse('https://jsonplaceholder.typicode.com/posts/${(timer.tick % 20) + 1}'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            String time = DateTime.now().toString().substring(11, 19);
            liveLogs.insert(0, "[$time] DATA_STREAM: ${data['title'].toString().substring(0, 20)}...");
            if (liveLogs.length > 15) liveLogs.removeLast();
          });
        }
      } catch (e) {
        debugPrint("Heartbeat error: $e");
      }
    });
  }

  Future<void> triggerAction(String action) async {
    const String targetEmail = 'asadiraveendra021@gmail.com'; // Fixed Static Email
    final DateTime requestStartTime = DateTime.now();
    
    setState(() { isBusy = true; status = "Connecting to $targetEmail..."; });

    try {
      // 1. Authenticate (This pop-up only happens once)
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      // Safety Check: Ensure the user logged into the CORRECT static email
      if (account == null || account.email != targetEmail) {
        setState(() => status = "Error: Please login as $targetEmail");
        await _googleSignIn.signOut(); // Force logout if it's the wrong account
        isBusy = false;
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? accessToken = auth.accessToken;

      // 2. Your API Call
      await http.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: jsonEncode({'action': action, 'email': targetEmail}),
      );

      // 3. The Search Loop (Same as your working version)
      String? foundOtp;
      int attempts = 0;
      while (attempts < 12 && foundOtp == null) {
        attempts++;
        setState(() => status = "Scanning Inbox (Attempt $attempts/12)...");

        final client = ImapClient(isLogEnabled: false);
        try {
          await client.connectToServer('imap.gmail.com', 993, isSecure: true);
          
          // Authenticate using the Token instead of Password
          await client.authenticateWithOAuth2(targetEmail, accessToken!);
          
          await client.selectInbox();
          final fetchResult = await client.fetchRecentMessages(messageCount: 3);
          
          for (final message in fetchResult.messages) {
            final DateTime emailDate = message.decodeDate() ?? DateTime(2000);
            if (emailDate.isAfter(requestStartTime.subtract(const Duration(seconds: 5)))) {
              final body = message.decodeTextPlainPart() ?? "";
              final otpMatch = RegExp(r'\b\d{4,6}\b').firstMatch(body);
              if (otpMatch != null) {
                foundOtp = otpMatch.group(0);
                break;
              }
            }
          }
        } finally {
          await client.logout();
        }
        if (foundOtp == null) await Future.delayed(const Duration(seconds: 10));
      }

      if (foundOtp != null) {
        setState(() => status = "OTP $foundOtp Found! Shutter $action.");
      } else {
        setState(() => status = "Timeout: No new OTP found.");
      }
    } catch (e) {
      setState(() => status = "Auth Error: Check IMAP settings.");
    } finally {
      setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text("System Dashboard"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 1),
      body: Column(
        children: [
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _shutterTile("OPEN", "https://www.shutterstock.com/image-vector/half-open-garage-door-on-260nw-2473923275.jpg", "ON"),
              _shutterTile("CLOSE", "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRJCwI_HbX7_13gTATZH-64yhrRrKEmQxh51g&s", "OFF"),
            ],
          ),
          const SizedBox(height: 20),
          Text(status, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const Divider(height: 40),
          const Text("LIVE SYSTEM LOGS", style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: Colors.grey)),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: liveLogs.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(liveLogs[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.green)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shutterTile(String label, String url, String action) {
    return InkWell(
      onTap: isBusy ? null : () => triggerAction(action),
      child: Column(
        children: [
          Image.network(url, width: 140, height: 140),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
