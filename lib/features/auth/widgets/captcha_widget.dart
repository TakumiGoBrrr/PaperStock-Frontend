import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CaptchaImage extends StatelessWidget {
  const CaptchaImage({
    super.key,
    required this.text,
    required this.seed,
  });

  final String text;
  final int seed;

  String? _tryDecodeSvgString(String image) {
    final raw = image.trim();
    if (raw.isEmpty) return null;

    // Backend format: "data:image/svg+xml;base64,XXXX"
    if (raw.startsWith('data:image/svg+xml;base64,')) {
      try {
        final base64Str = raw.split(',').last;
        final svgString = utf8.decode(base64Decode(base64Str));
        return svgString.trim().isEmpty ? null : svgString;
      } catch (_) {
        return null;
      }
    }

    // Support direct inline SVG (useful for local/dev fallbacks).
    if (raw.startsWith('<svg') || raw.contains('<svg')) {
      return raw;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final raw = text.trim();
    final bg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);

    Widget content;

    if (raw.isEmpty) {
      content = ColoredBox(
        color: bg,
        child: const Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      final svgString = _tryDecodeSvgString(raw);
      if (svgString != null) {
        content = ColoredBox(
          color: bg,
          child: SvgPicture.string(
            svgString,
            key: ValueKey<String>(raw),
            fit: BoxFit.cover,
          ),
        );
      } else {
        // Fallback for locally generated captcha text.
        content = CustomPaint(
          painter: _CaptchaPainter(
            text: raw,
            seed: seed,
            foreground: colorScheme.onSurface.withValues(alpha: 0.85),
            noise: colorScheme.onSurface.withValues(alpha: 0.14),
            background: bg,
          ),
          child: const SizedBox.expand(),
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 56,
        width: 140,
        child: content,
      ),
    );
  }
}

class _CaptchaPainter extends CustomPainter {
  _CaptchaPainter({
    required this.text,
    required this.seed,
    required this.foreground,
    required this.noise,
    required this.background,
  });

  final String text;
  final int seed;
  final Color foreground;
  final Color noise;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);

    final bgPaint = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Noise lines.
    final linePaint = Paint()
      ..color = noise
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 10; i++) {
      final p1 =
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      final p2 =
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      canvas.drawLine(p1, p2, linePaint);
    }

    // Noise dots.
    final dotPaint = Paint()..color = noise.withValues(alpha: 0.7);
    for (var i = 0; i < 50; i++) {
      final p =
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      canvas.drawCircle(p, r.nextDouble() * 1.6 + 0.6, dotPaint);
    }

    // Captcha text.
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 3.2,
          color: foreground,
        ),
      ),
    )..layout();

    final baseOffset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );

    // Slight per-character jitter.
    final chars = text.split('');
    var dx = baseOffset.dx;
    for (final c in chars) {
      final charPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: c,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.2,
            color: foreground,
          ),
        ),
      )..layout();

      final jitter = Offset(
        (r.nextDouble() - 0.5) * 2.6,
        (r.nextDouble() - 0.5) * 2.6,
      );

      charPainter.paint(canvas, Offset(dx, baseOffset.dy) + jitter);
      dx += charPainter.width + 3.2;
    }
  }

  @override
  bool shouldRepaint(covariant _CaptchaPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.seed != seed;
  }
}
