import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../providers/music_provider.dart';

String providerStateLabel(ProviderState state) {
  switch (state) {
    case ProviderState.disconnected:
      return '未连接';
    case ProviderState.connecting:
      return '连接中';
    case ProviderState.connected:
      return '已连接';
    case ProviderState.expired:
      return '授权过期';
    case ProviderState.error:
      return '出错';
  }
}

class ProviderStatusBanner extends StatelessWidget {
  const ProviderStatusBanner({
    super.key,
    required this.snapshot,
    this.errorMessage,
    this.onRetry,
  });

  final ProviderSnapshot snapshot;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = snapshot.capabilities;
    final failed = errorMessage != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: failed ? theme.colorScheme.error : theme.dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.cloud_outlined,
            size: 16,
            color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${snapshot.service.displayName} · ${providerStateLabel(snapshot.state)}'
              '${caps.inAppPlayback ? ' · 可内播' : ' · 仅跳转'}',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
          ],
        ],
      ),
    );
  }
}
