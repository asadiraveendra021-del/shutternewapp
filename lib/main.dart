import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:notification_listener_service/notification_listener_service.dart';

void main() => runApp(const MaterialApp(home: ShutterHomePage()));

class ShutterHomePage extends StatefulWidget {
  const ShutterHomePage({super.key});

  @override
  State<ShutterHomePage> createState() => _ShutterHomePageState();
}

class _ShutterHomePageState extends State<ShutterHomePage> {
  String status = "Ready";
  bool isBusy = false;
  List<String> liveLogs = [
    "System Booting...",
    "Establishing API Heartbeat..."
  ];
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _startListening();
    _startContinuousDataFetch();
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    super.dispose();
  }

  // ===============================
  // 🔐 REQUEST NOTIFICATION ACCESS
  // ===============================
  void _requestPermission() async {
    bool isGranted =
        await NotificationListenerService.isPermissionGranted();

    if (!isGranted) {
      await NotificationListenerService.openPermissionSettings();
    }
  }

  // ===============================
  // 📩 LISTEN FOR NOTIFICATIONS
  // ===============================
  void _startListening() {
    NotificationListenerService.notificationsStream.listen((event) {
      if (event == null) return;

      if (event.text != null) {
        String notificationText = event.text!.join(" ");

        RegExp otpRegex = RegExp(r'\b\d{4,6}\b');
        Match? match = otpRegex.firstMatch(notificationText);

        if (match != null) {
          String otp = match.group(0)!;

          setState(() {
            status = "OTP $otp Auto Read From Notification!";
            liveLogs.insert(
                0,
                "[${DateTime.now().toString().substring(11, 19)}] OTP DETECTED: $otp");

            if (liveLogs.length > 15) liveLogs.removeLast();
          });
        }
      }
    });
  }

  // ===============================
  // 🔄 DUMMY LOG FETCH
  // ===============================
  void _startContinuousDataFetch() {
    _logTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final response = await http.get(Uri.parse(
            'https://jsonplaceholder.typicode.com/posts/${(timer.tick % 20) + 1}'));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          setState(() {
            String time =
                DateTime.now().toString().substring(11, 19);

            liveLogs.insert(
                0,
                "[$time] DATA_STREAM: ${data['title'].toString().substring(0, 20)}...");

            if (liveLogs.length > 15) liveLogs.removeLast();
          });
        }
      } catch (e) {
        debugPrint("Heartbeat error: $e");
      }
    });
  }

  // ===============================
  // 🚀 BUTTON ACTION (NO EMAIL LOGIN)
  // ===============================
  Future<void> triggerAction(String action) async {
    setState(() {
      isBusy = true;
      status = "Sending request...";
    });

    try {
      await http.post(
        Uri.parse('https://jsonplaceholder.typicode.com/posts'),
        body: jsonEncode({'action': action}),
      );

      setState(() {
        status = "Waiting for OTP notification...";
      });
    } catch (e) {
      setState(() {
        status = "API Error!";
      });
    } finally {
      setState(() {
        isBusy = false;
      });
    }
  }

  // ===============================
  // 🎨 UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("System Dashboard"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _shutterTile("OPEN",
                  "https://www.shutterstock.com/image-vector/half-open-garage-door-on-260nw-2473923275.jpg",
                  "ON"),
              _shutterTile("CLOSE",
                  "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRJCwI_HbX7_13gTATZH-64yhrRrKEmQxh51g&s",
                  "OFF"),
            ],
          ),
          const SizedBox(height: 20),
          Text(status,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey)),
          const Divider(height: 40),
          const Text("LIVE SYSTEM LOGS",
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.grey)),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12)),
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: liveLogs.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    liveLogs[index],
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.green),
                  ),
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
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
