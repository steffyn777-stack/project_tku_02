import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum ClientStatus { disconnected, connecting, connected, error }

class SocketClientService extends ChangeNotifier {
  static final SocketClientService _instance = SocketClientService._internal();
  factory SocketClientService() => _instance;
  SocketClientService._internal();

  Socket? _socket;
  ClientStatus _status = ClientStatus.disconnected;
  String? _errorMessage;

  ClientStatus get status => _status;
  bool get isConnected => _status == ClientStatus.connected;
  String? get errorMessage => _errorMessage;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _binaryController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get binaryMessages => _binaryController.stream;

  Future<void> connect(String ip, int port) async {
    if (_status == ClientStatus.connecting || _status == ClientStatus.connected)
      return;

    _status = ClientStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      _socket =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _status = ClientStatus.connected;
      notifyListeners();

      final List<int> buffer = [];

      _socket!.listen(
        (data) {
          buffer.addAll(data);
          _processBuffer(buffer);
        },
        onDone: () {
          disconnect();
        },
        onError: (error) {
          _status = ClientStatus.error;
          _errorMessage = error.toString();
          disconnect();
        },
      );
    } catch (e) {
      _status = ClientStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
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
        debugPrint('Error parsing message from server: $e');
      }
    }
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _status = ClientStatus.disconnected;
    notifyListeners();
  }

  void sendCommand(Map<String, dynamic> command) {
    if (_socket != null && _status == ClientStatus.connected) {
      try {
        final encoded = utf8.encode(jsonEncode(command));
        final length = encoded.length + 1; // +1 for type flag

        // Write length prefix (4 bytes)
        final header = Uint8List(5);
        header[0] = (length >> 24) & 0xFF;
        header[1] = (length >> 16) & 0xFF;
        header[2] = (length >> 8) & 0xFF;
        header[3] = length & 0xFF;
        header[4] = 0x01; // JSON flag

        _socket!.add(header);
        _socket!.add(encoded);
      } catch (e) {
        debugPrint('Error sending command to server: $e');
      }
    }
  }

  void sendBinary(Uint8List data) {
    if (_socket != null && _status == ClientStatus.connected) {
      try {
        final length = data.length + 1; // +1 for type flag

        final header = Uint8List(5);
        header[0] = (length >> 24) & 0xFF;
        header[1] = (length >> 16) & 0xFF;
        header[2] = (length >> 8) & 0xFF;
        header[3] = length & 0xFF;
        header[4] = 0x02; // Binary flag

        _socket!.add(header);
        _socket!.add(data);
      } catch (e) {
        debugPrint('Error sending binary to server: $e');
      }
    }
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    _binaryController.close();
    super.dispose();
  }
}