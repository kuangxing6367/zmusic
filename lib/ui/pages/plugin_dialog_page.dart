import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/plugin/plugin_dialog.dart';
import '../icon_map.dart';
import '../widgets/empty_state.dart';

/// Renders a plugin's declarative `ui.<id>` dialog with host components.
class PluginDialogPage extends StatefulWidget {
  const PluginDialogPage({
    super.key,
    required this.controller,
    required this.providerId,
    required this.contributionId,
    this.label = '',
    this.icon = 'extension',
  });

  final AppController controller;
  final String providerId;
  final String contributionId;
  final String label;
  final String icon;

  @override
  State<PluginDialogPage> createState() => _PluginDialogPageState();
}

class _PluginDialogPageState extends State<PluginDialogPage> {
  final Map<String, dynamic> _inputs = {};
  final Map<String, TextEditingController> _textControllers = {};
  PluginDialog? _dialog;
  Timer? _refresh;
  bool _loading = true;
  bool _busy = false;
  bool _disposed = false;
  String _error = '';
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _invoke('open', sendInputs: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _refresh?.cancel();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _invoke(String action, {bool sendInputs = true}) async {
    final requestId = ++_requestId;
    if (action != 'refresh') {
      setState(() {
        _busy = true;
        _error = '';
      });
    }
    try {
      final raw = await widget.controller.invokeUi(
        widget.providerId,
        widget.contributionId,
        action,
        sendInputs ? _collectInputs() : const {},
      );
      if (_disposed || requestId != _requestId) return;
      final dialog = PluginDialog.fromJson(raw);
      if (dialog == null) {
        throw StateError('插件界面返回格式错误');
      }
      setState(() {
        _dialog = dialog;
        _loading = false;
        _busy = false;
        _error = '';
        _applyInputs(dialog);
      });
      _scheduleRefresh(dialog.refreshMs);
    } catch (e) {
      if (_disposed || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic> _collectInputs() {
    final result = <String, dynamic>{};
    for (final entry in _inputs.entries) {
      final value = entry.value;
      if (value is bool) {
        result[entry.key] = value;
      } else {
        result[entry.key] = value?.toString() ?? '';
      }
    }
    return result;
  }

  void _applyInputs(PluginDialog dialog) {
    final seen = <String>{};
    for (final node in dialog.body) {
      if (node is PluginInputNode) {
        seen.add(node.id);
        final existing = _inputs[node.id];
        final value = node.value.isNotEmpty
            ? node.value
            : (existing is String ? existing : '');
        _inputs[node.id] = value;
        final controller = _textControllers.putIfAbsent(
          node.id,
          () => TextEditingController(text: value),
        );
        if (controller.text != value) controller.text = value;
      } else if (node is PluginSwitchNode) {
        seen.add(node.id);
        final existing = _inputs[node.id];
        _inputs[node.id] = node.checked
            ? true
            : (existing is bool ? existing : false);
      }
    }
    final stale = _inputs.keys.where((key) => !seen.contains(key)).toList();
    for (final key in stale) {
      _inputs.remove(key);
      _textControllers.remove(key)?.dispose();
    }
  }

  void _scheduleRefresh(int refreshMs) {
    _refresh?.cancel();
    _refresh = null;
    if (refreshMs < 500) return;
    _refresh = Timer.periodic(
      Duration(milliseconds: refreshMs),
      (_) {
        if (_busy) return;
        _invoke('refresh', sendInputs: false);
      },
    );
  }

  Future<void> _button(PluginButtonNode node) async {
    if (_busy || !node.enabled) return;
    _refresh?.cancel();
    await _invoke(node.id);
  }

  Future<void> _switch(PluginSwitchNode node, bool value) async {
    _inputs[node.id] = value;
    _refresh?.cancel();
    await _invoke(node.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialog = _dialog;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          dialog?.title ?? (widget.label.isEmpty ? '插件界面' : widget.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        iconForName(dialog?.icon ?? widget.icon),
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dialog?.title ??
                                (widget.label.isEmpty
                                    ? '插件界面'
                                    : widget.label),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((dialog?.subtitle ?? '').isNotEmpty)
                            Text(
                              dialog!.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ErrorBanner(
                    message: _error,
                    onRetry: () => _invoke('open', sendInputs: false),
                  ),
                ],
                if (dialog != null && _error.isEmpty) ...[
                  const SizedBox(height: 16),
                  for (final node in dialog.body) ...[
                    _buildNode(context, node),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _buildNode(BuildContext context, PluginDialogNode node) {
    final theme = Theme.of(context);
    if (node is PluginTextNode) {
      final style = switch (node.style) {
        'title' => theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        'caption' => theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        _ => theme.textTheme.bodyLarge,
      };
      return Text(
        node.text,
        textAlign: node.center ? TextAlign.center : TextAlign.start,
        style: style,
      );
    }
    if (node is PluginErrorNode) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (node is PluginInputNode) {
      final controller = _textControllers[node.id] ??
          TextEditingController(text: _inputs[node.id]?.toString() ?? '');
      _textControllers[node.id] = controller;
      return TextField(
        controller: controller,
        obscureText: node.secret,
        enabled: !_busy,
        onChanged: (value) => _inputs[node.id] = value,
        decoration: InputDecoration(
          hintText: node.placeholder,
          labelText: node.placeholder.isEmpty ? null : node.placeholder,
        ),
      );
    }
    if (node is PluginSwitchNode) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (node.description.isNotEmpty)
                    Text(
                      node.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: _inputs[node.id] == true,
              onChanged: node.enabled && !_busy
                  ? (value) => _switch(node, value)
                  : null,
            ),
          ],
        ),
      );
    }
    if (node is PluginButtonNode) {
      return _buttonWidget(node);
    }
    if (node is PluginRowNode) {
      return Row(
        children: [
          for (var i = 0; i < node.items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _buttonWidget(node.items[i])),
          ],
        ],
      );
    }
    if (node is PluginSpacerNode) {
      return SizedBox(height: node.height.toDouble());
    }
    return const SizedBox.shrink();
  }

  Widget _buttonWidget(PluginButtonNode node) {
    final theme = Theme.of(context);
    final enabled = node.enabled && !_busy;
    final onPressed = enabled ? () => _button(node) : null;
    final destructive = node.destructive;
    final child = Text(node.label);
    switch (node.style) {
      case 'outlined':
        return OutlinedButton(
          onPressed: onPressed,
          style: destructive
              ? OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                )
              : null,
          child: child,
        );
      case 'text':
        return TextButton(
          onPressed: onPressed,
          style: destructive
              ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
              : null,
          child: child,
        );
      default:
        return FilledButton(
          onPressed: onPressed,
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          child: child,
        );
    }
  }
}
