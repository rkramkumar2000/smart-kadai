import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'sync_store.dart';

/// The QR code a phone scans to join the shop PC:
/// `SMARTKADAI1|192.168.1.5,10.0.0.4|8686|482913`.
class PairInfo {
  PairInfo(this.hosts, this.port, this.code);
  final List<String> hosts;
  final int port;
  final String code;

  static const _tag = 'SMARTKADAI1';

  String encode() => '$_tag|${hosts.join(',')}|$port|$code';

  static PairInfo? parse(String text) {
    final parts = text.trim().split('|');
    if (parts.length != 4 || parts[0] != _tag) return null;
    final port = int.tryParse(parts[2]);
    final hosts = parts[1]
        .split(',')
        .where((h) => h.trim().isNotEmpty)
        .toList();
    if (port == null || hosts.isEmpty || parts[3].isEmpty) return null;
    return PairInfo(hosts, port, parts[3]);
  }
}

/// Runs on the shop PC: phones on the shop Wi-Fi send their bills here.
/// No internet is needed. Only phones paired with the QR code get in.
class ShopServer {
  ShopServer(
    this.store, {
    this.port = defaultPort,
    this.onChange,
    this.onPhoneBill,
  });

  static const defaultPort = 8686;

  final SyncStore store;
  int port;

  /// Something a phone sent was saved: the PC screens refresh.
  final void Function()? onChange;

  /// A phone bill was saved, with its sale id: the PC may print it.
  final void Function(String saleId)? onPhoneBill;

  HttpServer? _http;
  String? _code;
  DateTime? _codeUntil;

  bool get running => _http != null;

  /// Starts listening on the shop network. Throws when the port is busy.
  Future<void> start({InternetAddress? address}) async {
    if (_http != null) return;
    final http = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    port = http.port;
    _http = http;
    http.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final h = _http;
    _http = null;
    await h?.close(force: true);
  }

  /// A fresh 6-digit pairing code, good for 15 minutes.
  String newPairingCode() {
    _code = (100000 + Random.secure().nextInt(900000)).toString();
    _codeUntil = DateTime.now().add(const Duration(minutes: 15));
    return _code!;
  }

  /// This PC's addresses on the shop network, Wi-Fi first.
  static Future<List<String>> addresses() async {
    final out = <String>[];
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      list.sort((a, b) {
        int rank(NetworkInterface n) {
          final name = n.name.toLowerCase();
          if (name.contains('wi-fi') ||
              name.contains('wlan') ||
              name.contains('wireless')) {
            return 0;
          }
          if (name.contains('vethernet') ||
              name.contains('virtual') ||
              name.contains('vmware') ||
              name.contains('docker')) {
            return 2;
          }
          return 1;
        }

        return rank(a).compareTo(rank(b));
      });
      for (final n in list) {
        for (final a in n.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) out.add(a.address);
        }
      }
    } on Object {
      // No network: the QR code cannot be made.
    }
    return out;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      final body = req.method == 'POST'
          ? jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, Object?>
          : const <String, Object?>{};
      final out = _route(req, body);
      res.write(jsonEncode(out));
    } on _HttpError catch (e) {
      res.statusCode = e.status;
      res.write(jsonEncode({'error': e.message}));
    } on Object catch (e) {
      res.statusCode = 500;
      res.write(jsonEncode({'error': '$e'}));
    }
    await res.close();
  }

  Map<String, Object?> _route(HttpRequest req, Map<String, Object?> body) {
    final path = req.uri.path;
    if (path == '/api/hello') {
      return {
        'app': 'smart-kadai',
        'shop': store.repo.setting('shop_name', 'Smart Kadai'),
      };
    }
    if (path == '/api/pair' && req.method == 'POST') {
      final ok =
          _code != null &&
          body['code'] == _code &&
          DateTime.now().isBefore(_codeUntil!);
      if (!ok) throw _HttpError(403, 'Wrong or old pairing code');
      final d = store.addDevice('${body['name'] ?? 'Phone'}');
      return {
        'deviceId': d.id,
        'token': d.token,
        'shop': store.repo.setting('shop_name', 'Smart Kadai'),
      };
    }
    final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final device = store.deviceFor(
      auth.startsWith('Bearer ') ? auth.substring(7) : '',
    );
    if (device == null) throw _HttpError(401, 'This phone is not paired');
    switch ((req.method, path)) {
      case ('GET', '/api/snapshot'):
        return store.snapshot();
      case ('POST', '/api/sale'):
        final no = store.receiveSale(body, device.id);
        onChange?.call();
        onPhoneBill?.call((body['sale'] as Map)['id'] as String);
        return {'billNo': no};
      case ('POST', '/api/product'):
        final code = store.receiveProduct(body);
        onChange?.call();
        return {'code': code};
      case ('POST', '/api/customer'):
        store.receiveCustomer(body);
        onChange?.call();
        return {};
      case ('POST', '/api/customer_payment'):
        store.receivePayment(body);
        onChange?.call();
        return {};
    }
    throw _HttpError(404, 'Not found');
  }
}

class _HttpError implements Exception {
  _HttpError(this.status, this.message);
  final int status;
  final String message;
}
