enum PluginPermission {
  network('network'),
  clearTextNetwork('clearTextNetwork'),
  localNetwork('localNetwork'),
  credentials('credentials'),
  webAuth('webAuth'),
  clipboard('clipboard'),
  openUrl('openUrl'),
  playbackRead('playbackRead'),
  playbackControl('playbackControl'),
  queueWrite('queueWrite'),
  notifications('notifications'),
  customUi('customUi'),
  backgroundTimers('backgroundTimers'),
  filesSave('files.save');

  const PluginPermission(this.wireName);

  final String wireName;

  static PluginPermission fromWireName(String value) {
    for (final permission in values) {
      if (permission.wireName == value) return permission;
    }
    throw ArgumentError('unknown plugin permission: $value');
  }

  String get label => switch (this) {
        PluginPermission.network => '网络访问',
        PluginPermission.clearTextNetwork => '明文 HTTP',
        PluginPermission.localNetwork => '局域网访问',
        PluginPermission.credentials => '账号凭据',
        PluginPermission.webAuth => '网页登录',
        PluginPermission.clipboard => '剪贴板',
        PluginPermission.openUrl => '打开链接',
        PluginPermission.playbackRead => '读取播放状态',
        PluginPermission.playbackControl => '控制播放',
        PluginPermission.queueWrite => '修改播放队列',
        PluginPermission.notifications => '发送通知',
        PluginPermission.customUi => '自定义对话框',
        PluginPermission.backgroundTimers => '后台定时任务',
        PluginPermission.filesSave => '保存文件',
      };

  String get description => switch (this) {
        PluginPermission.network => '向插件声明的域名发起网络请求',
        PluginPermission.clearTextNetwork => '允许不加密的 http:// 连接',
        PluginPermission.localNetwork => '允许访问本机或局域网地址',
        PluginPermission.credentials => '安全保存你的登录凭据',
        PluginPermission.webAuth => '在内置网页中执行登录脚本',
        PluginPermission.clipboard => '向剪贴板写入文本',
        PluginPermission.openUrl => '请求打开外部链接',
        PluginPermission.playbackRead => '读取当前歌曲、队列与进度',
        PluginPermission.playbackControl => '播放、暂停、跳转与切歌',
        PluginPermission.queueWrite => '替换当前播放队列',
        PluginPermission.notifications => '显示轻提示',
        PluginPermission.customUi => '在设置与播放器页显示插件对话框',
        PluginPermission.backgroundTimers => '每秒一次的后台心跳',
        PluginPermission.filesSave => '把下载的音频保存到本地',
      };
}
