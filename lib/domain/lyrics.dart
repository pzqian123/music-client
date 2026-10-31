/// 歌词时间轴：行级 + 逐字级，带逐行/静态/不可用回退。
library;

/// 单个逐字片段。
class LyricWord {
  final String text;
  final Duration start;
  final Duration end;

  const LyricWord({
    required this.text,
    required this.start,
    required this.end,
  });

  bool get isValid => end > start;

  @override
  String toString() => 'LyricWord("$text", $start..$end)';
}

/// 一行歌词。
class LyricLine {
  final String text;
  final Duration start;
  final Duration end;
  final List<LyricWord> words;

  const LyricLine({
    required this.text,
    required this.start,
    required this.end,
    this.words = const [],
  });

  bool get hasTiming => end > start;

  @override
  String toString() => 'LyricLine("$text", $start..$end, words: ${words.length})';
}

/// 歌词同步模式。
enum LyricSyncMode {
  /// 有可靠逐字时间戳，可做逐字高亮。
  word,

  /// 只有行级时间戳，平滑滚动 + 整行高亮。
  line,

  /// 完全没有时间戳，只能静态展示。
  static,

  /// 没有歌词。
  unavailable,
}

/// 歌词时间轴。
class LyricTimeline {
  /// 已按 start 升序，非法行已剔除。
  final List<LyricLine> lines;

  /// 是否为静态（无时间戳）歌词。
  final bool isStatic;

  LyricTimeline(List<LyricLine> lines, {this.isStatic = false})
      : lines = List.unmodifiable(_sanitize(lines, isStatic));

  /// 无时间戳的静态歌词。
  factory LyricTimeline.staticText(String text) {
    final rows = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => LyricLine(text: e, start: Duration.zero, end: Duration.zero))
        .toList();
    return LyricTimeline(rows, isStatic: true);
  }

  static List<LyricLine> _sanitize(List<LyricLine> input, bool isStatic) {
    if (isStatic) return List<LyricLine>.from(input);
    final sorted = List<LyricLine>.from(input)
      ..sort((a, b) => a.start.compareTo(b.start));
    return sorted.where((line) => line.text.trim().isNotEmpty).toList();
  }

  bool get isEmpty => lines.isEmpty;

  int get length => lines.length;

  /// 任一行缺可靠逐字时间戳就整体回退到行级，避免"部分逐字"的割裂感。
  LyricSyncMode get mode {
    if (lines.isEmpty) return LyricSyncMode.unavailable;
    if (isStatic) return LyricSyncMode.static;
    final timed = lines.where((l) => l.hasTiming).toList();
    if (timed.isEmpty) return LyricSyncMode.static;
    final allWorded = timed.every(
      (line) => line.words.isNotEmpty && _wordCoverage(line) >= 0.8,
    );
    return allWorded ? LyricSyncMode.word : LyricSyncMode.line;
  }

  static double _wordCoverage(LyricLine line) {
    final lineSpan = line.end - line.start;
    if (lineSpan <= Duration.zero) return 0;
    var covered = Duration.zero;
    for (final word in line.words) {
      if (!word.isValid) continue;
      final start = word.start < line.start ? line.start : word.start;
      final end = word.end > line.end ? line.end : word.end;
      if (end > start) covered += end - start;
    }
    final ratio = covered.inMilliseconds / lineSpan.inMilliseconds;
    if (ratio.isNaN || ratio.isInfinite) return 0;
    return ratio.clamp(0.0, 1.0);
  }

  /// 当前行索引；空歌词返回 -1。
  int activeLineAt(Duration position) {
    if (lines.isEmpty) return -1;
    if (mode == LyricSyncMode.static) return 0;
    if (position <= lines.first.start) return 0;
    var index = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].start <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// 整行进度 0..1；用于逐字模式的整体扫光。
  double wordProgressAt(int lineIndex, Duration position) {
    if (lineIndex < 0 || lineIndex >= lines.length) return 0;
    final line = lines[lineIndex];
    if (!line.hasTiming || line.words.isEmpty) return 0;
    final wordProgresses = wordProgressesAt(lineIndex, position);
    if (wordProgresses.isEmpty) return 0;
    final sum = wordProgresses.fold<double>(0, (acc, p) => acc + p);
    final raw = sum / wordProgresses.length;
    if (raw.isNaN || raw.isInfinite) return 0;
    return raw.clamp(0.0, 1.0);
  }

  /// 每个字的进度 0..1，供 Text.rich 逐字染色。
  List<double> wordProgressesAt(int lineIndex, Duration position) {
    if (lineIndex < 0 || lineIndex >= lines.length) return const [];
    final line = lines[lineIndex];
    if (!line.hasTiming || line.words.isEmpty) return const [];
    return [
      for (final word in line.words)
        if (!word.isValid)
          0.0
        else if (position <= word.start)
          0.0
        else if (position >= word.end)
          1.0
        else
          ((position - word.start).inMilliseconds /
                  (word.end - word.start).inMilliseconds)
              .clamp(0.0, 1.0),
    ];
  }

  /// 解析 [mm:ss.xx] 形式的 LRC。
  factory LyricTimeline.parseLrc(String lrc) {
    final pattern = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricLine>[];
    for (final rawLine in lrc.split('\n')) {
      final matches = pattern.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final text = rawLine.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fractionRaw = match.group(3) ?? '0';
        final fraction = int.parse(
          fractionRaw.padRight(3, '0').substring(0, 3),
        );
        final start = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: fraction,
        );
        lines.add(
          LyricLine(
            text: text,
            start: start,
            end: start, // 行结束时间在 buildEnds 中补齐
          ),
        );
      }
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return LyricTimeline(_withComputedEnds(lines));
  }

  /// 用下一行的开始时间补齐当前行结束时间；最后一行给 4 秒。
  static List<LyricLine> _withComputedEnds(List<LyricLine> lines) {
    if (lines.isEmpty) return lines;
    const tail = Duration(seconds: 4);
    final result = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final end = i + 1 < lines.length ? lines[i + 1].start : line.start + tail;
      result.add(
        LyricLine(
          text: line.text,
          start: line.start,
          end: end,
          words: line.words,
        ),
      );
    }
    return result;
  }
}
