import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import '../domain/models.dart';
import '../platform/web_playback_engine.dart';
import '../providers/music_provider.dart';
import '../providers/spotify_provider.dart';
import 'web_player_ui.dart';
import 'widgets/provider_status_banner.dart';

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Text('连接', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('仅使用官方授权流程；本应用不会请求或保存你的账号密码。', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          const _OfficialPlayerCard(),
          const SizedBox(height: 12),
          for (final provider in music.providers) ...[
            _ProviderCard(music: music, provider: provider),
            const SizedBox(height: 12),
          ],
          if (music.isDemo) ...[
            const SizedBox(height: 8),
            Text(
              '当前为演示数据：不会访问任何真实服务，也不会产生真实授权。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficialPlayerCard extends StatelessWidget {
  const _OfficialPlayerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ui = context.watch<WebPlayerUi>();
    final engine = context.watch<WebPlaybackEngine?>();
    final state = engine?.state;

    return Card(
      key: const Key('official-player-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('官方网页播放器', style: theme.textTheme.titleMedium),
                ),
                Text(
                  engine == null ? '不可用' : (engine.isAttached ? '已就绪' : '未挂载'),
                  key: const Key('official-player-state'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '音频由官方页面输出，界面完全由本应用控制。首次使用请在这里登录（登录信息只存在本机）。',
              style: theme.textTheme.bodySmall,
            ),
            if (state != null && state.hasMedia) ...[
              const SizedBox(height: 8),
              Text(
                '当前：${state.nowPlaying.isEmpty ? "未知曲目" : state.nowPlaying} · '
                '${state.paused ? "已暂停" : "播放中"}',
                style: theme.textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('open-official-page'),
                  onPressed: ui.open,
                  icon: const Icon(Icons.login, size: 16),
                  label: const Text('打开官方页面登录/切歌'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotifySetupPanel extends StatefulWidget {
  const _SpotifySetupPanel({required this.music, required this.provider});

  final MusicController music;
  final SpotifyProvider provider;

  @override
  State<_SpotifySetupPanel> createState() => _SpotifySetupPanelState();
}

class _SpotifySetupPanelState extends State<_SpotifySetupPanel> {
  final _controller = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _editing = !widget.provider.isConfigured;
    _controller.text = widget.provider.clientId ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _maskedClientId {
    final id = widget.provider.clientId ?? '';
    if (id.length <= 10) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  Future<void> _openDashboard() async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await widget.music.openOfficialApp(
      Uri.parse('https://developer.spotify.com/dashboard'),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          opened ? '已在浏览器打开 Spotify Developer Dashboard' : '无法打开浏览器',
        ),
      ),
    );
  }

  Future<void> _saveAndLogin() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '请输入 Spotify Client ID');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.provider.configureClientId(value);
      widget.music.refreshProviders();
      await widget.provider.connect();
      widget.music.refreshProviders();
      if (!mounted) return;
      setState(() => _editing = false);
      messenger.showSnackBar(const SnackBar(content: Text('Spotify 已连接')));
    } on ProviderException catch (error) {
      widget.music.refreshProviders();
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_editing && widget.provider.isConfigured) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.key_rounded, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Client ID：$_maskedClientId',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('spotify-edit-client-id'),
                onPressed: () => setState(() => _editing = true),
                child: const Text('更换'),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('配置 Spotify 公共客户端', style: theme.textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(
              '在 Dashboard 创建应用，并把回调地址设为 '
              'http://127.0.0.1:8080/callback。Client ID 不是密钥，可安全保存在本机。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('spotify-client-id'),
              controller: _controller,
              enabled: !_saving,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Spotify Client ID',
                errorText: _error,
                isDense: true,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('spotify-open-dashboard'),
                  onPressed: _openDashboard,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开 Dashboard'),
                ),
                FilledButton.icon(
                  key: const Key('spotify-save-login'),
                  onPressed: _saving ? null : _saveAndLogin,
                  icon: _saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login, size: 16),
                  label: Text(_saving ? '等待授权…' : '保存并登录'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.music, required this.provider});

  final MusicController music;
  final MusicProvider provider;

  Uri? get _handoffUri {
    final track = music.playback.current;
    if (track == null) return null;
    return track.sourceFor(provider.service)?.officialHandoffUri;
  }

  Future<void> _connect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.connect();
      music.refreshProviders();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${provider.displayName} 已连接${provider.isDemo ? '（演示）' : ''}',
          ),
        ),
      );
    } on ProviderException catch (error) {
      music.refreshProviders();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot =
        music.providerStates[provider.service] ?? provider.snapshot;
    final caps = snapshot.capabilities;
    final connected = snapshot.state == ProviderState.connected;
    final handoff = _handoffUri;

    return Card(
      key: Key('provider-card-${provider.service.name}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    provider.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (provider.isDemo)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('演示', style: theme.textTheme.labelSmall),
                  ),
                Text(
                  providerStateLabel(snapshot.state),
                  key: Key('provider-state-${provider.service.name}'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _capability(context, '搜索', caps.search),
                _capability(context, '元数据', caps.metadata),
                _capability(context, '歌词', caps.lyrics),
                _capability(context, '客户端内播放', caps.inAppPlayback),
                _capability(context, '跳转官方', caps.officialHandoff),
              ],
            ),
            if (provider is SpotifyProvider) ...[
              const SizedBox(height: 12),
              _SpotifySetupPanel(
                music: music,
                provider: provider as SpotifyProvider,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!connected)
                  FilledButton(
                    key: Key('connect-${provider.service.name}'),
                    onPressed: () => _connect(context),
                    child: const Text('连接'),
                  )
                else
                  OutlinedButton(
                    key: Key('disconnect-${provider.service.name}'),
                    onPressed: () => music.disconnect(provider.service),
                    child: const Text('断开'),
                  ),
                TextButton.icon(
                  key: Key('handoff-${provider.service.name}'),
                  onPressed: handoff == null
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await music.openOfficialApp(handoff);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? '已请求打开官方 App' : '打开官方 App 失败，请检查是否已安装',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开官方 App'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _capability(BuildContext context, String label, bool enabled) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(label, style: theme.textTheme.labelSmall),
      backgroundColor: enabled
          ? theme.colorScheme.primary.withValues(alpha: 0.18)
          : null,
      side: BorderSide(
        color: enabled ? theme.colorScheme.primary : theme.dividerColor,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
