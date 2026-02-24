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
    // 1. Record the exact microsecond the button was pressed
    final DateTime requestStartTime = DateTime.now();
    
    setState(() {
      isBusy = true;
      status = "Starting $action...";
    });

    try {
      // 2. Initial API Call
      await http.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: jsonEncode({'action': action}),
      );

      String? foundOtp;
      int attempts = 0;
      const int maxAttempts = 12; 

      while (attempts < maxAttempts && foundOtp == null) {
        attempts++;
        setState(() => status = "Waiting for new email (Attempt $attempts/12)...");

        final client = ImapClient(isLogEnabled: false);
        try {
          await client.connectToServer('imap.gmail.com', 993, isSecure: true);
          await client.login('asadiraveendra021@gmail.com', 'iiwq aetl lmsg kkfe');
          await client.selectInbox();

          // Fetch only the most recent messages
          final fetchResult = await client.fetchRecentMessages(messageCount: 3);
          
          for (final message in fetchResult.messages) {
            final DateTime emailDate = message.decodeDate() ?? DateTime(2000);
            
            // CRITICAL: Only accept the email if it arrived AFTER the button press.
            // This makes it safe to receive "2025" if it's the actual new OTP.
            if (emailDate.isAfter(requestStartTime.subtract(const Duration(seconds: 2)))) {
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

        if (foundOtp == null) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }

      if (foundOtp != null) {
        setState(() => status = "New OTP Found: $foundOtp. Verifying...");
        await http.post(
          Uri.parse('https://jsonplaceholder.typicode.com/posts'),
          body: jsonEncode({'otp': foundOtp}),
        );
        setState(() => status = "Success! Shutter $action Verified with $foundOtp.");
      } else {
        setState(() => status = "No new email found within 2 minutes.");
      }
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
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18)),
            ),
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
