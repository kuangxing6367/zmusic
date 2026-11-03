import 'package:flutter/material.dart';

import '../core/app/app_controller.dart';
import 'pages/player_page.dart';

/// Opens the full player above any current page. Shared by the global mini
/// player and the shell so route settings stay consistent.
Future<void> openPlayer(
  GlobalKey<NavigatorState> navigatorKey,
  AppController controller,
) {
  final navigator = navigatorKey.currentState;
  if (navigator == null || controller.playback.currentSong == null) {
    return Future.value();
  }
  return navigator.push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/player'),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => PlayerPage(controller: controller),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}
