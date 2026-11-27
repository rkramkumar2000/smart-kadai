import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/shop_repository.dart';
import 'shop_server.dart';
import 'sync_store.dart';

/// What pairing with the PC returned.
class LinkDetails {
  LinkDetails({
    required this.url,
    required this.token,
    required this.deviceId,
    required this.shop,
    required this.phoneName,
  });
  final String url;
  final String token;
  final String deviceId;
  final String shop;
  final String phoneName;
}

/// Thrown when pairing fails, with a message for the owner.
class LinkException implements Exception {
  LinkException(this.en, this.ta);
  final String en;
  final String ta;
  @override
  String toString() => en;
}

/// Runs on a staff phone that bills through the shop PC. Bills are saved on
/// the phone first, so billing never waits for Wi-Fi, and sent to the PC
/// as soon as it can be reached.
class PhoneLink extends ChangeNotifier {
  PhoneLink(this.repo) : store = SyncStore(repo) {
    repo.onLocalChange = (kind, id) {
      store.queue(kind, id);
      _changed();
      // Send it straight away when the PC is there.
      if (_timer != null) unawaited(syncNow());
    };
  }

  final ShopRepository repo;
  final SyncStore store;

  String get url => repo.setting('link_url');
  String get token => repo.setting('link_token');
  String get deviceId => repo.setting('link_device_id');
  String get phoneName => repo.setting('link_phone_name', 'Phone');
  String get pcShop => repo.setting('link_shop', 'Shop PC');

  /// The PC answered the last time it was tried.
  bool online = false;

  /// The PC said this phone is no longer allowed (removed on the PC).
  bool removed = false;
  DateTime? lastSync;
  String? lastError;
  int get waiting => store.waiting;
  int get waitingBills => store.waitingBills;

  Timer? _timer;
  DateTime? _lastPull;

  static const _timeout = Duration(seconds: 6);

  /// Saves the PC's address and this phone's pass on the phone.
  void remember(LinkDetails d) {
    repo
      ..setSetting('link_url', d.url)
      ..setSetting('link_token', d.token)
      ..setSetting('link_device_id', d.deviceId)
      ..setSetting('link_shop', d.shop)
      ..setSetting('link_phone_name', d.phoneName);
  }

  /// Finds the PC from its QR code and pairs this phone with it.
  static Future<LinkDetails> pair(PairInfo info, String phoneName) async {
    String? found;
    for (final h in info.hosts) {
      final url = 'http://$h:${info.port}';
      try {
        final r = await _call(
          'GET',
          '$url/api/hello',
          timeout: const Duration(seconds: 3),
        );
        if (r['app'] == 'smart-kadai') {
          found = url;
          break;
        }
      } on Object {
        // Try the next address.
      }
    }
    if (found == null) {
      throw LinkException(
        'Could not reach the shop PC. Check that this phone is on the same Wi-Fi as the PC, and that "Phones can bill through this PC" is on.',
        'கடை கணினியை அடைய முடியவில்லை. போனும் கணினியும் ஒரே Wi-Fi-ல் உள்ளதா என்று பாருங்கள்.',
      );
    }
    final Map<String, Object?> r;
    try {
      r = await _call(
        'POST',
        '$found/api/pair',
        body: {'code': info.code, 'name': phoneName},
      );
    } on _Status catch (e) {
      if (e.status == 403) {
        throw LinkException(
          'The QR code is old. Press "Pair a phone" on the PC again and scan the new code.',
          'QR பழையது. கணினியில் மீண்டும் "Pair a phone" அழுத்தி புதிய QR-ஐ ஸ்கேன் செய்யுங்கள்.',
        );
      }
      rethrow;
    }
    return LinkDetails(
      url: found,
      token: r['token'] as String,
      deviceId: r['deviceId'] as String,
      shop: r['shop'] as String? ?? 'Shop PC',
      phoneName: phoneName,
    );
  }

  /// Sends waiting bills every few seconds and takes the PC's latest
  /// products, stock and customers every half minute.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => syncNow());
    unawaited(syncNow(pull: true));
  }

  /// Sends what is waiting, then takes the PC's latest copy once nothing
  /// is waiting. Returns true when the PC was reached.
  Future<bool> syncNow({bool pull = false}) async {
    if (url.isEmpty) return false;
    // One at a time: wait for a send already on its way, then go again.
    while (_running != null) {
      await _running;
    }
    final run = _sync(pull);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  Future<bool>? _running;

  Future<bool> _sync(bool pull) async {
    try {
      final sentAny = await _push();
      final due =
          _lastPull == null ||
          DateTime.now().difference(_lastPull!) > const Duration(seconds: 30);
      if (online && store.waiting == 0 && (pull || sentAny || due)) {
        await _pull();
      }
      return online;
    } on Object {
      return false;
    } finally {
      _changed();
    }
  }

  /// Takes the PC's products, stock, customers and staff now.
  Future<bool> pullNow() async {
    if (url.isEmpty) return false;
    try {
      await _pull();
      return true;
    } on Object {
      return false;
    } finally {
      _changed();
    }
  }

  Future<bool> _push() async {
    var sentAny = false;
    for (final item in store.outbox()) {
      final body = store.payload(item.kind, item.refId);
      if (body == null) {
        store.sent(item.id);
        continue;
      }
      try {
        final r = await _call(
          'POST',
          '$url/api/${item.kind}',
          body: body,
          token: token,
        );
        if (item.kind == 'sale' && r['billNo'] is int) {
          store.setPcBillNo(item.refId, r['billNo'] as int);
        }
        store.sent(item.id);
        sentAny = true;
        online = true;
        lastSync = DateTime.now();
        lastError = null;
      } on _Status catch (e) {
        online = true;
        if (e.status == 401) removed = true;
        lastError = e.message;
        store.failed(item.id, e.message);
        // Keep the order: a bill waits for the product it uses.
        return sentAny;
      } on Object catch (e) {
        online = false;
        lastError = '$e';
        return sentAny;
      }
    }
    if (!sentAny && store.waiting == 0) {
      // Nothing to send: check the PC is there.
      try {
        await _call(
          'GET',
          '$url/api/hello',
          timeout: const Duration(seconds: 3),
        );
        online = true;
      } on Object {
        online = false;
      }
    }
    return sentAny;
  }

  Future<void> _pull() async {
    try {
      final snap = await _call('GET', '$url/api/snapshot', token: token);
      // A bill made while the copy was on its way waits for the next one.
      if (store.waiting > 0) return;
      store.applySnapshot(snap);
      _lastPull = DateTime.now();
      lastSync = _lastPull;
      online = true;
      removed = false;
      onPulled?.call();
    } on _Status catch (e) {
      if (e.status == 401) removed = true;
      rethrow;
    } on Object {
      online = false;
      rethrow;
    }
  }

  /// Called after the PC's latest copy is on the phone.
  VoidCallback? onPulled;

  void _changed() {
    if (hasListeners) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (repo.onLocalChange != null) repo.onLocalChange = null;
    super.dispose();
  }

  static Future<Map<String, Object?>> _call(
    String method,
    String url, {
    Map<String, Object?>? body,
    String? token,
    Duration timeout = _timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, Uri.parse(url)).timeout(timeout);
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await utf8.decoder.bind(res).join().timeout(timeout);
      final json = text.isEmpty
          ? <String, Object?>{}
          : jsonDecode(text) as Map<String, Object?>;
      if (res.statusCode != 200) {
        throw _Status(
          res.statusCode,
          '${json['error'] ?? 'Error ${res.statusCode}'}',
        );
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }
}

class _Status implements Exception {
  _Status(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}
