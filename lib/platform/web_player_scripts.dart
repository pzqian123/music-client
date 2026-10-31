/// 隐藏式网页播放器的 JS 脚本集合（纯字符串，便于单测）。
///
/// 设计原则：直接操作底层 <audio>/<video> 元素，而不是依赖厂商的 DOM 结构，
/// 这样页面改版时不容易失效。
library;

/// 探测媒体元素并回读状态。
const String mediaStateScript = r"""
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  var el = null;
  for (var i = 0; i < els.length; i++) {
    if (els[i].duration > 0 || !els[i].paused) { el = els[i]; break; }
  }
  if (!el && els.length) el = els[0];
  if (!el) {
    return JSON.stringify({ hasMedia: false, mediaCount: els.length });
  }
  return JSON.stringify({
    hasMedia: true,
    mediaCount: els.length,
    paused: el.paused,
    ended: el.ended,
    position: el.currentTime || 0,
    duration: isFinite(el.duration) ? el.duration : 0,
    readyState: el.readyState,
    networkState: el.networkState,
    errorCode: el.error ? el.error.code : 0,
    volume: el.volume,
    muted: el.muted,
    tag: el.tagName
  });
})();
""";

/// 播放/暂停切换。
const String mediaToggleScript = r"""
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  var el = null;
  for (var i = 0; i < els.length; i++) {
    if (els[i].duration > 0 || !els[i].paused) { el = els[i]; break; }
  }
  if (!el && els.length) el = els[0];
  if (!el) { return 'no-media'; }
  if (el.paused) { el.play(); return 'play'; }
  el.pause();
  return 'pause';
})();
""";

/// 显式播放。
const String mediaPlayScript = r"""
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  if (!els.length) { return 'no-media'; }
  var el = els[0];
  for (var i = 0; i < els.length; i++) {
    if (els[i].duration > 0 || !els[i].paused) { el = els[i]; break; }
  }
  el.play();
  return 'play';
})();
""";

/// 显式暂停。
const String mediaPauseScript = r"""
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  for (var i = 0; i < els.length; i++) { els[i].pause(); }
  return 'pause';
})();
""";

/// 跳转到指定秒数。
String mediaSeekScript(double seconds) {
  final safe = seconds.isFinite && seconds >= 0 ? seconds : 0;
  return '''
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  if (!els.length) { return 'no-media'; }
  var el = els[0];
  for (var i = 0; i < els.length; i++) {
    if (els[i].duration > 0 || !els[i].paused) { el = els[i]; break; }
  }
  el.currentTime = $safe;
  return 'seeked:' + el.currentTime;
})();
''';
}

/// 设置音量 0..1。
String mediaVolumeScript(double volume) {
  final safe = volume.isFinite ? volume.clamp(0.0, 1.0) : 1.0;
  return '''
(function () {
  var els = Array.prototype.slice.call(document.querySelectorAll('audio, video'));
  for (var i = 0; i < els.length; i++) { els[i].volume = $safe; els[i].muted = false; }
  return 'volume:$safe';
})();
''';
}

/// 让 WebView 里的页面保持活跃（避免部分页面因失焦暂停）。
const String keepAliveScript = r"""
(function () {
  window.__hiddenPlayerKeepAlive = true;
  document.addEventListener('visibilitychange', function () {
    if (document.hidden && window.__hiddenPlayerKeepAlive) {
      try { window.focus(); } catch (e) {}
    }
  });
  return 'ok';
})();
""";
