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
    setState(() {
      isBusy = true;
      status = "Starting $action...";
    });

    try {
      // 1. Initial API Call
      await http.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: jsonEncode({'action': action}),
      );

      // 2. Start the Polling Loop (Wait up to 2 minutes)
      String? foundOtp;
      int attempts = 0;
      const int maxAttempts = 12; // 12 * 10 seconds = 120 seconds total

      while (attempts < maxAttempts && foundOtp == null) {
        attempts++;
        setState(() => status = "Checking Gmail (Attempt $attempts/$maxAttempts)...");

        final client = ImapClient(isLogEnabled: false);
        try {
          await client.connectToServer('imap.gmail.com', 993, isSecure: true);
          await client.login('asadiraveendra021@gmail.com', 'iiwq aetl lmsg kkfe');
          await client.selectInbox();

          // Fetch latest 5 messages
          final fetchResult = await client.fetchRecentMessages(messageCount: 5);
          for (final message in fetchResult.messages) {
            final body = message.decodeTextPlainPart() ?? "";
            
            // ADJUSTED: This now looks for any number between 4 and 6 digits long
            final otpMatch = RegExp(r'\b\d{4,6}\b').firstMatch(body);

            if (otpMatch != null) {
              foundOtp = otpMatch.group(0);
              break;
            }
          }
        } finally {
          await client.logout();
        }

        if (foundOtp == null) {
          // Wait 10 seconds before the next check
          await Future.delayed(const Duration(seconds: 10));
        }
      }

      // 3. Final Result Handling
      if (foundOtp != null) {
        setState(() => status = "OTP Found: $foundOtp. Verifying...");

        // Trigger Dummy Verify API
        await http.post(
          Uri.parse('https://jsonplaceholder.typicode.com/posts'),
          body: jsonEncode({'otp': foundOtp}),
        );

        setState(() => status = "Success! Shutter $action Verified.");
      } else {
        setState(() => status = "Timeout: No OTP arrived after 2 minutes.");
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
      appBar: AppBar(
        title: const Text("SHUTTER CONTROL"),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: isBusy ? null : () => triggerAction("ON"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(200, 60),
              ),
              child: const Text("SHUTTER ON"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isBusy ? null : () => triggerAction("OFF"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size(200, 60),
              ),
              child: const Text("SHUTTER OFF"),
            ),
          ],
        ),
      ),
    );
  }
}
