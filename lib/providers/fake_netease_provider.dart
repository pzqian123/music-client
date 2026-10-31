/// 网易云音乐演示 Provider。
///
/// 模拟"可搜索、有逐字歌词、支持客户端内演示播放"的状态。
library;

import '../domain/lyrics.dart';
import '../domain/models.dart';
import 'demo_provider.dart';
import 'music_provider.dart';

final List<ProviderTrack> neteaseCatalog = [
  ProviderTrack(
    service: MusicService.netease,
    providerTrackId: 'ne-1',
    title: '夜空中最亮的星',
    artist: '逃跑计划',
    album: '世界',
    duration: const Duration(minutes: 4, seconds: 11),
    accentColor: 0xFF2B4C6F,
    officialHandoffUri: Uri.parse('https://music.163.com/song?id=ne-1'),
    playable: true,
  ),
  ProviderTrack(
    service: MusicService.netease,
    providerTrackId: 'ne-2',
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    duration: const Duration(minutes: 4, seconds: 29),
    accentColor: 0xFF6B4A2F,
    officialHandoffUri: Uri.parse('https://music.163.com/song?id=ne-2'),
    playable: true,
  ),
  ProviderTrack(
    service: MusicService.netease,
    providerTrackId: 'ne-3',
    title: '平凡之路',
    artist: '朴树',
    album: '猎户星座',
    duration: const Duration(minutes: 5, seconds: 2),
    accentColor: 0xFF3A3F52,
    officialHandoffUri: Uri.parse('https://music.163.com/song?id=ne-3'),
    playable: true,
  ),
  ProviderTrack(
    service: MusicService.netease,
    providerTrackId: 'ne-4',
    title: '稻香',
    artist: '周杰伦',
    album: '魔杰座',
    duration: const Duration(minutes: 3, seconds: 43),
    accentColor: 0xFF4A5A3C,
    officialHandoffUri: Uri.parse('https://music.163.com/song?id=ne-4'),
    playable: true,
  ),
];

/// 逐字歌词：每行 4 秒，逐字时间戳覆盖整行。
LyricTimeline _wordTimeline(List<String> lines) {
  const lineMs = 4000;
  return LyricTimeline([
    for (var i = 0; i < lines.length; i++)
      wordLine(i * lineMs, (i + 1) * lineMs, lines[i]),
  ]);
}

LyricTimeline? _neteaseLyrics(String trackId) {
  switch (trackId) {
    case 'ne-1':
      return _wordTimeline(const [
        '夜空中最亮的星',
        '能否听清',
        '那仰望的人',
        '心底的孤独和叹息',
        '我祈祷拥有一颗透明的心灵',
        '和会流泪的眼睛',
        '给我再去相信的勇气',
        '越过谎言去拥抱你',
      ]);
    case 'ne-2':
      return _wordTimeline(const [
        '故事的小黄花',
        '从出生那年就飘着',
        '童年的荡秋千',
        '随记忆一直晃到现在',
        '吹着前奏望着天空',
        '我想起花瓣试着掉落',
        '为你翘课的那一天',
        '花落的那一天',
      ]);
    case 'ne-3':
      return LyricTimeline.staticText(
        '我曾经跨过山和大海\n也穿过人山人海\n我曾经拥有着的一切\n转眼都飘散如烟',
      );
    default:
      return null; // ne-4：无歌词
  }
}

class FakeNeteaseProvider extends DemoMusicProvider {
  FakeNeteaseProvider({super.initiallyConnected = true})
      : super(
          service: MusicService.netease,
          displayName: '网易云音乐',
          catalog: neteaseCatalog,
          lyrics: {
            for (final track in neteaseCatalog)
              if (_neteaseLyrics(track.providerTrackId) != null)
                track.providerTrackId: _neteaseLyrics(track.providerTrackId)!,
          },
          capabilities: const ProviderCapabilities(
            search: true,
            metadata: true,
            lyrics: true,
            inAppPlayback: true,
            officialHandoff: true,
          ),
          playbackOutcome: PlaybackStartOutcome.started,
        );
}
