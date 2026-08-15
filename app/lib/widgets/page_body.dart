import 'package:flutter/material.dart';

/// Constrains page content to a comfortable reading width.
///
/// This is a mobile-first app, but its most visible deployment is a browser
/// window that can be 2,000 px wide. Without a cap, list rows stretch until the
/// title and its trailing chip sit at opposite ends of the screen and the eye
/// has to travel between them. 840 px is roughly Material's "medium" breakpoint
/// and keeps a row scannable on any display.
///
/// Applied per screen rather than at the shell, because the map is the one
/// view that genuinely wants every pixel it can get.
class PageBody extends StatelessWidget {
  const PageBody({required this.child, this.maxWidth = 840, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
