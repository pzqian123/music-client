// 用 Node 跑「生产环境真正注入的」mediaTapScript / mediaStateScript，
// 验证选择器能在 Spotify 那种「一个循环占位视频 + 一个不挂 DOM 的真播放元素」
// 的页面里挑对元素。脚本字符串直接从 Dart 源码里抽，保证测的是同一份代码。
import fs from 'node:fs';
import path from 'node:path';

const dartSource = fs.readFileSync(
  path.join('lib', 'platform', 'web_player_scripts.dart'),
  'utf8',
);

function extractRawString(name) {
  const re = new RegExp(`const String ${name} = r"""([\\s\\S]*?)""";`);
  const match = re.exec(dartSource);
  if (!match) throw new Error(`script not found: ${name}`);
  return match[1];
}

// —— 浏览器最小替身（只实现脚本真正用到的部分）——
class FakeMediaElement {
  constructor(tag = 'VIDEO', opts = {}) {
    this.tagName = tag;
    this.duration = opts.duration ?? 0;
    this.currentTime = 0;
    this.paused = true;
    this.ended = false;
    this.loop = opts.loop ?? false;
    this.volume = 1;
    this.muted = false;
    this.readyState = 4;
    this.parentElement = opts.parent ?? null;
    this.src = '';
    this.currentSrc = `blob:https://open.spotify.com/${Math.random().toString(16).slice(2)}`;
    this.ariaLabel = opts.ariaLabel || '';
    this.textContent = '';
    this.classList = { contains: () => false };
  }
  play() {
    this.paused = false;
    return Promise.resolve();
  }
  pause() {
    this.paused = true;
    return Promise.resolve();
  }
  getAttribute(name) {
    return name === 'aria-label' ? this.ariaLabel : null;
  }
  querySelector() {
    return null;
  }
  querySelectorAll() {
    return [];
  }
  click() {}
}

const domElements = [];
const selectors = new Map();

const documentStub = {
  title: 'Love Story • Taylor Swift',
  body: { innerText: '' },
  createElement(tag) {
    const el = new FakeMediaElement(tag.toUpperCase());
    return el;
  },
  querySelector(selector) {
    return selectors.get(selector) || null;
  },
  querySelectorAll(selector) {
    if (selector === 'audio, video') return domElements;
    return [];
  },
};

const windowStub = {
  Audio: function Audio() {
    return new FakeMediaElement('AUDIO');
  },
};

globalThis.window = windowStub;
globalThis.document = documentStub;
globalThis.Document = documentStub;
globalThis.HTMLMediaElement = FakeMediaElement;
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: {
    mediaSession: {
      metadata: { title: 'Love Story', artist: 'Taylor Swift', album: '' },
    },
  },
});

// 1) 安装注入脚本（与 App 里 AT_DOCUMENT_START 完全一致）。
new Function(extractRawString('mediaTapScript'))();

// 2) 造出 Spotify 实测的两类元素：
//    a. DOM 里的循环占位视频：loop、duration 5.7s；
//    b. 不挂 DOM 的真播放元素：duration 242.19s，正在播放。
const placeholder = new FakeMediaElement('VIDEO', {
  duration: 5.7,
  loop: true,
  parent: { tagName: 'DIV' },
});
placeholder.play();
domElements.push(placeholder);

const realSource = new FakeMediaElement('VIDEO', { duration: 242.19 });
realSource.play();
realSource.currentTime = 61.4;

selectors.set('[data-testid="context-item-link"]', {
  textContent: 'Love Story',
  getAttribute: () => '/album/123',
});
selectors.set('[data-testid="now-playing-widget-v2-byline"]', {
  textContent: 'Taylor Swift',
});
selectors.set('[data-testid="playback-position"]', { textContent: '1:01' });
selectors.set('[data-testid="playback-duration"]', { textContent: '3:56' });
selectors.set('[data-testid="control-button-playpause"]', {
  getAttribute: (name) => (name === 'aria-label' ? '暂停' : ''),
});
selectors.set('[data-testid="cover-art-image"]', {
  getAttribute: () => 'https://i.scdn.co/image/abc',
});

// 3) 生产选择器必须挑到真播放元素。
const picked = windowStub.__dshPickMedia();
const pickedIsReal = picked === realSource;
console.log('picked real source:', pickedIsReal, '| duration:', picked?.duration);

// 4) 生产状态脚本必须报告真实时长/进度/曲名。
const stateScript = extractRawString('mediaStateScript').trim();
const stateBody = stateScript.endsWith(';')
  ? stateScript.slice(0, -1)
  : stateScript;
const state = JSON.parse(new Function(`return ${stateBody}`)());
console.log('state:', JSON.stringify(state));

const failures = [];
if (!pickedIsReal) failures.push('选择器挑错了元素');
if (state.hasMedia !== true) failures.push('hasMedia 应为 true');
if (state.source !== 'element') failures.push('source 应为 element');
if (Math.abs(state.duration - 242.19) > 0.01) failures.push('duration 应为 242.19');
if (Math.abs(state.position - 61.4) > 0.01) failures.push('position 应为 61.4');
if (state.paused !== false) failures.push('正在播放时 paused 应为 false');
if (state.mediaSessionTitle !== 'Love Story') failures.push('曲名应来自 Media Session');
if (state.barDuration !== '3:56') failures.push('播放条时长文本应被读到');
if (state.barPlayLabel !== '暂停') failures.push('播放按钮语义应被读到');

// 5) 页面上只剩占位视频时：允许退化，但不能崩。
windowStub.__dshMediaEls = [];
domElements.length = 0;
const onlyPlaceholder = new FakeMediaElement('VIDEO', {
  duration: 5.7,
  loop: true,
  parent: { tagName: 'DIV' },
});
onlyPlaceholder.play();
domElements.push(onlyPlaceholder);
const fallbackPicked = windowStub.__dshPickMedia();
const fallbackState = JSON.parse(new Function(`return ${stateBody}`)());
console.log(
  'fallback picked loop element:',
  fallbackPicked === onlyPlaceholder,
  '| state duration:',
  fallbackState.duration,
);
if (fallbackPicked !== onlyPlaceholder) failures.push('无真元素时应回落到占位元素');
if (fallbackState.hasMedia !== true) failures.push('退化时仍应报告 hasMedia');

if (failures.length) {
  console.error('FAILED:', failures.join('; '));
  process.exit(1);
}
console.log('OK: injected scripts behave correctly on the Spotify DOM shape');
