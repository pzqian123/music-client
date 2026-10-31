import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/music_controller.dart';
import '../domain/models.dart';
import '../providers/music_provider.dart';
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
          Text(
            '仅使用官方授权流程；本应用不会请求或保存你的账号密码。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
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
        SnackBar(content: Text('${provider.displayName} 已连接（演示）')),
      );
    } on ProviderException catch (error) {
      music.refreshProviders();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = music.providerStates[provider.service] ??
        provider.snapshot;
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
      backgroundColor:
          enabled ? theme.colorScheme.primary.withValues(alpha: 0.18) : null,
      side: BorderSide(
        color: enabled ? theme.colorScheme.primary : theme.dividerColor,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
