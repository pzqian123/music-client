/// Spotify 演示 Provider。
///
/// 刻意模拟"可搜索、可读歌词、但账号无客户端内播放权限"的真实常见状态，
/// 用于验证能力降级与官方 App 回退。
library;

import '../domain/lyrics.dart';
import '../domain/models.dart';
import 'demo_provider.dart';
import 'music_provider.dart';

final List<ProviderTrack> spotifyCatalog = [
  ProviderTrack(
    service: MusicService.spotify,
    providerTrackId: 'sp-1',
    title: '夜空中最亮的星',
    artist: '逃跑计划',
    album: '世界',
    duration: const Duration(minutes: 4, seconds: 12),
    accentColor: 0xFF1F3A5F,
    officialHandoffUri: Uri.parse('spotify:track:sp-1'),
    playable: false,
  ),
  ProviderTrack(
    service: MusicService.spotify,
    providerTrackId: 'sp-2',
    title: '夜空中最亮的星 (Live)',
    artist: '逃跑计划',
    album: '世界巡回演唱会',
    duration: const Duration(minutes: 5, seconds: 1),
    accentColor: 0xFF2F4A6F,
    versionMarkers: const {'live'},
    officialHandoffUri: Uri.parse('spotify:track:sp-2'),
    playable: false,
  ),
  ProviderTrack(
    service: MusicService.spotify,
    providerTrackId: 'sp-3',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    duration: const Duration(minutes: 4, seconds: 29),
    accentColor: 0xFF6B4A2F,
    officialHandoffUri: Uri.parse('spotify:track:sp-3'),
    playable: false,
  ),
  ProviderTrack(
    service: MusicService.spotify,
    providerTrackId: 'sp-4',
    title: 'Bohemian Rhapsody',
    artist: 'Queen',
    album: 'A Night At The Opera',
    duration: const Duration(minutes: 5, seconds: 55),
    accentColor: 0xFF3B2A4A,
    officialHandoffUri: Uri.parse('spotify:track:sp-4'),
    playable: false,
  ),
];

LyricTimeline? _spotifyLyrics(String trackId) {
  switch (trackId) {
    case 'sp-1':
      return _lineTimeline(const [
        '夜空中最亮的星',
        '能否听清',
        '那仰望的人',
        '心底的孤独和叹息',
        '夜空中最亮的星',
        '能否记起',
        '曾与我同行',
        '消失在风里的身影',
      ]);
    case 'sp-2':
      return _lineTimeline(const [
        '夜空中最亮的星 (Live)',
        '能否听清',
        '那仰望的人',
        '心底的孤独和叹息',
      ]);
    case 'sp-3':
      return _lineTimeline(const [
        '故事的小黄花',
        '从出生那年就飘着',
        '童年的荡秋千',
        '随记忆一直晃到现在',
      ]);
    default:
      return null; // sp-4：无歌词
  }
}

LyricTimeline _lineTimeline(List<String> lines) {
  const lineMs = 4000;
  return LyricTimeline([
    for (var i = 0; i < lines.length; i++)
      LyricLine(
        text: lines[i],
        start: Duration(milliseconds: i * lineMs),
        end: Duration(milliseconds: (i + 1) * lineMs),
      ),
  ]);
}

class FakeSpotifyProvider extends DemoMusicProvider {
  FakeSpotifyProvider({super.initiallyConnected = true})
      : super(
          service: MusicService.spotify,
          displayName: 'Spotify',
          catalog: spotifyCatalog,
          lyrics: {
            for (final track in spotifyCatalog)
              if (_spotifyLyrics(track.providerTrackId) != null)
                track.providerTrackId: _spotifyLyrics(track.providerTrackId)!,
          },
          capabilities: const ProviderCapabilities(
            search: true,
            metadata: true,
            lyrics: true,
            inAppPlayback: false,
            officialHandoff: true,
          ),
          playbackOutcome: PlaybackStartOutcome.requiresSubscription,
        );
}
