import 'dart:convert';

/// Compares two byte lists in time that does not depend on *where* they first
/// differ, only on the length of [a]. A naive `==` on HMAC hex strings bails
/// at the first mismatching character, which in principle leaks how many
/// leading bytes an attacker guessed correctly.
///
/// This is defence-in-depth rather than a fix for a reachable hole: Narraity's
/// signatures are verified against local files, with no network oracle an
/// attacker could time adaptively, and the key is password-derived and never
/// transmitted. It costs almost nothing to be correct here anyway, so the
/// signature checks use it.
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    // Index-guard b so a length mismatch can't throw; the length difference
    // XOR'd into `diff` above already forces the result to false in that case.
    diff |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return diff == 0;
}

/// [constantTimeBytesEqual] for strings — used for the HMAC-hex signature and
/// verifier comparisons. Encodes both sides as UTF-8 bytes first.
bool constantTimeEquals(String a, String b) =>
    constantTimeBytesEqual(utf8.encode(a), utf8.encode(b));
