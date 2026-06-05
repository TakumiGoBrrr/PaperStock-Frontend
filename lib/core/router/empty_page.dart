import 'package:flutter/material.dart';

class EmptyPage extends StatelessWidget {
  const EmptyPage({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SizedBox.expand(child: Center(child: Text(label ?? ''))),
      ),
    );
  }
}
