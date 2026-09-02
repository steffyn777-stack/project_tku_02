// lib/widgets/pi_ip_dialog.dart
import 'package:flutter/material.dart';

Future<String?> showPiIpDialog(BuildContext context, {String? initialIp}) {
  final controller = TextEditingController(text: initialIp ?? '192.168.0.103');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('連接樹莓派鏡頭'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: '樹莓派 IP 位址',
          hintText: '例如 192.168.0.103',
        ),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('連線'),
        ),
      ],
    ),
  );
}