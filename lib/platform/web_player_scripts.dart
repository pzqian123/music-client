/// 隐藏式网页播放器的 JS 脚本集合（纯字符串，便于单测）。
///
/// 设计原则：
/// 1. 直接操作底层 <audio>/<video>，不依赖厂商 UI 结构；
/// 2. 读状态和发命令必须用**同一个**元素选择器；
/// 3. 播放器常用 `new Audio()` 创建但不挂 DOM，必须在文档开始时就劫持登记。
library;

/// 在文档开始加载时注入：登记所有媒体元素 + 提供统一选择器。
const String mediaTapScript = r"""
(function () {
  if (window.__dshMediaTapInstalled) { return; }
  window.__dshMediaTapInstalled = true;
  window.__dshMediaEls = [];
  window.__dshActiveMedia = null;

  function remember(el) {
    if (!el) { return; }
    if (window.__dshMediaEls.indexOf(el) === -1) {
      window.__dshMediaEls.push(el);
      if (window.__dshMediaEls.length > 30) { window.__dshMediaEls.shift(); }
    }
  }
  window.__dshRememberMedia = remember;

  // 统一的选择器：
  // 1) 优先"正在播且有长度"；2) 有长度；3) 有 src 的；4) 最后创建的那个。
  // 直接取第一个会拿到播放器创建的哑元素（duration 恒为 0）。
  window.__dshPickMedia = function () {
    var list = (window.__dshMediaEls || []).slice();
    var dom = document.querySelectorAll('audio, video');
    for (var i = 0; i < dom.length; i++) {
      if (list.indexOf(dom[i]) === -1) { list.push(dom[i]); }
    }
    var playing = null;
    var timed = null;
    var withSrc = null;
    for (var j = 0; j < list.length; j++) {
      var el = list[j];
      if (!el) { continue; }
      var hasTime = isFinite(el.duration) && el.duration > 0;
      if (!el.paused && hasTime) { playing = el; break; }
      if (hasTime && !timed) { timed = el; }
      if (!withSrc && (el.currentSrc || el.src)) { withSrc = el; }
    }
    var picked = playing || timed || withSrc || list[list.length - 1] || null;
    window.__dshActiveMedia = picked;
    return picked;
  };

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

/// 读取状态（使用统一选择器）。
const String mediaStateScript = r"""
(function () {
  function nowPlayingNode() {
    var selectors = [
      '.m-playbar .words a',
      '.m-playbar .words',
      '[data-testid="context-item-link"]',
      '[data-testid="nowplaying-track-link"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var node = document.querySelector(selectors[i]);
      if (node) { return node; }
    }
    return null;
  }

  function nowPlaying() {
    var node = nowPlayingNode();
    if (!node) { return ''; }
    var title = (node.getAttribute && node.getAttribute('title')) || '';
    var text = node.textContent || title || '';
    return text.trim().slice(0, 60);
  }

  function nowPlayingId() {
    var candidates = [
      '.m-playbar .words a[href*="song?id="]',
      '.m-playbar a[href*="song?id="]',
      '#g_player a[href*="song?id="]',
      '[data-testid="context-item-link"]',
      '[data-testid="nowplaying-track-link"]'
    ];
    for (var i = 0; i < candidates.length; i++) {
      var node = document.querySelector(candidates[i]);
      if (!node) { continue; }
      var href = node.getAttribute('href') || node.href || '';
      var match = /song\?id=(\d+)/.exec(href);
      if (match) { return match[1]; }
      var dataId = node.getAttribute('data-id') ||
        node.getAttribute('data-song-id') || '';
      if (/^\d+$/.test(dataId)) { return dataId; }
    }
    var active = document.querySelector(
      '.m-playbar [data-song-id], #g_player [data-song-id]'
    );
    return active ? (active.getAttribute('data-song-id') || '') : '';
  }

  function mediaSessionField(name) {
    try {
      var metadata = navigator.mediaSession && navigator.mediaSession.metadata;
      if (!metadata || !metadata[name]) { return ''; }
      return String(metadata[name]).trim().slice(0, 100);
    } catch (e) {
      return '';
    }
  }

  function mssToMs(text) {
    var m = /(\d{1,2}):(\d{2})/.exec(text || '');
    if (!m) { return 0; }
    return (parseInt(m[1], 10) * 60 + parseInt(m[2], 10)) * 1000;
  }

  var count = (window.__dshMediaEls || []).length +
    document.querySelectorAll('audio, video').length;
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;

  var base = {
    mediaCount: count,
    pageTitle: document.title,
    nowPlaying: nowPlaying(),
    nowPlayingId: nowPlayingId(),
    mediaSessionTitle: mediaSessionField('title'),
    mediaSessionArtist: mediaSessionField('artist'),
    mediaSessionAlbum: mediaSessionField('album')
  };

  if (el) {
    base.hasMedia = true;
    base.source = 'element';
    base.paused = el.paused;
    base.ended = el.ended;
    base.position = el.currentTime || 0;
    base.duration = isFinite(el.duration) ? el.duration : 0;
    base.readyState = el.readyState;
    base.volume = el.volume;
    base.muted = el.muted;
    base.tag = el.tagName;
    return JSON.stringify(base);
  }

  var bar = document.querySelector('.m-playbar');
  if (bar) {
    var timeNode = bar.querySelector('.time');
    var timeText = timeNode ? timeNode.textContent : '';
    var parts = (timeText || '').match(/(\d{1,2}):(\d{2})/g);
    base.hasMedia = true;
    base.source = 'navbar';
    base.paused = !bar.querySelector('.btns .ply[title="暂停"]');
    base.position = (parts && parts.length ? mssToMs(parts[0]) : 0) / 1000;
    base.duration = parts && parts.length > 1 ? mssToMs(parts[1]) / 1000 : 0;
    return JSON.stringify(base);
  }

  base.hasMedia = false;
  base.source = 'none';
  return JSON.stringify(base);
})();
""";

/// 打开网易云官方播放列表；已经展开时不重复点击。
const String neteaseQueueOpenScript = r"""
(function () {
  var panel = document.querySelector('#g_playlist');
  if (panel && panel.offsetHeight > 0 &&
      getComputedStyle(panel).display !== 'none') {
    return 'already-open';
  }
  var nodes = Array.from(document.querySelectorAll('a,button,span'));
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    var label = [
      node.getAttribute('title') || '',
      node.getAttribute('aria-label') || '',
      node.className || '',
      node.textContent || ''
    ].join(' ');
    if (/播放列表|m-playbar.*icn-list|icn-list/.test(label)) {
      node.click();
      return 'opened';
    }
  }
  return 'queue-button-not-found';
})();
""";

/// 读取网易云官方播放列表（保留官方顺序与当前项）。
const String neteaseQueueReadScript = r"""
(function () {
  function text(node) {
    return node ? (node.textContent || '').replace(/\s+/g, ' ').trim() : '';
  }
  var root = document.querySelector('#g_playlist .listbdc');
  if (!root) { return JSON.stringify({ items: [] }); }
  var items = Array.from(root.querySelectorAll('li[data-id]')).map(function (row) {
    var id = row.getAttribute('data-id') || '';
    var title = text(row.querySelector('.col-2'));
    var artistNode = row.querySelector('.col-4 span');
    var artist = artistNode
      ? ((artistNode.getAttribute('title') || '') || text(artistNode))
      : '';
    return {
      id: id,
      title: title,
      artist: artist,
      duration: text(row.querySelector('.col-5')),
      selected: row.classList.contains('z-sel')
    };
  }).filter(function (item) {
    return /^\d+$/.test(item.id) && item.title;
  });
  return JSON.stringify({ items: items });
})();
""";

String neteaseQueuePlayScript(String songId) {
  final safe = RegExp(r'^\d+$').hasMatch(songId) ? songId : '';
  return r"""
