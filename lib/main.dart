import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'x509 Multicast Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MulticastHomePage(),
    );
  }
}

class MulticastHomePage extends StatefulWidget {
  const MulticastHomePage({super.key});

  @override
  State<MulticastHomePage> createState() => _MulticastHomePageState();
}

class _MulticastHomePageState extends State<MulticastHomePage> {
  static const methodChannel = MethodChannel('x509_multicast/methods');
  static const eventChannel = EventChannel('x509_multicast/events');

  final List<String> _messages = [];
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    eventChannel.receiveBroadcastStream().listen((event) {
      setState(() {
        _messages.insert(0, event.toString());
        if (_messages.length > 100) {
          _messages.removeLast();
        }
      });
    });
  }

  Future<void> _startService() async {
    try {
      final success = await methodChannel.invokeMethod<bool>('start');
      if (success == true) {
        setState(() => _isRunning = true);
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to start service: '${e.message}'.");
    }
  }

  Future<void> _stopService() async {
    try {
      final success = await methodChannel.invokeMethod<bool>('stop');
      if (success == true) {
        setState(() => _isRunning = false);
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to stop service: '${e.message}'.");
    }
  }

  Future<void> _sendPresence() async {
    try {
      await methodChannel.invokeMethod('sendPresence');
    } on PlatformException catch (e) {
      debugPrint("Failed to send presence: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('x509 UDP Multicast Client'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _startService,
                  child: const Text('Start'),
                ),
                ElevatedButton(
                  onPressed: _isRunning ? _stopService : null,
                  child: const Text('Stop'),
                ),
                ElevatedButton(
                  onPressed: _isRunning ? _sendPresence : null,
                  child: const Text('Broadcast Presence'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Status: ${_isRunning ? "Running" : "Stopped"}', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(_messages[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
