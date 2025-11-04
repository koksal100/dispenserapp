import 'package:flutter/material.dart';

class RelativesScreen extends StatelessWidget {
  const RelativesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_rounded, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('Yakınlarım', style: TextStyle(fontSize: 22, color: Colors.grey)),
        ],
      ),
    );
  }
}
