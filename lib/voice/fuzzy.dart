import 'dart:math' as math;

/// Jaro-Winkler similarity between two strings, 0 (different) to 1 (same).
/// Good for short words with small spelling or hearing differences.
double jaroWinkler(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final range = math.max(0, math.max(a.length, b.length) ~/ 2 - 1);
  final aMatched = List<bool>.filled(a.length, false);
  final bMatched = List<bool>.filled(b.length, false);
  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final lo = math.max(0, i - range);
    final hi = math.min(i + range + 1, b.length);
    for (var j = lo; j < hi; j++) {
      if (bMatched[j] || a[i] != b[j]) continue;
      aMatched[i] = true;
      bMatched[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;
  var t = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!aMatched[i]) continue;
    while (!bMatched[k]) {
      k++;
    }
    if (a[i] != b[k]) t++;
    k++;
  }
  final m = matches.toDouble();
  final jaro = (m / a.length + m / b.length + (m - t / 2) / m) / 3;
  var prefix = 0;
  for (var i = 0; i < math.min(4, math.min(a.length, b.length)); i++) {
    if (a[i] != b[i]) break;
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

/// Similarity between a spoken phrase and a product name, both as lists of
/// sound-key words.
///
/// Every spoken word looks for its best partner in the name. Short spoken
/// names ("hamam" for "hamam soap") still score high, while a name that
/// covers more of the spoken words wins over one that covers fewer.
double phraseSimilarity(List<String> spoken, List<String> name) {
  if (spoken.isEmpty || name.isEmpty) return 0;
  final whole = jaroWinkler(spoken.join(), name.join());
  var sum = 0.0;
  final used = <int>{};
  for (final s in spoken) {
    var best = 0.0;
    var bestJ = -1;
    for (var j = 0; j < name.length; j++) {
      var sim = jaroWinkler(s, name[j]);
      // A clear prefix ("choco" for "chocolate") is a good sign.
      if (s.length >= 3 && name[j].startsWith(s)) sim = math.max(sim, 0.92);
      if (sim > best) {
        best = sim;
        bestJ = j;
      }
    }
    if (bestJ >= 0) used.add(bestJ);
    sum += best;
  }
  final perWord = sum / spoken.length;
  final coverage = used.length / name.length;
  final tokenScore = perWord * (0.88 + 0.12 * coverage);
  return math.max(tokenScore, whole * 0.97);
}
