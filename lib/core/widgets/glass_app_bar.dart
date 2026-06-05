import 'package:flutter/material.dart';

import 'app_header.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.left,
    this.right,
  });

  final Widget title;
  final Widget? left;
  final Widget? right;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: AppHeader(title: title, left: left, right: right),
      ),
    );
  }
}
