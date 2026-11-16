import 'package:flutter/material.dart';

import 'build_info.dart';

/// A thin strip across the top of the window that says this is a development build, with its
/// commit and time. It takes its own room above the app instead of lying over it, so it never
/// covers a button or a line of text, and it doesn't take taps. A release build (see
/// [BuildInfo.isRelease]) shows the app alone.
class DevBand extends StatelessWidget {
  final Widget child;

  /// The build to show; [BuildInfo.current] unless a test passes another.
  final BuildInfo? info;

  const DevBand({super.key, required this.child, this.info});

  static const height = 16.0;
  static const _background = Color(0xFFFFC107);
  static const _foreground = Color(0xFF3E2723);

  @override
  Widget build(BuildContext context) {
    final info = this.info ?? BuildInfo.current;
    if (info.isRelease) return child;
    final media = MediaQuery.of(context);
    final label = info.commit.isEmpty ? 'DEV BUILD' : 'DEV BUILD · ${info.label}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The phone's status bar or notch stays above the strip's text, in the strip's colour.
        IgnorePointer(
          child: Container(
            key: const Key('dev-band'),
            color: _background,
            padding: EdgeInsets.only(top: media.padding.top),
            height: media.padding.top + height,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: _foreground,
                  decoration: TextDecoration.none),
            ),
          ),
        ),
        // The strip already keeps the app clear of the top of the screen.
        Expanded(
          child: MediaQuery(data: media.removePadding(removeTop: true), child: child),
        ),
      ],
    );
  }
}
