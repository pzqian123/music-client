/// 隐藏式网页播放器的 JS 脚本集合（纯字符串，便于单测）。
///
/// 设计原则：直接操作底层 <audio>/<video> 元素，而不是依赖厂商的 DOM 结构，
/// 这样页面改版时不容易失效。
library;

/// 探测媒体元素并回读状态。
/// 在文档开始加载时注入：登记所有被创建的媒体元素。
///
/// 关键点：不少播放器用 `new Audio()` 创建音频对象但**不挂到 DOM**，
/// `document.querySelectorAll('audio')` 找不到它。这里劫持构造与 play()，
/// 把元素登记进 `window.__dshMediaEls`。
const String mediaTapScript = r"""
(function () {
  if (window.__dshMediaTapInstalled) { return; }
  window.__dshMediaTapInstalled = true;
  window.__dshMediaEls = [];

  function remember(el) {
    if (!el) { return; }
    if (window.__dshMediaEls.indexOf(el) === -1) {
      window.__dshMediaEls.push(el);
      if (window.__dshMediaEls.length > 30) { window.__dshMediaEls.shift(); }
    }
  }
  window.__dshRememberMedia = remember;

  try {
    var OriginalAudio = window.Audio;
    if (OriginalAudio) {
      var PatchedAudio = function (src) {
        var el = new OriginalAudio(src);
        remember(el);
        return el;
      };
      PatchedAudio.prototype = OriginalAudio.prototype;
      window.Audio = PatchedAudio;
    }
  } catch (e) {}

  try {
    var createElement = Document.prototype.createElement;
    Document.prototype.createElement = function (tag) {
      var el = createElement.apply(this, arguments);
      if (el && el.tagName && /^(AUDIO|VIDEO)$/i.test(el.tagName)) {
        remember(el);
      }
      return el;
    };
  } catch (e) {}

  try {
    var originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      remember(this);
      return originalPlay.apply(this, arguments);
    };
  } catch (e) {}
})();
""";

/// 探测媒体元素并回读状态。
const String mediaStateScript = r"""
(function () {
  function nowPlaying() {
    var selectors = [
      '.m-playbar .words a',
      '.m-playbar .words',
      '[data-testid="context-item-link"]',
      '[data-testid="nowplaying-track-link"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var node = document.querySelector(selectors[i]);
      if (node && node.textContent) { return node.textContent.trim().slice(0, 60); }
    }
    return '';
  }

  function mssToMs(text) {
    var m = /(\d{1,2}):(\d{2})/.exec(text || '');
    if (!m) { return 0; }
    return (parseInt(m[1], 10) * 60 + parseInt(m[2], 10)) * 1000;
  }

  // 1) 先找劫持登记过的元素，再并入 DOM 里的元素。
  var els = [];
  if (window.__dshMediaEls && window.__dshMediaEls.length) {
    els = els.concat(window.__dshMediaEls);
  }
  els = els.concat(Array.prototype.slice.call(document.querySelectorAll('audio, video')));
  els = els.filter(function (el, idx) { return el && els.indexOf(el) === idx; });

  var el = null;
  for (var i = 0; i < els.length; i++) {
    if (!els[i].paused && els[i].duration > 0) { el = els[i]; break; }
  }
  if (!el) {
    for (var j = 0; j < els.length; j++) {
      if (els[j].duration > 0) { el = els[j]; break; }
    }
  }
  if (!el && els.length) { el = els[0]; }

  var base = {
    mediaCount: els.length,
    pageTitle: document.title,
    nowPlaying: nowPlaying(),
    iframes: document.querySelectorAll('iframe').length
  };

  if (el) {
    base.hasMedia = true;
    base.source = 'element';
    base.paused = el.paused;
    base.ended = el.ended;
    base.position = el.currentTime || 0;
    base.duration = isFinite(el.duration) ? el.duration : 0;
    base.readyState = el.readyState;
    base.networkState = el.networkState;
    base.errorCode = el.error ? el.error.code : 0;
    base.volume = el.volume;
    base.muted = el.muted;
    base.tag = el.tagName;
    return JSON.stringify(base);
  }

  // 2) 兜底：从官方播放栏文本与进度条推断（网易云等 WebAudio 播放器）。
  var bar = document.querySelector('.m-playbar');
  if (bar) {
    var timeNode = bar.querySelector('.time');
    var timeText = timeNode ? timeNode.textContent : '';
    var playing = !!bar.querySelector('.btns .ply[title="暂停"]');
    base.hasMedia = true;
    base.source = 'navbar';
    base.paused = !playing;
    base.position = mssToMs(timeText) / 1000;
    var parts = (timeText || '').match(/(\d{1,2}):(\d{2})/g);
    base.duration = parts && parts.length > 1 ? mssToMs(parts[1]) / 1000 : 0;
    return JSON.stringify(base);
  }

  base.hasMedia = false;
  return JSON.stringify(base);
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
