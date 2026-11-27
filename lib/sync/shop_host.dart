import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/shop_repository.dart';
import '../voice/speech_service.dart';
import 'phone_link.dart';

/// Holds the app's current shop. A phone has two: its own (used alone) and
/// the shop PC's copy (when it bills through the PC). Pairing or leaving
/// the PC switches between them without restarting the app.
class ShopHost extends ValueNotifier<AppState> {
  ShopHost({
    required AppDatabase Function() openOwn,
    required AppDatabase Function() openLinked,
    required this._rememberLinked,
    required bool linked,
    required this.speech,
    this.isPhone = false,
  }) : _openOwn = openOwn,
       _openLinked = openLinked,
       super(_make(linked ? openLinked() : openOwn(), speech, linked)) {
    value.host = this;
    value.link?.start();
  }

  static AppState _make(AppDatabase db, SpeechService speech, bool linked) {
    final repo = ShopRepository(db);
    if (!linked) return AppState(repo..seedIfEmpty(), speech: speech);
    return AppState(repo, speech: speech, link: PhoneLink(repo));
  }

  final AppDatabase Function() _openOwn;
  final AppDatabase Function() _openLinked;
  final Future<void> Function(bool linked) _rememberLinked;
  final SpeechService speech;

  /// Running on a phone, which can join a shop PC.
  final bool isPhone;

  AppState _ownState(AppDatabase db) => _make(db, speech, false)..host = this;

  AppState _linkedState(AppDatabase db) => _make(db, speech, true)..host = this;

  /// Pairs with the PC: takes its products, stock, customers and staff,
  /// then shows the PIN screen with the PC's staff.
  Future<void> connect(LinkDetails d) async {
    final db = _openLinked();
    final s = _linkedState(db);
    s.link!.remember(d);
    if (!await s.link!.pullNow()) {
      s.dispose();
      db.close();
      throw LinkException(
        'Paired, but the products could not be copied from the PC. Try again.',
        'இணைந்தது, ஆனால் பொருட்களை எடுக்க முடியவில்லை. மீண்டும் முயலுங்கள்.',
      );
    }
    s.refresh();
    await _rememberLinked(true);
    _swap(s);
    s.link!.start();
  }

  /// Stops billing through the PC: the phone goes back to its own shop.
  /// Bills not yet sent stay on the phone and go when it pairs again.
  Future<void> disconnect() async {
    await _rememberLinked(false);
    _swap(_ownState(_openOwn()));
  }

  void _swap(AppState next) {
    final old = value;
    value = next;
    // Screens still showing the old shop let go of it first.
    Timer(const Duration(seconds: 2), () {
      old.dispose();
      old.repo.dbHandle.close();
    });
  }
}
