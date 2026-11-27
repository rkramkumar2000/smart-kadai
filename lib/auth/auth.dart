import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';

enum Role {
  owner('OWNER', 'Owner', 'உரிமையாளர்'),
  staff('STAFF', 'Staff', 'பணியாளர்');

  const Role(this.code, this.label, this.tamil);
  final String code;
  final String label;
  final String tamil;

  static Role fromCode(String c) =>
      Role.values.firstWhere((r) => r.code == c, orElse: () => Role.staff);
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
  });

  final String id;
  final String name;
  final Role role;
  final bool active;

  bool get isOwner => role == Role.owner;

  // What staff may not do. Owners can do everything.
  bool get canEditProducts => isOwner;
  bool get canSeeProfit => isOwner;
  bool get canCorrectStock => isOwner;
  bool get canManageUsers => isOwner;
  bool get canChangeSettings => isOwner;
}

/// Thrown after too many wrong PINs; the owner waits before trying again.
class PinLockedException implements Exception {
  PinLockedException(this.waitSeconds);
  final int waitSeconds;
}

/// Users and 4-digit PINs. PINs are never stored: only a salted hash,
/// stretched with many rounds so a copied database does not reveal them.
class AuthRepository {
  AuthRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;
  static const _uuid = Uuid();
  static const _rounds = 20000;
  static const maxTries = 5;
  static const lockSeconds = 30;

  final Map<String, int> _failures = {};
  final Map<String, DateTime> _lockedUntil = {};

  /// For tests: a clock that can be moved.
  DateTime Function() now = DateTime.now;

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  bool get hasOwner => _db
      .select("SELECT 1 FROM users WHERE role = 'OWNER' AND active = 1 LIMIT 1")
      .isNotEmpty;

  List<AppUser> users({bool includeInactive = false}) => _db
      .select(
        'SELECT * FROM users ${includeInactive ? '' : 'WHERE active = 1'} '
        "ORDER BY role = 'OWNER' DESC, name COLLATE NOCASE",
      )
      .map(_user)
      .toList();

  AppUser createUser(String name, Role role, String pin) {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be 4 digits');
    final id = _uuid.v4();
    final salt = _salt();
    _db.execute(
      'INSERT INTO users (id, name, role, pin_hash, pin_salt, active, created_at) VALUES (?,?,?,?,?,1,?)',
      [
        id,
        name.trim(),
        role.code,
        _hash(pin, salt),
        salt,
        now().toIso8601String(),
      ],
    );
    return AppUser(id: id, name: name.trim(), role: role, active: true);
  }

  /// Returns the user when [pin] is right, null when wrong.
  /// Throws [PinLockedException] after [maxTries] wrong PINs in a row.
  AppUser? verify(String userId, String pin) {
    final until = _lockedUntil[userId];
    if (until != null && now().isBefore(until)) {
      throw PinLockedException(until.difference(now()).inSeconds + 1);
    }
    final rows = _db.select('SELECT * FROM users WHERE id = ? AND active = 1', [
      userId,
    ]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final ok = _constantTimeEquals(
      _hash(pin, r['pin_salt'] as String),
      r['pin_hash'] as String,
    );
    if (ok) {
      _failures.remove(userId);
      _lockedUntil.remove(userId);
      return _user(r);
    }
    final n = (_failures[userId] ?? 0) + 1;
    _failures[userId] = n;
    if (n >= maxTries) {
      _failures.remove(userId);
      _lockedUntil[userId] = now().add(const Duration(seconds: lockSeconds));
      throw PinLockedException(lockSeconds);
    }
    return null;
  }

  void changePin(String userId, String newPin) {
    if (!isValidPin(newPin)) throw ArgumentError('PIN must be 4 digits');
    final salt = _salt();
    _db.execute('UPDATE users SET pin_hash = ?, pin_salt = ? WHERE id = ?', [
      _hash(newPin, salt),
      salt,
      userId,
    ]);
  }

  void rename(String userId, String name) => _db.execute(
    'UPDATE users SET name = ? WHERE id = ?',
    [name.trim(), userId],
  );

  /// Turns a staff login off or on. The last owner cannot be turned off.
  void setActive(String userId, bool active) {
    if (!active) {
      final owners = _db.select(
        "SELECT id FROM users WHERE role = 'OWNER' AND active = 1",
      );
      if (owners.length == 1 && owners.first['id'] == userId) {
        throw StateError('The shop needs at least one owner.');
      }
    }
    _db.execute('UPDATE users SET active = ? WHERE id = ?', [
      active ? 1 : 0,
      userId,
    ]);
  }

  AppUser _user(Row r) => AppUser(
    id: r['id'] as String,
    name: r['name'] as String,
    role: Role.fromCode(r['role'] as String),
    active: (r['active'] as int) == 1,
  );

  static String _salt() {
    final rnd = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static String _hash(String pin, String salt) {
    final saltBytes = utf8.encode(salt);
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < _rounds; i++) {
      bytes = sha256.convert([...bytes, ...saltBytes]).bytes;
    }
    return base64Url.encode(bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
