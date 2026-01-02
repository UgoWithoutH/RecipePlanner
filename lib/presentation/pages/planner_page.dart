import 'package:flutter/material.dart';

class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planner'),
        backgroundColor: Colors.blue,
      ),
      body: const Center(
        child: Text(
          'Planner Page',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}