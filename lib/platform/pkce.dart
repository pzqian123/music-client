/// PKCE（RFC 7636）工具：Spotify 公共客户端授权必需。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PkcePair {
  final String verifier;
  final String challenge;
  final String method;

  const PkcePair({
    required this.verifier,
    required this.challenge,
    this.method = 'S256',
  });

  @override
  String toString() => 'PkcePair(method: $method, verifierLength: ${verifier.length})';
}

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// 生成 64 字符的 code verifier（RFC 允许 43–128）。
String generateCodeVerifier([Random? random]) {
  final rng = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 64; i++) {
    buffer.write(_unreserved[rng.nextInt(_unreserved.length)]);
  }
  return buffer.toString();
}

/// BASE64URL(SHA256(verifier))，去掉补位。
String codeChallengeFor(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

PkcePair generatePkcePair([Random? random]) {
  final verifier = generateCodeVerifier(random);
  return PkcePair(verifier: verifier, challenge: codeChallengeFor(verifier));
}

/// 随机 state，用于防止回调被伪造。
String generateState([Random? random]) {
  final rng = random ?? Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(24, (_) => chars[rng.nextInt(chars.length)]).join();
}
