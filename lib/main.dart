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

  Future<void> triggerAction(String action) async {
    setState(() { isBusy = true; status = "Starting $action..."; });
    
    try {
      // 1. Call your API
      final url = action == "ON" 
          ? 'https://jsonplaceholder.typicode.com/posts' 
          : 'https://jsonplaceholder.typicode.com/posts';
          
      await http.post(Uri.parse(url), body: jsonEncode({'action': action}));
      
      // 2. Check Email for OTP
      setState(() => status = "Checking Gmail for OTP...");
      final client = ImapClient(isLogEnabled: false);
      await client.connectToServer('imap.gmail.com', 993, isSecure: true);
      await client.login('asadiraveendra021@gmail.com', 'iiwq aetl lmsg kkfe');
      await client.selectInbox();

      // This version is more compatible with Gmail's specific IMAP rules
      final fetchResult = await client.fetchRecentMessages(messageCount: 5);
      if (fetchResult.messages.isNotEmpty) {
        final body = fetchResult.messages.first.decodeTextPlainPart() ?? "";
        final otpMatch = RegExp(r'\b\d{6}\b').firstMatch(body);
        if (otpMatch != null) {
          setState(() => status = "Success! Found OTP: ${otpMatch.group(0)}");
        } else {
          setState(() => status = "Action sent, but no OTP found in email.");
        }
      }
      await client.logout();
    } catch (e) {
      setState(() => status = "Error: $e");
    } finally {
      setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("SHUTTER CONTROL"), backgroundColor: Colors.teal),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(status, style: const TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: isBusy ? null : () => triggerAction("ON"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(200, 60)),
              child: const Text("SHUTTER ON"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isBusy ? null : () => triggerAction("OFF"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(200, 60)),
              child: const Text("SHUTTER OFF"),
            ),
          ],
        ),
      ),
    );
  }
}
