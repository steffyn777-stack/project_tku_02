import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum ServerStatus { stopped, starting, running, error }

class SocketServerService extends ChangeNotifier {
  static final SocketServerService _instance = SocketServerService._internal();
  factory SocketServerService() => _instance;
  SocketServerService._internal();

  ServerSocket? _server;
  Socket? _clientSocket;
  ServerStatus _status = ServerStatus.stopped;
  String? _ipAddress;
  final int _port = 4040;
  String? _errorMessage;

  ServerStatus get status => _status;
  String? get ipAddress => _ipAddress;
  int get port => _port;
  bool get isClientConnected => _clientSocket != null;
  String? get errorMessage => _errorMessage;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _binaryController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get binaryMessages => _binaryController.stream;

  Future<void> startServer() async {
    if (_status == ServerStatus.running) return;

    _status = ServerStatus.starting;
    notifyListeners();

    try {
      _ipAddress = await _getIpAddress();
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      _status = ServerStatus.running;
      _errorMessage = null;
      notifyListeners();

      _server!.listen((Socket client) {
        if (_clientSocket != null) {
          client.destroy(); // Accept only one client
          return;
        }
        _handleClient(client);
      });
    } catch (e) {
      _status = ServerStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopServer() async {
    await _clientSocket?.close();
    await _server?.close();
    _clientSocket = null;
    _server = null;
    _status = ServerStatus.stopped;
    _ipAddress = null;
    notifyListeners();
  }

  void _handleClient(Socket client) {
    _clientSocket = client;
    notifyListeners();

    final List<int> buffer = [];

    client.listen(
      (data) {
        buffer.addAll(data);
        _processBuffer(buffer);
      },
      onDone: () {
        _clientSocket = null;
        notifyListeners();
      },
      onError: (error) {
        _clientSocket = null;
        notifyListeners();
      },
    );
  }

  void _processBuffer(List<int> buffer) {
    while (buffer.length >= 5) {
      // Read length prefix (32-bit big endian)
      final int length =
          (buffer[0] << 24) | (buffer[1] << 16) | (buffer[2] << 8) | buffer[3];

      if (buffer.length < 4 + length) {
        // Wait for more data
        break;
      }

      // Read type flag (1 byte)
      final int type = buffer[4];

      // Extract message data
      final payloadData = buffer.sublist(5, 4 + length);
      buffer.removeRange(0, 4 + length);

      try {
        if (type == 0x01) {
          // JSON
          final message = utf8.decode(payloadData);
          final Map<String, dynamic> json = jsonDecode(message);
          _messageController.add(json);
        } else if (type == 0x02) {
          // Binary
          _binaryController.add(Uint8List.fromList(payloadData));
        }
      } catch (e) {
        debugPrint('Error parsing message from client: $e');
      }
    }
  }

  Future<String?> _getIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      debugPrint(
          'Found network interfaces: ${interfaces.map((i) => i.name).toList()}');

      // 1. Try to find Wi-Fi or Ethernet interfaces first
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('en') ||
            name.contains('eth')) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              debugPrint(
                  'Selected IP from priority interface (${interface.name}): ${addr.address}');
              return addr.address;
            }
          }
        }
      }

      // 2. Fallback to any non-loopback IPv4 address
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            debugPrint(
                'Selected IP from fallback interface (${interface.name}): ${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting IP address: $e');
    }
    return null;
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_clientSocket != null) {
      try {
        final encoded = utf8.encode(jsonEncode(message));
        final length = encoded.length + 1; // +1 for type flag

        // Write length prefix (4 bytes)
        final header = Uint8List(5);
        header[0] = (length >> 24) & 0xFF;
        header[1] = (length >> 16) & 0xFF;
        header[2] = (length >> 8) & 0xFF;
        header[3] = length & 0xFF;
        header[4] = 0x01; // JSON flag

        _clientSocket!.add(header);
        _clientSocket!.add(encoded);
      } catch (e) {
        debugPrint('Error sending message to client: $e');
      }
    }
  }

  void sendBinary(Uint8List data) {
    if (_clientSocket != null) {
      try {
        final length = data.length + 1; // +1 for type flag

        final header = Uint8List(5);
        header[0] = (length >> 24) & 0xFF;
        header[1] = (length >> 16) & 0xFF;
        header[2] = (length >> 8) & 0xFF;
        header[3] = length & 0xFF;
        header[4] = 0x02; // Binary flag

        _clientSocket!.add(header);
        _clientSocket!.add(data);
      } catch (e) {
        debugPrint('Error sending binary to client: $e');
      }
    }
  }

  @override
  void dispose() {
    stopServer();
    _messageController.close();
    _binaryController.close();
    super.dispose();
  }
}