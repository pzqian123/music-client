# WebView2 CDP 调试助手（仅用于本地验证，不参与应用运行）
#
# 用途：应用以 DSH_WEBVIEW_DEBUG_PORT=<port> 启动后，WebView2 会开放远程调试端口。
# 本脚本通过 CDP 做两件事：
#   1. -Mode set-cookie：把本机浏览器里已有的 Spotify 会话（sp_dc）注入 WebView2，
#      省掉在应用内重复输入账号密码，便于端到端验证播放链路；
#   2. -Mode eval：在官方页面上下文里执行任意 JS 并打印 JSON 结果。
#
# 示例：
#   .\tool\spotify_cdp_verify.ps1 -Port 9223 -Cookie $spDc -Mode set-cookie
#   .\tool\spotify_cdp_verify.ps1 -Port 9223 -Mode status

param(
  [int]$Port = 9223,
  [string]$Cookie = '',
  [string]$Mode = 'status',
  [string]$Expression = '',
  [string]$NavigateTo = 'https://open.spotify.com/'
)

$ErrorActionPreference = 'Stop'

function Get-PageTarget {
  param([int]$Port)
  $raw = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 10 -UseBasicParsing
  $targets = $raw.Content | ConvertFrom-Json
  $page = $targets | Where-Object { $_.type -eq 'page' -and $_.url -notlike 'about:*' } | Select-Object -First 1
  if (-not $page) { $page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1 }
  if (-not $page) { throw "no page target on port $Port" }
  return $page
}

function Invoke-Cdp {
  param(
    [string]$WsUrl,
    [array]$Commands
  )
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(20))
  [void]$ws.ConnectAsync([Uri]$WsUrl, $cts.Token).GetAwaiter().GetResult()

  $id = 0
  $results = @{}
  foreach ($cmd in $Commands) {
    $id++
    $payload = @{ id = $id; method = $cmd.method; params = $cmd.params } |
      ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$ws.SendAsync(
      [ArraySegment[byte]]::new($bytes),
      [System.Net.WebSockets.WebSocketMessageType]::Text,
      $true,
      [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()

    # 读到匹配 id 的响应为止（事件消息直接跳过）。
    while ($true) {
      $buffer = New-Object byte[] 262144
      $sb = [System.Text.StringBuilder]::new()
      do {
        $seg = [ArraySegment[byte]]::new($buffer)
        $recv = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $recv.Count))
      } while (-not $recv.EndOfMessage)
      $text = $sb.ToString()
      if (-not $text) { continue }
      $msg = $text | ConvertFrom-Json
      if ($msg.id -eq $id) {
        $results[$cmd.method] = $msg
        break
      }
    }
  }
  $ws.Dispose()
  return $results
}

$page = Get-PageTarget -Port $Port
Write-Output "target: $($page.url)"

switch ($Mode) {
  'set-cookie' {
    if (-not $Cookie) { throw 'Cookie is required for set-cookie' }
    $expires = [DateTimeOffset]::UtcNow.AddDays(300).ToUnixTimeSeconds()
    $out = Invoke-Cdp -WsUrl $page.webSocketDebuggerUrl -Commands @(
      @{ method = 'Network.enable'; params = @{} },
      @{ method = 'Network.setCookie'; params = @{
          name = 'sp_dc'
          value = $Cookie
          domain = '.spotify.com'
          path = '/'
          secure = $true
          httpOnly = $true
          sameSite = 'Lax'
          expires = $expires
        } },
      @{ method = 'Page.enable'; params = @{} },
      @{ method = 'Page.navigate'; params = @{ url = $NavigateTo } }
    )
    $set = $out['Network.setCookie']
    Write-Output ("setCookie success={0} error={1}" -f $set.result.success, $set.error.message)
  }
  'eval' {
    if (-not $Expression) { throw 'Expression is required for eval' }
    $out = Invoke-Cdp -WsUrl $page.webSocketDebuggerUrl -Commands @(
      @{ method = 'Runtime.enable'; params = @{} },
      @{ method = 'Runtime.evaluate'; params = @{
          expression = $Expression
          returnByValue = $true
          awaitPromise = $true
        } }
    )
    $res = $out['Runtime.evaluate']
    if ($res.result.exceptionDetails) {
      Write-Output ("exception: {0}" -f $res.result.exceptionDetails.text)
    } else {
      $value = $res.result.result.value
      if ($null -eq $value) { Write-Output 'null' }
      elseif ($value -is [string]) { Write-Output $value }
      else { $value | ConvertTo-Json -Depth 8 -Compress }
    }
  }
  'status' {
    $probe = @'
JSON.stringify({
  url: location.href,
  loggedIn: !!document.querySelector('[data-testid="user-widget-link"]'),
  title: document.title,
  media: (function(){
    var el = window.__dshPickMedia ? window.__dshPickMedia() : null;
    return el ? { paused: el.paused, t: el.currentTime, d: el.duration } : null;
  })(),
  mediaSession: navigator.mediaSession.metadata
    ? { title: navigator.mediaSession.metadata.title, artist: navigator.mediaSession.metadata.artist }
    : null,
  playerPos: (document.querySelector('[data-testid="playback-position"]') || {}).textContent || '',
  playerBtn: (document.querySelector('[data-testid="control-button-playpause"]') || {}).getAttribute
    ? document.querySelector('[data-testid="control-button-playpause"]').getAttribute('aria-label') : ''
})
'@
    $out = Invoke-Cdp -WsUrl $page.webSocketDebuggerUrl -Commands @(
      @{ method = 'Runtime.enable'; params = @{} },
      @{ method = 'Runtime.evaluate'; params = @{
          expression = $probe
          returnByValue = $true
        } }
    )
    $out['Runtime.evaluate'].result.result.value
  }
  default { throw "unknown mode: $Mode" }
}
