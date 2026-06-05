import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.left,
    this.right,
    this.height = 44,
  });

  final Widget title;
  final Widget? left;
  final Widget? right;

  /// Total height of the header box. Defaults to 44.
  /// Pass a smaller value (e.g. 40) to get a more compact toolbar.
  final double height;

  @override
  Widget build(BuildContext context) {
    // Keep 6 px bottom padding so the content doesn't hug the very bottom.
    final bottomPad = height >= 40 ? 6.0 : 4.0;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Center(child: title),
            if (left != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: left,
                ),
              ),
            if (right != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: right,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
