/// Host-rendered declarative dialog contributed by a plugin through the
/// `ui.<id>` handler (see docs/plugins.md, "Declarative dialogs").
class PluginDialog {
  const PluginDialog({
    required this.title,
    this.subtitle = '',
    this.icon = 'extension',
    this.refreshMs = 0,
    this.body = const [],
  });

  final String title;
  final String subtitle;
  final String icon;
  final int refreshMs;
  final List<PluginDialogNode> body;

  static PluginDialog? fromJson(Map<String, dynamic> raw) {
    final title = raw['title']?.toString().trim() ?? '';
    if (title.isEmpty || title.length > 60) return null;
    var subtitle = raw['subtitle']?.toString() ?? '';
    if (subtitle.length > 120) subtitle = subtitle.substring(0, 120);
    final icon = raw['icon']?.toString() ?? 'extension';
    final refreshMs = (raw['refreshMs'] as num?)?.toInt() ?? 0;
    final body = <PluginDialogNode>[];
    final rawBody = raw['body'];
    if (rawBody is List) {
      for (final item in rawBody.take(10)) {
        if (item is! Map) continue;
        final node = PluginDialogNode.fromJson(item.cast<String, dynamic>());
        if (node != null) body.add(node);
      }
    }
    if (body.isEmpty) return null;
    return PluginDialog(
      title: title,
      subtitle: subtitle,
      icon: RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(icon)
          ? icon
          : 'extension',
      refreshMs: refreshMs >= 500 && refreshMs <= 60000 ? refreshMs : 0,
      body: body,
    );
  }
}

sealed class PluginDialogNode {
  const PluginDialogNode();

  static PluginDialogNode? fromJson(Map<String, dynamic> raw) {
    final type = raw['type']?.toString() ?? '';
    switch (type) {
      case 'text':
        final text = _clip(raw['text']?.toString() ?? '', 500);
        final style = raw['style']?.toString() ?? 'body';
        return PluginTextNode(
          text: text,
          style: const {'title', 'body', 'caption'}.contains(style)
              ? style
              : 'body',
          center: raw['center'] == true,
        );
      case 'error':
        return PluginErrorNode(text: _clip(raw['text']?.toString() ?? '', 300));
      case 'input':
        final id = raw['id']?.toString() ?? '';
        if (!_idPattern.hasMatch(id)) return null;
        return PluginInputNode(
          id: id,
          placeholder: _clip(raw['placeholder']?.toString() ?? '', 60),
          value: _clip(raw['value']?.toString() ?? '', 2048),
          secret: raw['secret'] == true,
        );
      case 'switch':
        final id = raw['id']?.toString() ?? '';
        final label = _clip(raw['label']?.toString() ?? '', 120);
        if (!_idPattern.hasMatch(id) || label.isEmpty) return null;
        return PluginSwitchNode(
          id: id,
          label: label,
          description: _clip(raw['desc']?.toString() ?? '', 500),
          checked: raw['checked'] == true,
          enabled: raw['enabled'] != false,
        );
      case 'button':
        final button = PluginButtonNode.fromJson(raw);
        return button;
      case 'row':
        final rawItems = raw['items'];
        if (rawItems is! List) return null;
        final items = <PluginButtonNode>[];
        for (final item in rawItems.take(3)) {
          if (item is! Map) continue;
          if (item['type']?.toString() != 'button') continue;
          final button = PluginButtonNode.fromJson(item.cast<String, dynamic>());
          if (button != null) items.add(button);
        }
        if (items.isEmpty) return null;
        return PluginRowNode(items: items);
      case 'spacer':
        final height = (raw['height'] as num?)?.toInt() ?? 8;
        return PluginSpacerNode(height: height.clamp(0, 48).toInt());
      default:
        return null;
    }
  }

  static final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}

class PluginTextNode extends PluginDialogNode {
  const PluginTextNode({
    required this.text,
    this.style = 'body',
    this.center = false,
  });

  final String text;
  final String style;
  final bool center;
}

class PluginErrorNode extends PluginDialogNode {
  const PluginErrorNode({required this.text});

  final String text;
}

class PluginInputNode extends PluginDialogNode {
  const PluginInputNode({
    required this.id,
    this.placeholder = '',
    this.value = '',
    this.secret = false,
  });

  final String id;
  final String placeholder;
  final String value;
  final bool secret;
}

class PluginSwitchNode extends PluginDialogNode {
  const PluginSwitchNode({
    required this.id,
    required this.label,
    this.description = '',
    this.checked = false,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String description;
  final bool checked;
  final bool enabled;
}

class PluginButtonNode extends PluginDialogNode {
  const PluginButtonNode({
    required this.id,
    required this.label,
    this.style = 'filled',
    this.enabled = true,
    this.destructive = false,
  });

  final String id;
  final String label;
  final String style;
  final bool enabled;
  final bool destructive;

  static PluginButtonNode? fromJson(Map<String, dynamic> raw) {
    final id = raw['id']?.toString() ?? '';
    final label = PluginDialogNode._clip(raw['label']?.toString() ?? '', 24);
    if (!PluginDialogNode._idPattern.hasMatch(id) || label.isEmpty) return null;
    final style = raw['style']?.toString() ?? 'filled';
    return PluginButtonNode(
      id: id,
      label: label,
      style: const {'filled', 'outlined', 'text'}.contains(style)
          ? style
          : 'filled',
      enabled: raw['enabled'] != false,
      destructive: raw['destructive'] == true,
    );
  }
}

class PluginRowNode extends PluginDialogNode {
  const PluginRowNode({required this.items});

  final List<PluginButtonNode> items;
}

class PluginSpacerNode extends PluginDialogNode {
  const PluginSpacerNode({this.height = 8});

  final int height;
}
