import 'package:flutter/material.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sync_rounded, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('Senkronizasyon', style: TextStyle(fontSize: 22, color: Colors.grey)),
        ],
      ),
    );
  }
}
