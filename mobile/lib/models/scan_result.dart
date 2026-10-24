String? _str(dynamic v) {
  if (v == null) return null;
  final String s = v.toString().trim();
  return s.isEmpty ? null : s;
}

double? _num(dynamic v) {
  if (v == null) return null;
  final double? n = v is num ? v.toDouble() : double.tryParse(v.toString());
  if (n == null) return null;
  return n <= 1 ? n * 100 : n;
}

class MatchResult {
  final String? platform;
  final String? handle;
  final double? score;
  final String? profileUrl;
  final String? previewUrl;

  const MatchResult({
    this.platform,
    this.handle,
    this.score,
    this.profileUrl,
    this.previewUrl,
  });

  factory MatchResult.fromJson(Map<String, dynamic> j) {
    return MatchResult(
      platform: _str(j['platform'] ?? j['source'] ?? j['site']),
      handle: _str(j['handle'] ?? j['username']),
      score: _num(j['score'] ?? j['match_score'] ?? j['similarity']),
      profileUrl: _str(j['profile_url'] ?? j['url'] ?? j['link']),
      previewUrl: _str(j['preview_url'] ?? j['thumbnail'] ?? j['image_url']),
    );
  }
}

class ScanState {
  final String id;
  final String status;
  final int? credits;
  final List<MatchResult> matches;
  final String? errorMessage;

  const ScanState({
    required this.id,
    required this.status,
    this.credits,
    this.matches = const [],
    this.errorMessage,
  });

  bool get isCompleted =>
      const ['completed', 'complete', 'done', 'finished', 'success']
          .contains(status);

  bool get isFailed =>
      const ['failed', 'error', 'cancelled', 'canceled'].contains(status);

  bool get isFinished => isCompleted || isFailed;

  factory ScanState.fromJson(Map<String, dynamic> raw) {
    final dynamic inner = raw['data'];
    final Map<String, dynamic> j =
        inner is Map<String, dynamic> ? inner : raw;

    final dynamic list = j['matches'] ?? j['results'];
    final List<MatchResult> matches = [];
    if (list is List) {
      for (final dynamic item in list) {
        if (item is Map<String, dynamic>) {
          matches.add(MatchResult.fromJson(item));
        }
      }
    }

    final dynamic credits =
        j['credits'] ?? j['credits_remaining'] ?? raw['credits'];

    return ScanState(
      id: _str(j['id'] ?? j['scan_id']) ?? '',
      status: (_str(j['status']) ?? 'queued').toLowerCase(),
      credits: credits is num ? credits.toInt() : int.tryParse('$credits'),
      matches: matches,
      errorMessage: _str(j['error'] ?? j['message']),
    );
  }
}
