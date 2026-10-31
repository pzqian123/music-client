/// 演示用 Provider 基类：内存数据、无网络、无密码。
library;

import '../domain/lyrics.dart';
import '../domain/models.dart';
import 'music_provider.dart';

/// 用等分时长把一行文本切成若干逐字片段，保证覆盖率 100%。
LyricLine wordLine(int startMs, int endMs, String text, {int chunkSize = 3}) {
  final runes = text.runes.toList();
  if (runes.isEmpty) {
    return LyricLine(
      text: text,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );
  }
  final count = (runes.length / chunkSize).ceil().clamp(1, 9999);
  final span = endMs - startMs;
  final words = <LyricWord>[];
  for (var i = 0; i < count; i++) {
    final startIndex = i * chunkSize;
    if (startIndex >= runes.length) break;
    final endIndex = (startIndex + chunkSize).clamp(0, runes.length);
    final chunk = String.fromCharCodes(runes.sublist(startIndex, endIndex));
    final wordStart = startMs + (span * i ~/ count);
    final wordEnd = startMs + (span * (i + 1) ~/ count);
    words.add(
      LyricWord(
        text: chunk,
        start: Duration(milliseconds: wordStart),
        end: Duration(milliseconds: wordEnd),
      ),
    );
  }
  return LyricLine(
    text: text,
    start: Duration(milliseconds: startMs),
    end: Duration(milliseconds: endMs),
    words: words,
  );
}

/// 演示 Provider：所有数据在内存中，行为可预测。
class DemoMusicProvider implements MusicProvider {
  DemoMusicProvider({
    required this.service,
    required this.displayName,
    required List<ProviderTrack> catalog,
    Map<String, LyricTimeline> lyrics = const {},
    required this.capabilities,
    required this.playbackOutcome,
    this.latency = const Duration(milliseconds: 120),
    bool initiallyConnected = false,
  })  : _catalog = List.unmodifiable(catalog),
        _lyrics = Map.unmodifiable(lyrics),
        _state = initiallyConnected
            ? ProviderState.connected
            : ProviderState.disconnected;

  @override
  final MusicService service;

  @override
  final String displayName;

  final Duration latency;

  final List<ProviderTrack> _catalog;
  final Map<String, LyricTimeline> _lyrics;

  @override
  final ProviderCapabilities capabilities;

  final PlaybackStartOutcome playbackOutcome;

  ProviderState _state;

  /// 测试开关：置为 true 时 [search] 抛错，用于验证错误隔离。
  bool shouldFail = false;

  @override
  bool get isDemo => true;

  @override
  ProviderSnapshot get snapshot => ProviderSnapshot(
        service: service,
        state: _state,
        capabilities: capabilities,
      );

  @override
  Future<void> connect() async {
    await Future<void>.delayed(latency);
    _state = ProviderState.connected;
  }

  @override
  Future<void> disconnect() async {
    await Future<void>.delayed(latency);
    _state = ProviderState.disconnected;
  }

  @override
  Future<List<ProviderTrack>> search(String query) async {
    await Future<void>.delayed(latency);
    if (shouldFail) {
      throw const ProviderException(
        '演示网络错误',
        kind: ProviderErrorKind.network,
      );
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return _catalog
        .where(
          (track) =>
              track.title.toLowerCase().contains(normalized) ||
              track.artist.toLowerCase().contains(normalized),
        )
        .toList();
  }

  @override
  Future<LyricTimeline?> lyricsFor(String providerTrackId) async {
    await Future<void>.delayed(latency);
    return _lyrics[providerTrackId];
  }

  @override
  Future<PlaybackStartResult> startPlayback(String providerTrackId) async {
    await Future<void>.delayed(latency);
    switch (playbackOutcome) {
      case PlaybackStartOutcome.started:
        return const PlaybackStartResult.started();
      case PlaybackStartOutcome.requiresSubscription:
        return const PlaybackStartResult(
          PlaybackStartOutcome.requiresSubscription,
          message: '该账号无客户端内播放权限，可点「打开官方 App」',
        );
      case PlaybackStartOutcome.notAuthorized:
        return const PlaybackStartResult(
          PlaybackStartOutcome.notAuthorized,
          message: '尚未完成授权',
        );
      case PlaybackStartOutcome.notSupported:
        return const PlaybackStartResult(
          PlaybackStartOutcome.notSupported,
          message: '该服务不提供客户端内播放',
        );
      case PlaybackStartOutcome.regionRestricted:
        return const PlaybackStartResult(
          PlaybackStartOutcome.regionRestricted,
          message: '当前地区不可用',
        );
      case PlaybackStartOutcome.failed:
        return const PlaybackStartResult(
          PlaybackStartOutcome.failed,
          message: '播放失败，请重试',
        );
    }
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Uri? officialHandoff(String providerTrackId) {
    for (final track in _catalog) {
      if (track.providerTrackId == providerTrackId) {
        return track.officialHandoffUri;
      }
    }
    return null;
  }
}
