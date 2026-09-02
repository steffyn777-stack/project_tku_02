import 'package:flutter/material.dart';
import 'socket_client_service.dart';

class PhoneConnectionScreen extends StatefulWidget {
  const PhoneConnectionScreen({super.key});

  @override
  State<PhoneConnectionScreen> createState() => _PhoneConnectionScreenState();
}

class _PhoneConnectionScreenState extends State<PhoneConnectionScreen> {
  final _clientService = SocketClientService();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '4040');

  @override
  void initState() {
    super.initState();
    _clientService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _clientService.removeListener(_onServiceUpdate);
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _connect() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4040;
    if (ip.isNotEmpty) {
      _clientService.connect(ip, port);
    }
  }

  void _disconnect() {
    _clientService.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '連線至 TV',
                      style: TextStyle(
                        color: Color(0xFF1A1D2E),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '請輸入 TV 顯示的 IP 位址以建立控制連線',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    _buildInputCard(),
                    const SizedBox(height: 32),
                    _buildStatusCard(),
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                    if (_clientService.errorMessage != null) _buildErrorCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF374151), size: 16),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE0F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TV IP 位址',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ipController,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: '例如: 192.168.1.150',
              prefixIcon: const Icon(Icons.tv_rounded),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 20),
          const Text(
            '通訊埠 (Port)',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _portController,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.settings_input_component,
                color: Color(0xFF6B7280),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final isConnected = _clientService.isConnected;
    final statusColor = isConnected ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '連線狀態: ',
            style: TextStyle(
                color: statusColor.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600),
          ),
          Text(
            _clientService.status.name.toUpperCase(),
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final isConnecting = _clientService.status == ClientStatus.connecting;
    final isConnected = _clientService.isConnected;

    return Column(
      children: [
        GestureDetector(
          onTap: isConnecting || isConnected ? null : _connect,
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              gradient: isConnecting || isConnected
                  ? null
                  : const LinearGradient(
                      colors: [Color(0xFF4A65FF), Color(0xFF6B82FF)]),
              color:
                  isConnecting || isConnected ? const Color(0xFFEDEFF7) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: isConnecting
                  ? const CircularProgressIndicator(color: Color(0xFF4A65FF))
                  : Text(
                      isConnected ? '連線成功' : '開始連線',
                      style: TextStyle(
                        color: isConnecting || isConnected
                            ? const Color(0xFFB0B3C5)
                            : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
        if (isConnected) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _disconnect,
            child: Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDDE0F0)),
              ),
              child: const Center(
                child: Text(
                  '中斷連線',
                  style: TextStyle(
                    color: Color(0xFFFF4B4B),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _clientService.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}