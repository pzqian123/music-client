import 'package:flutter_test/flutter_test.dart';
import 'package:music_client/domain/lyrics.dart';

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(int startMs, int endMs, {List<LyricWord> words = const []}) {
  return LyricLine(
    text: 'line-$startMs',
    start: _ms(startMs),
    end: _ms(endMs),
    words: words,
  );
}

List<LyricWord> _fullWords(int startMs, int endMs) {
  final mid = (startMs + endMs) ~/ 2;
  return [
    LyricWord(text: 'a', start: _ms(startMs), end: _ms(mid)),
    LyricWord(text: 'b', start: _ms(mid), end: _ms(endMs)),
  ];
}

void main() {
  group('activeLineAt', () {
    final timeline = LyricTimeline([
      _line(0, 5000),
      _line(5000, 10000),
      _line(10000, 15000),
    ]);

    test('开始前返回 0', () => expect(timeline.activeLineAt(Duration.zero), 0));

    test('负时间返回 0', () {
      expect(timeline.activeLineAt(const Duration(seconds: -5)), 0);
    });

    test('区间中返回对应行', () {
      expect(timeline.activeLineAt(_ms(7000)), 1);
      expect(timeline.activeLineAt(_ms(12000)), 2);
    });

    test('恰好落在切换点算新行', () {
      expect(timeline.activeLineAt(_ms(5000)), 1);
    });

    test('结束后返回最后一行', () {
      expect(timeline.activeLineAt(_ms(99999)), 2);
    });

    test('空歌词返回 -1', () {
      expect(LyricTimeline(const []).activeLineAt(Duration.zero), -1);
    });
  });

  group('mode', () {
    test('空歌词为 unavailable', () {
      expect(LyricTimeline(const []).mode, LyricSyncMode.unavailable);
    });

    test('全部行都有逐字时间戳为 word', () {
      final timeline = LyricTimeline([
        _line(0, 4000, words: _fullWords(0, 4000)),
        _line(4000, 8000, words: _fullWords(4000, 8000)),
      ]);
      expect(timeline.mode, LyricSyncMode.word);
    });

    test('任一行缺逐字时间戳整体回退 line', () {
      final timeline = LyricTimeline([
        _line(0, 4000, words: _fullWords(0, 4000)),
        _line(4000, 8000),
      ]);
      expect(timeline.mode, LyricSyncMode.line);
    });

    test('逐字覆盖率不足 80% 回退 line', () {
      final partial = [
        LyricWord(text: 'a', start: _ms(0), end: _ms(1000)),
      ];
      final timeline = LyricTimeline([
        _line(0, 8000, words: partial),
      ]);
      expect(timeline.mode, LyricSyncMode.line);
    });

    test('非法逐字区间被忽略并导致回退', () {
      final invalid = [
        LyricWord(text: 'a', start: _ms(1000), end: _ms(1000)),
      ];
      final timeline = LyricTimeline([
        _line(0, 4000, words: invalid),
      ]);
      expect(timeline.mode, LyricSyncMode.line);
    });

    test('静态歌词为 static', () {
      final timeline = LyricTimeline.staticText('第一行\n第二行');
      expect(timeline.mode, LyricSyncMode.static);
      expect(timeline.lines.length, 2);
    });

    test('无时间戳的行列表也是 static', () {
      final timeline = LyricTimeline([
        _line(0, 0),
        _line(0, 0),
      ]);
      expect(timeline.mode, LyricSyncMode.static);
    });
  });

  group('wordProgressAt', () {
    final timeline = LyricTimeline([
      _line(0, 4000, words: _fullWords(0, 4000)),
    ]);

    test('行开始为 0', () {
      expect(timeline.wordProgressAt(0, Duration.zero), 0);
    });

    test('行结束为 1', () {
      expect(timeline.wordProgressAt(0, _ms(4000)), 1);
    });

    test('区间内落在 0 到 1 之间', () {
      final value = timeline.wordProgressAt(0, _ms(2000));
      expect(value, greaterThan(0));
      expect(value, lessThan(1));
    });

    test('越界索引返回 0', () {
      expect(timeline.wordProgressAt(-1, _ms(1000)), 0);
      expect(timeline.wordProgressAt(9, _ms(1000)), 0);
    });

    test('每个字进度在 0 到 1 之间', () {
      final progresses = timeline.wordProgressesAt(0, _ms(1000));
      expect(progresses.length, 2);
      for (final p in progresses) {
        expect(p, inInclusiveRange(0, 1));
      }
    });
  });

  group('parseLrc', () {
    test('解析时间戳并补齐行结束时间', () {
      final timeline = LyricTimeline.parseLrc(
        '[00:12.34]第一句\n[00:20.00]第二句',
      );
      expect(timeline.lines.length, 2);
      expect(timeline.lines.first.start, _ms(12340));
      expect(timeline.lines.first.end, _ms(20000));
      expect(timeline.lines.last.end, _ms(24000));
    });

    test('忽略空行与无时间戳行', () {
      final timeline = LyricTimeline.parseLrc(
        '\n随便写点什么\n[00:01.00]有效行\n',
      );
      expect(timeline.lines.length, 1);
      expect(timeline.lines.single.text, '有效行');
    });

    test('同一行多个时间戳生成多条', () {
      final timeline = LyricTimeline.parseLrc('[00:01.00][00:05.00]副歌');
      expect(timeline.lines.length, 2);
    });

    test('无歌词文本返回空时间轴', () {
      final timeline = LyricTimeline.parseLrc('[00:01.00]');
      expect(timeline.mode, LyricSyncMode.unavailable);
    });
  });
}
