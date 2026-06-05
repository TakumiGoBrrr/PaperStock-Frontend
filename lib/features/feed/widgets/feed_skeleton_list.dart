import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class FeedSkeletonList extends StatelessWidget {
  const FeedSkeletonList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final base = colorScheme.surfaceContainerHighest;
    final highlight = colorScheme.surfaceContainerHigh;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) => const _PostCardSkeleton(),
      ),
    );
  }
}

class _PostCardSkeleton extends StatelessWidget {
  const _PostCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final fill = colorScheme.surfaceContainerHighest;

    Widget bar(
        {required double width, required double height, double radius = 8}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Card.filled(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            bar(width: 260, height: 22, radius: 10),
            const SizedBox(height: 12),
            bar(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            bar(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            bar(width: 220, height: 14),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                bar(width: 72, height: 28, radius: 999),
                bar(width: 84, height: 28, radius: 999),
                bar(width: 64, height: 28, radius: 999),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(child: bar(width: double.infinity, height: 14)),
                const SizedBox(width: 10),
                bar(width: 36, height: 36, radius: 999),
                const SizedBox(width: 6),
                bar(width: 36, height: 36, radius: 999),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
