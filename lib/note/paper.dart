import 'dart:math';

import 'package:flutter/material.dart';

/// The colours of a sticky note, in light and dark themes.
class NoteColors {
  final Color paper;
  final Color ink;
  final Color faded;
  final Color rule;
  final Color highlight;
  final Color tape;

  const NoteColors._(
      {required this.paper,
      required this.ink,
      required this.faded,
      required this.rule,
      required this.highlight,
      required this.tape});

  static NoteColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const NoteColors._(
        paper: Color(0xFF3A3424),
        ink: Color(0xFFF4ECD2),
        faded: Color(0xFFB7AD90),
        rule: Color(0x22F4ECD2),
        highlight: Color(0x1FFFD54F),
        tape: Color(0x33FFFFFF),
      );
    }
    return const NoteColors._(
      paper: Color(0xFFFFF4B8),
      ink: Color(0xFF332C14),
      faded: Color(0xFF7D7353),
      rule: Color(0x1F332C14),
      highlight: Color(0x26E0A800),
      tape: Color(0x66FFFFFF),
    );
  }
}

/// A sticky note: a square of yellow paper with a strip of tape on top. [child] is what is written
/// on it.
class NotePaper extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const NotePaper(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.fromLTRB(8, 20, 8, 12)});

  @override
  Widget build(BuildContext context) {
    final colors = NoteColors.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: colors.paper,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2),
              topRight: Radius.circular(2),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(14),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: colors.ink),
            child: IconTheme.merge(
                data: IconThemeData(color: colors.faded), child: child),
          ),
        ),
        Positioned(
          top: -8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 84,
              height: 18,
              decoration: BoxDecoration(
                color: colors.tape,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Text with a line drawn through it when [struck], drawn across from left to right as it is
/// checked off, the way a pen would.
class StrikeText extends StatelessWidget {
  final String text;
  final bool struck;
  final TextStyle? style;
  final int? maxLines;

  /// Whether to draw the line as it happens, rather than show it already there.
  final bool animate;

  const StrikeText(this.text,
      {super.key,
      required this.struck,
      this.style,
      this.maxLines,
      this.animate = true});

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final textStyle = struck
        ? base.copyWith(color: base.color?.withValues(alpha: 0.55))
        : base;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: struck ? 1 : 0),
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            foregroundPainter: progress == 0
                ? null
                : _StrikePainter(
                    text: text,
                    style: textStyle,
                    maxLines: maxLines,
                    progress: progress,
                    color: base.color ?? Colors.black,
                    textDirection: Directionality.of(context),
                  ),
            child: Text(text,
                style: textStyle,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis),
          );
        },
      ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final double progress;
  final Color color;
  final TextDirection textDirection;

  _StrikePainter(
      {required this.text,
      required this.style,
      required this.maxLines,
      required this.progress,
      required this.color,
      required this.textDirection});

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    final total = lines.fold<double>(0, (sum, l) => sum + l.width);
    var left = total * progress;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = max(1.5, (style.fontSize ?? 14) / 9)
      ..strokeCap = StrokeCap.round;
    for (final line in lines) {
      if (left <= 0) break;
      final width = min(left, line.width);
      final y = line.baseline - line.ascent * 0.32;
      canvas.drawLine(
          Offset(line.left, y), Offset(line.left + width, y), paint);
      left -= line.width;
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_StrikePainter old) =>
      old.progress != progress || old.text != text || old.style != style;
}

/// A short burst of confetti from the centre of [child], played each time [trigger] changes to a
/// new value.
class Burst extends StatefulWidget {
  final Widget child;
  final int trigger;

  const Burst({super.key, required this.child, required this.trigger});

  @override
  State<Burst> createState() => _BurstState();
}

class _BurstState extends State<Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void didUpdateWidget(Burst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primary,
      scheme.tertiary,
      const Color(0xFFFFB300),
      const Color(0xFF43A047),
    ];
    return CustomPaint(
      foregroundPainter: _BurstPainter(_controller, colors),
      child: widget.child,
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Animation<double> animation;
  final List<Color> colors;

  _BurstPainter(this.animation, this.colors) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t == 0 || t == 1) return;
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(t);
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = i * 2 * pi / count + (i.isEven ? 0.2 : 0);
      final distance = 8 + 22 * eased * (i.isEven ? 1 : 0.75);
      final position = center + Offset(cos(angle), sin(angle)) * distance;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 1 - t);
      canvas.drawCircle(position, 2.6 * (1 - t * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
