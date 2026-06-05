import 'profile_screen.dart';
import 'package:flutter/material.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProfileScreen(
      userId: 'me',
      showTopHeader: false,
      showBackButton: false,
    );
  }
}
