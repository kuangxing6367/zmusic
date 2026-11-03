import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Severity of a transient notification.
enum AppToastKind { info, success, error }

class AppToastItem {
  AppToastItem({
    required this.id,
    required this.message,
    required this.kind,
  });

  final int id;
  final String message;
  final AppToastKind kind;

  Duration get duration => switch (kind) {
        AppToastKind.error => const Duration(seconds: 4),
        _ => const Duration(milliseconds: 2600),
      };
}

/// Lightweight notification service.
///
/// Uses a top-right stack instead of [ScaffoldMessenger] snack bars so the
/// message never collides with the mini player docked at the bottom of the
/// window. The cards look like Windows 11 toasts and slide in from the right.
class AppToast {
  AppToast._();

  static final ValueNotifier<List<AppToastItem>> queue =
      ValueNotifier<List<AppToastItem>>(const []);

  static int _nextId = 0;

  static void show(
    String message, {
    AppToastKind kind = AppToastKind.info,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    // Repeating the same message replaces the current card instead of stacking
    // five identical ones (favourite toggles, queue adds, ...).
    final items = queue.value
        .where((item) => item.message != text)
        .toList(growable: true)
      ..add(AppToastItem(id: _nextId++, message: text, kind: kind));
    if (items.length > 4) items.removeRange(0, items.length - 4);
    queue.value = List.unmodifiable(items);
  }

  static void success(String message) =>
      show(message, kind: AppToastKind.success);

  static void error(String message) => show(message, kind: AppToastKind.error);

  static void remove(int id) {
    final next = queue.value.where((item) => item.id != id).toList();
    if (next.length == queue.value.length) return;
    queue.value = List.unmodifiable(next);
  }
}

/// Overlay that hosts the notification stack. Placed in `MaterialApp.builder`
/// above the navigator so it survives page transitions.
class AppToastHost extends StatelessWidget {
  const AppToastHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = math.min(360.0, MediaQuery.sizeOf(context).width - 32);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            minimum: const EdgeInsets.only(top: 12, right: 16),
            child: ValueListenableBuilder<List<AppToastItem>>(
              valueListenable: AppToast.queue,
              builder: (context, items, _) {
                if (items.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final item in items.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ToastCard(
                            key: ValueKey(item.id),
                            item: item,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.item});

  final AppToastItem item;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0.22, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.item.duration, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) AppToast.remove(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, tint) = switch (widget.item.kind) {
      AppToastKind.success => (Icons.check_rounded, const Color(0xFF34C759)),
      AppToastKind.error => (Icons.priority_high_rounded, scheme.error),
      AppToastKind.info => (Icons.notifications_none_rounded, scheme.primary),
    };

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.item.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