(function () {
  var id = '"""+safe+r"""';
  var row = document.querySelector('#g_playlist li[data-id="' + id + '"]');
  if (!row) { return 'not-found'; }
  row.click();
  return 'clicked';
})();
""";
}

/// 播放/暂停切换，返回操作前的状态便于诊断。
const String mediaToggleScript = r"""
(function () {
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
  if (!el) { return 'no-media'; }
  var before = el.paused;
  try {
    if (before) { el.play(); } else { el.pause(); }
  } catch (e) { return 'error:' + e; }
  return JSON.stringify({ action: before ? 'play' : 'pause', tag: el.tagName });
})();
""";

const String mediaPlayScript = r"""
(function () {
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
  if (!el) { return 'no-media'; }
  try { el.play(); } catch (e) { return 'error:' + e; }
  return 'play';
})();
""";

const String mediaPauseScript = r"""
(function () {
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
  if (!el) { return 'no-media'; }
  try { el.pause(); } catch (e) { return 'error:' + e; }
  return 'pause';
})();
""";

/// 跳转到指定秒数。
String mediaSeekScript(double seconds) {
  final safe = seconds.isFinite && seconds >= 0 ? seconds : 0;
  return '''
(function () {
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
  if (!el) { return 'no-media'; }
  try { el.currentTime = $safe; } catch (e) { return 'error:' + e; }
  return JSON.stringify({ seeked: el.currentTime, duration: el.duration });
})();
''';
}

/// 设置音量 0..1。
String mediaVolumeScript(double volume) {
  final safe = volume.isFinite ? volume.clamp(0.0, 1.0) : 1.0;
  return '''
(function () {
  var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
  if (!el) { return 'no-media'; }
  el.volume = $safe;
  el.muted = false;
  return 'volume:$safe';
})();
''';
}

/// 只点「歌曲页自己的播放按钮」。
///
/// 关键：绝不能回退到播放栏的播放键——那是"继续上一首"，
/// 会导致点新歌却在放旧歌。只接受标题链接附近的播放控件。
const String neteaseSongPagePlayScript = r"""
(function () {
  var frame = document.querySelector('#g_iframe');
  var doc = frame && frame.contentDocument ? frame.contentDocument : document;
  var selectors = [
    'a.u-btni-addply',
    '.u-btni-addply',
    'a[data-res-action="play"]',
    '.u-btni-play',
    '.u-btni.u-btni-play',
    'a[title="播放"]',
    'button[title="播放"]'
  ];
  for (var i = 0; i < selectors.length; i++) {
    var node = doc.querySelector(selectors[i]);
    if (!node) { continue; }
    // 跳过禁用/置灰的按钮（VIP、无版权曲目会出现）。
    var cls = (node.className || '') + '';
    if (cls.indexOf('dis') !== -1) { continue; }
    try { node.click(); } catch (e) { return 'click-error:' + e; }
    return 'clicked:' + selectors[i];
  }
  return 'no-play-button';
})();
""";

/// 判断当前歌曲页是否是「不可播放」状态（VIP / 无版权 / 下架）。
const String neteaseSongPageBlockedScript = r"""
(function () {
  var frame = document.querySelector('#g_iframe');
  var doc = frame && frame.contentDocument ? frame.contentDocument : document;
  var text = (doc.body && doc.body.innerText) || '';
  if (text.indexOf('无版权') !== -1) { return 'no-copyright'; }
  if (text.indexOf('已下架') !== -1) { return 'removed'; }
  if (text.indexOf('VIP') !== -1 && text.indexOf('播放') === -1) { return 'vip'; }
  return '';
})();
""";

/// 读取当前歌曲页标题，用于确认页面已切到目标曲目。
const String pageTitleScript =
    r"""(function () { return document.title || ''; })();""";

/// 点击官方页面上的「播放」按钮（歌曲页 / 播放栏），用于真正起播。
const String neteaseClickPlayScript = r"""
(function () {
  function clickInDoc(doc) {
    var selectors = [
      'a.u-btni-addply',
      '.u-btni-addply',
      '.u-btni-play',
      '.u-btni.u-btni-play',
      '.m-playbar .btns .ply',
      '.m-playbar .ply'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var node = doc.querySelector(selectors[i]);
      if (node) {
        try { node.click(); } catch (e) { return 'click-error:' + e; }
        return 'clicked:' + selectors[i];
      }
    }
    return '';
  }
  var frame = document.querySelector('#g_iframe');
  var doc = frame && frame.contentDocument ? frame.contentDocument : null;
  var inner = doc ? clickInDoc(doc) : '';
  if (inner) { return inner; }
  var outer = clickInDoc(document);
  return outer || 'no-play-button';
})();
""";

/// 诊断：列出歌曲页里文字为「播放」的元素及其 class，用于定位正确的按钮。
const String neteaseSongPageButtonsScript = r"""
(function () {
  var frame = document.querySelector('#g_iframe');
  var doc = frame && frame.contentDocument ? frame.contentDocument : document;
  var nodes = doc.querySelectorAll('a, button, div, span');
  var found = [];
  for (var i = 0; i < nodes.length && found.length < 12; i++) {
    var text = (nodes[i].textContent || '').trim();
    if (text === '播放' || text === '播放全部') {
      found.push({
        tag: nodes[i].tagName,
        className: nodes[i].className || '',
        id: nodes[i].id || ''
      });
    }
  }
  return JSON.stringify({ hasFrame: !!frame, buttons: found });
})();
""";

/// 诊断：导出官方搜索页的真实结构，用于校准选择器。
const String neteaseSearchDebugScript = r"""
(function () {
  function pickFrame() {
    var frames = document.querySelectorAll('iframe');
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].id === 'g_iframe') { return frames[i]; }
    }
    return frames.length ? frames[0] : null;
  }
  var frame = pickFrame();
  var doc = frame && frame.contentDocument ? frame.contentDocument : document;
  function count(sel) {
    try { return doc.querySelectorAll(sel).length; } catch (e) { return -1; }
  }
  var body = doc.body ? doc.body.innerText || '' : '';
  var sample = [];
  try {
    var nodes = doc.querySelectorAll('a[href*="song?id="]');
    for (var i = 0; i < nodes.length && i < 5; i++) {
      sample.push({
        text: (nodes[i].textContent || '').trim().slice(0, 40),
        title: nodes[i].getAttribute('title') || '',
        href: nodes[i].getAttribute('href') || ''
      });
    }
  } catch (e) {}
  return JSON.stringify({
    frameSrc: frame ? (frame.getAttribute('src') || '') : '',
    frameId: frame ? frame.id : '',
    docTitle: doc.title,
    bodyLen: body.length,
    bodyHead: body.slice(0, 400),
    counts: {
      srchsongst: count('.srchsongst'),
      srchsongstItem: count('.srchsongst .item'),
      mTable: count('table.m-table'),
      mTableTr: count('table.m-table tbody tr'),
      dataResId: count('[data-res-id]'),
      itemClass: count('.item'),
      songLinks: count('a[href*="song?id="]')
    },
    sample: sample
  });
})();
""";

/// 在官方页面里抓取封面字节（返回 base64）。
///
/// 图床会按 UA/Referer 拦截非浏览器请求（Flutter 直连返回 403），
/// 由官方页面自己去取最稳。
String neteaseCoverBytesScript(List<Map<String, String>> items) {
  final payload = items
      .where((e) =>
          RegExp(r'^\d+$').hasMatch(e['id'] ?? '') &&
          (e['url'] ?? '').startsWith('http'))
      .take(20)
      .map((e) => '{"id":"${e['id']}","url":"${e['url']}"}')
      .join(',');
  return '''
(function () {
  window.__dshCoverBytes = { status: 'pending', items: [] };
  var list = [$payload];
  if (!list.length) { window.__dshCoverBytes = { status: 'ok', items: [] }; return 'empty'; }
  var pending = list.length;
  var results = [];
  function done() {
    pending = pending - 1;
    if (pending <= 0) {
      window.__dshCoverBytes = { status: 'ok', items: results };
    }
  }
  list.forEach(function (item) {
    try {
      fetch(item.url, { credentials: 'omit' })
        .then(function (r) { return r.blob(); })
        .then(function (blob) {
          var reader = new FileReader();
          reader.onloadend = function () {
            results.push({ id: item.id, data: String(reader.result || '') });
            done();
          };
          reader.onerror = function () { done(); };
          reader.readAsDataURL(blob);
        })
        .catch(function () { done(); });
    } catch (e) { done(); }
  });
  return 'started';
})();
''';
}

/// 读取封面字节结果。
const String neteaseCoverBytesReadScript =
    r"""(function () { return JSON.stringify(window.__dshCoverBytes || { status: 'none' }); })();""";

/// 批量取封面：官方详情接口返回 `songs[].al.picUrl`。
String neteaseCoverFetchScript(List<String> songIds) {
  final safe = songIds
      .where((id) => RegExp(r'^\d+$').hasMatch(id))
      .take(50)
      .join(',');
  return '''
(function () {
  window.__dshCover = { status: 'pending' };
  if ('$safe' === '') { window.__dshCover = { status: 'ok', items: [] }; return 'empty'; }
  try {
    fetch('/api/song/detail?ids=[$safe]', { credentials: 'include' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        var songs = (data && data.songs) || [];
        var items = [];
        for (var i = 0; i < songs.length; i++) {
          var song = songs[i];
          var album = song.al || song.album || {};
          var pic = album.picUrl || '';
          items.push({ id: String(song.id), pic: pic });
        }
        window.__dshCover = { status: 'ok', items: items };
      })
      .catch(function (error) {
        window.__dshCover = { status: 'error', message: String(error) };
      });
  } catch (error) {
    window.__dshCover = { status: 'error', message: String(error) };
  }
  return 'started';
})();
''';
}

/// 读取封面结果。
const String neteaseCoverReadScript =
    r"""(function () { return JSON.stringify(window.__dshCover || { status: 'none' }); })();""";

/// 在官方页面上下文里取歌词（同源请求，自动带上页面自己的登录态）。
///
/// 返回的 LRC 带时间戳，可驱动逐行同步；没有逐字时间戳时回退逐行。
String neteaseLyricFetchScript(String songId) {
  final safe = RegExp(r'^\d+$').hasMatch(songId) ? songId : '';
  return '''
(function () {
  window.__dshLyric = { status: 'pending' };
  if ('$safe' === '') { window.__dshLyric = { status: 'error', message: 'invalid id' }; return 'invalid'; }
  try {
    fetch('/api/song/lyric?id=$safe&lv=1&tv=-1&kv=1', { credentials: 'include' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        var lrc = (data && data.lrc && data.lrc.lyric) || '';
        var tlyric = (data && data.tlyric && data.tlyric.lyric) || '';
        window.__dshLyric = { status: 'ok', lrc: lrc, tlyric: tlyric };
      })
      .catch(function (error) {
        window.__dshLyric = { status: 'error', message: String(error) };
      });
  } catch (error) {
    window.__dshLyric = { status: 'error', message: String(error) };
  }
  return 'started';
})();
''';
}

/// 读取上一步写入的歌词结果。
const String neteaseLyricReadScript =
    r"""(function () { return JSON.stringify(window.__dshLyric || { status: 'none' }); })();""";

/// 在官方页面上发起搜索（网易云使用 hash 路由）。
String neteaseSearchScript(String query) {
  final encoded = Uri.encodeComponent(query);
  return '''
(function () {
  location.hash = '#/search/m/?s=$encoded&type=1';
  return 'navigated';
})();
''';
}

/// 解析官方搜索结果列表（网易云）。结果在 #g_iframe 内，同源可直接访问。
///
/// 实测结构（2026-10）：`.srchsongst .item`，标题是 `a[href*="song?id="]`，
/// 没有 `.tit` 类；艺人/专辑在 `.td .text` 里。
const String neteaseParseSearchScript = r"""
(function () {
  var frame = document.querySelector('#g_iframe');
  var doc = frame && frame.contentDocument ? frame.contentDocument : document;
  var rows = doc.querySelectorAll('.srchsongst .item');
  var items = [];
  for (var i = 0; i < rows.length && i < 30; i++) {
    var row = rows[i];
    var link = row.querySelector('a[href*="song?id="]');
    if (!link) { continue; }
    var title = (link.textContent || '').trim();
    if (!title) { continue; }

    var id = row.getAttribute('data-res-id') || '';
    if (!id) {
      var m = /song\?id=(\d+)/.exec(link.getAttribute('href') || '');
      if (m) { id = m[1]; }
    }
    if (!id) { continue; }

    var artistNodes = row.querySelectorAll('.td .text a');
    var artists = [];
    for (var j = 0; j < artistNodes.length; j++) {
      var name = (artistNodes[j].textContent || '').trim();
      if (name && artists.indexOf(name) === -1) { artists.push(name); }
    }
    if (!artists.length) {
      var textCell = row.querySelector('.td .text');
      if (textCell) {
        var firstLine = (textCell.textContent || '').split('\n')[0].trim();
        if (firstLine) { artists.push(firstLine.slice(0, 40)); }
      }
    }

    var durationText = '';
    var durationMatch = /(\d{1,2}):(\d{2})/.exec(row.textContent || '');
    if (durationMatch) { durationText = durationMatch[0]; }

    items.push({
      id: id,
      title: title,
      artist: artists.join('/'),
      duration: durationText
    });
  }
  return JSON.stringify({
    count: items.length,
    hasFrame: !!frame,
    href: location.href,
    items: items
  });
})();
""";
