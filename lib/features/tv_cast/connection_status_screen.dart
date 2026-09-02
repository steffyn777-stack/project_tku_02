import 'package:flutter/material.dart';
import 'socket_server_service.dart';

class ConnectionStatusScreen extends StatefulWidget {
  const ConnectionStatusScreen({super.key});

  @override
  State<ConnectionStatusScreen> createState() => _ConnectionStatusScreenState();
}

class _ConnectionStatusScreenState extends State<ConnectionStatusScreen> {
  final _serverService = SocketServerService();

  @override
  void initState() {
    super.initState();
    _serverService.addListener(_onServiceUpdate);
    _serverService.startServer();
  }

  @override
  void dispose() {
    _serverService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TV Connection Status',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Server Status: ${_serverService.status.name.toUpperCase()}',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text('IP Address: ${_serverService.ipAddress ?? "Loading..."}',
                style: const TextStyle(fontSize: 20)),
            Text('Port: ${_serverService.port}',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _serverService.isClientConnected
                    ? Colors.green
                    : Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _serverService.isClientConnected
                    ? 'Phone Connected: YES'
                    : 'Phone Connected: NO',
                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            if (_serverService.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Error: ${_serverService.errorMessage}',
                    style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            StreamBuilder<Map<String, dynamic>>(
              stream: _serverService.messages,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text('Last Command: ${snapshot.data}');
                }
                return const Text('Waiting for commands...');
              },
            ),
          ],
        ),
      ),
    );
  }
}