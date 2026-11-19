/// Spotify 官方网页播放器（open.spotify.com）的注入脚本。
///
/// 全部选择器均在真实登录会话里核对过（2026-11，Chrome 156）：
///
/// - 播放元素是 `document.createElement('video')` 创建后**不挂 DOM** 的对象，
///   `querySelectorAll('video')` 抓到的是 5.7 秒循环的占位视频，不是音频源。
///   因此必须靠 [mediaTapScript] 在文档开始时劫持登记（见 web_player_scripts.dart）。
/// - 播放条：`[data-testid="context-item-link"]`（曲名）、
///   `[data-testid="now-playing-widget-v2-byline"]`（艺人）、
///   `[data-testid="playback-position"]` / `playback-duration`（时间）。
/// - 控制：`[data-testid="control-button-playpause"]`、`skip-forward`、`skip-back`。
/// - 搜索结果：`[data-testid="tracklist-row"]` 内 `a[href*="/track/"]`。
/// - 曲目页大按钮：`[data-testid="action-bar-row"] [data-testid="play-button"]`，
///   播放中 aria-label 会变成「暂停」。
///
/// 重要实测结论：直接设置播放元素 `currentTime` 会让官方界面同步跳转，
/// 调 `pause()` 会让官方界面切到暂停且进度冻结，所以播放控制以元素为准，
/// 官方按钮只作为兜底。
library;

/// 打开 Spotify 搜索结果（曲目页签）。
String spotifySearchScript(String query) {
  final encoded = Uri.encodeComponent(query.trim());
  return '''
(function () {
  location.href = 'https://open.spotify.com/search/$encoded/tracks';
  return 'navigated';
})();
''';
}

/// 解析搜索结果列表。
///
/// 返回 `{count, href, items:[{id,title,artist,duration,cover}]}`。
const String spotifyParseSearchScript = r"""
(function () {
  function text(node) {
    return node ? (node.textContent || '').replace(/\s+/g, ' ').trim() : '';
  }
  var rows = document.querySelectorAll('[data-testid="tracklist-row"]');
  var items = [];
  for (var i = 0; i < rows.length && items.length < 30; i++) {
    var row = rows[i];
    var link = row.querySelector('a[href*="/track/"]');
    if (!link) { continue; }
    var href = link.getAttribute('href') || '';
    var match = /\/track\/([A-Za-z0-9]+)/.exec(href);
    if (!match) { continue; }
    var title = text(link);
    if (!title) { continue; }

    var artists = [];
    var nodes = row.querySelectorAll('a[href*="/artist/"]');
    for (var j = 0; j < nodes.length; j++) {
      var name = text(nodes[j]);
      if (name && artists.indexOf(name) === -1) { artists.push(name); }
    }

    var cells = row.querySelectorAll('[role="gridcell"]');
    var duration = '';
    for (var k = cells.length - 1; k >= 0; k--) {
      var cellText = text(cells[k]);
      if (/^\d{1,2}:\d{2}$/.test(cellText)) { duration = cellText; break; }
    }

    var img = row.querySelector('img');
    items.push({
      id: match[1],
      title: title,
      artist: artists.join('/'),
      duration: duration,
      cover: img ? (img.getAttribute('src') || '') : ''
    });
  }
  return JSON.stringify({
    count: items.length,
    href: location.href,
    title: document.title,
    items: items
  });
})();
""";

/// 点击曲目页的大播放按钮；已经在播就返回 `already-playing`。
const String spotifyTrackPlayScript = r"""
(function () {
  var btn = document.querySelector('[data-testid="action-bar-row"] [data-testid="play-button"]')
    || document.querySelector('[data-testid="play-button"]');
  if (!btn) { return 'no-play-button'; }
  var label = (btn.getAttribute('aria-label') || '').toLowerCase();
  btn.setAttribute('data-dsh-seen', label);
  if (label.indexOf('暂停') !== -1 || label.indexOf('pause') !== -1) {
    return 'already-playing';
  }
  try { btn.click(); } catch (e) { return 'click-error:' + e; }
  return 'clicked';
})();
""";

/// 点击播放条上的播放/暂停（元素控制失效时的兜底）。
const String spotifyTogglePlayScript = r"""
(function () {
  var btn = document.querySelector('[data-testid="control-button-playpause"]');
  if (!btn) { return 'no-toggle'; }
  var before = btn.getAttribute('aria-label') || '';
  try { btn.click(); } catch (e) { return 'click-error:' + e; }
  return JSON.stringify({ before: before });
})();
""";

/// 上一首 / 下一首（官方播放条）。
String spotifySkipScript({required bool forward}) {
  final testId = forward
      ? 'control-button-skip-forward'
      : 'control-button-skip-back';
  return '''
(function () {
  var btn = document.querySelector('[data-testid="$testId"]');
  if (!btn) { return 'no-button'; }
  try { btn.click(); } catch (e) { return 'click-error:' + e; }
  return 'clicked';
})();
''';
}

/// 登录状态探测：登录后播放条右侧一定存在用户菜单。
///
/// 未登录时页面会停在 `/` 或登录页，只有「登录」入口。
const String spotifyLoginStateScript = r"""
(function () {
  function text(node) {
    return node ? (node.textContent || '').replace(/\s+/g, ' ').trim() : '';
  }
  var user = document.querySelector('[data-testid="user-widget-link"]');
  var bar = document.querySelector('[data-testid="now-playing-bar"]');
  var login = document.querySelector(
    '[data-testid="login-button"], a[href*="/login"], button[data-testid="login-button"]'
  );
  var bodyText = (document.body && document.body.innerText) || '';
  var needsLogin = /登录|Log in|Sign in/i.test(
    text(login) || (login ? 'login' : '')
  );
  return JSON.stringify({
    loggedIn: !!user,
    hasPlayerBar: !!bar,
    hasLoginEntry: !!login,
    looksLikeLoginPage: !user && needsLogin && !bar,
    href: location.href,
    title: document.title,
    bodyHead: bodyText.slice(0, 160)
  });
})();
""";

/// 打开插件的「歌词」面板（Spotify 的歌词是官方内嵌视图，可选）。
const String spotifyOpenLyricsScript = r"""
(function () {
  var btn = document.querySelector('[data-testid="lyrics-button"]');
  if (!btn) { return 'no-button'; }
  try { btn.click(); } catch (e) { return 'click-error:' + e; }
  return 'clicked';
})();
""";

/// 读取当前曲目在官方页面上的封面（播放条 640px 封面）。
const String spotifyCurrentCoverScript = r"""
(function () {
  var img = document.querySelector('[data-testid="cover-art-image"]');
  if (!img) { return ''; }
  return img.getAttribute('src') || '';
})();
""";

/// 把 64px 列表封面升级成 640px 版本（Spotify CDN 用同一 hash，只改尺寸段）。
String upgradeSpotifyCover(String url) {
  if (url.isEmpty) return url;
  return url
      .replaceAll('ab67616d00004851', 'ab67616d0000b273')
      .replaceAll('ab67616d00001e02', 'ab67616d0000b273');
}
