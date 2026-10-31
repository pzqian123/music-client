/// 统一的服务商契约：表现层只能依赖这里，不得直接依赖任何服务商 SDK。
library;

import '../domain/lyrics.dart';
import '../domain/models.dart';

/// 服务商错误的分类，用于映射到界面提示。
enum ProviderErrorKind {
  network,
  unauthorized,
  forbidden,
  rateLimited,
  notConfigured,
  notSupported,
  unknown,
}

class ProviderException implements Exception {
  final String message;
  final ProviderErrorKind kind;

  const ProviderException(this.message, {this.kind = ProviderErrorKind.unknown});

  @override
  String toString() => 'ProviderException($message)';
}

/// 某个服务当前的可观测状态快照。
class ProviderSnapshot {
  final MusicService service;
  final ProviderState state;
  final ProviderCapabilities capabilities;
  final String? message;

  const ProviderSnapshot({
    required this.service,
    required this.state,
    required this.capabilities,
    this.message,
  });

  ProviderSnapshot copyWith({
    ProviderState? state,
    ProviderCapabilities? capabilities,
    String? message,
  }) {
    return ProviderSnapshot(
      service: service,
      state: state ?? this.state,
      capabilities: capabilities ?? this.capabilities,
      message: message ?? this.message,
    );
  }
}

/// 客户端内播放的启动结果。
enum PlaybackStartOutcome {
  started,
  notAuthorized,
  notSupported,
  regionRestricted,
  requiresSubscription,
  failed,
}

class PlaybackStartResult {
  final PlaybackStartOutcome outcome;
  final String? message;

  const PlaybackStartResult(this.outcome, {this.message});

  const PlaybackStartResult.started({this.message})
      : outcome = PlaybackStartOutcome.started;

  bool get isStarted => outcome == PlaybackStartOutcome.started;
}

abstract interface class MusicProvider {
  MusicService get service;

  String get displayName;

  /// 演示数据标记：界面必须显示"演示数据"，避免被误认为真实接入。
  bool get isDemo;

  ProviderSnapshot get snapshot;

  ProviderCapabilities get capabilities;

  Future<void> connect();

  Future<void> disconnect();

  Future<List<ProviderTrack>> search(String query);

  Future<LyricTimeline?> lyricsFor(String providerTrackId);

  Future<PlaybackStartResult> startPlayback(String providerTrackId);

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Uri? officialHandoff(String providerTrackId);
}
