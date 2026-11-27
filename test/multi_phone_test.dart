import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_kadai/app_state.dart';
import 'package:smart_kadai/auth/auth.dart';
import 'package:smart_kadai/billing/bill.dart';
import 'package:smart_kadai/catalogue/product.dart';
import 'package:smart_kadai/customers/customers.dart';
import 'package:smart_kadai/data/database.dart';
import 'package:smart_kadai/data/shop_repository.dart';
import 'package:smart_kadai/sync/phone_link.dart';
import 'package:smart_kadai/sync/shop_host.dart';
import 'package:smart_kadai/sync/shop_server.dart';
import 'package:smart_kadai/voice/speech_service.dart';

/// Ram: staff phones bill through the shop PC over the shop Wi-Fi.
void main() {
  late AppState pc;
  late AppUser owner, kumar;
  late ShopHost phone;
  var phoneLinked = false;

  setUp(() async {
    final repo = ShopRepository(AppDatabase.inMemory())..seedIfEmpty();
    repo
      ..setSetting('setup_done', '1')
      ..setSetting('shop_name', 'Ram Stores');
    pc = AppState(repo);
    owner = pc.auth.createUser('Ram', Role.owner, '1234');
    kumar = pc.auth.createUser('Kumar', Role.staff, '5678');
    pc.login(owner);
    pc.server = ShopServer(pc.sync, port: 0, onChange: pc.refresh);
    await pc.server!.start(address: InternetAddress.loopbackIPv4);
    phoneLinked = false;
    phone = ShopHost(
      openOwn: () => AppDatabase.inMemory(),
      openLinked: () => AppDatabase.inMemory(),
      rememberLinked: (on) async => phoneLinked = on,
      linked: false,
      speech: NoSpeechService(),
    );
  });

  tearDown(() async {
    phone.value.dispose();
    await pc.server!.stop();
  });

  String qr() => PairInfo(
    ['127.0.0.1'],
    pc.server!.port,
    pc.server!.newPairingCode(),
  ).encode();

  Future<AppState> pairPhone(String name) async {
    final d = await PhoneLink.pair(PairInfo.parse(qr())!, name);
    await phone.connect(d);
    return phone.value;
  }

  Product product(AppState s, String name) =>
      s.products.firstWhere((p) => p.nameEn == name);

  test('the QR code reads back', () {
    final i = PairInfo.parse('SMARTKADAI1|192.168.1.5,10.0.0.4|8686|482913')!;
    expect(i.hosts, ['192.168.1.5', '10.0.0.4']);
    expect(i.port, 8686);
    expect(i.code, '482913');
    expect(PairInfo.parse('upi://pay?pa=x'), isNull);
  });

  test('pairing copies products, stock and staff to the phone', () async {
    final s = await pairPhone('Kumar phone');
    expect(phoneLinked, isTrue);
    expect(s.isLinkedPhone, isTrue);
    expect(s.shopName, 'Ram Stores');
    expect(s.products.length, pc.products.length);
    expect(product(s, 'Sugar').stockQty, product(pc, 'Sugar').stockQty);
    // Staff log in on the phone with their own PIN.
    expect(s.auth.users().map((u) => u.name), containsAll(['Ram', 'Kumar']));
    expect(s.auth.verify(kumar.id, '5678')?.name, 'Kumar');
    expect(s.auth.verify(kumar.id, '0000'), isNull);
    expect(pc.sync.devices().single.name, 'Kumar phone');
  });

  test('a wrong or old code is refused', () async {
    pc.server!.newPairingCode();
    final bad = PairInfo(['127.0.0.1'], pc.server!.port, '000000');
    expect(
      () => PhoneLink.pair(bad, 'x'),
      throwsA(isA<LinkException>().having((e) => e.en, 'en', contains('old'))),
    );
  });

  test('no PC on the Wi-Fi says so', () async {
    final none = PairInfo(['127.0.0.1'], 1, '123456');
    expect(
      () => PhoneLink.pair(none, 'x'),
      throwsA(
        isA<LinkException>().having((e) => e.en, 'en', contains('Wi-Fi')),
      ),
    );
  });

  test(
    'a phone bill reaches the PC: one stock, PC numbering, per staff',
    () async {
      pc.handleSpoken('sugar 1 kg', EntryMethod.voice);
      expect(pc.completeBill(PaymentMode.cash), 1);
      final sugarBefore = product(pc, 'Sugar').stockQty;

      final s = await pairPhone('Kumar phone');
      s.login(s.auth.users().firstWhere((u) => u.name == 'Kumar'));
      s.handleSpoken('sugar 2 kg', EntryMethod.voice);
      final total = s.bill.total;
      s.completeBill(PaymentMode.cash);
      expect(s.lastBill!.label, startsWith('M-'));
      await s.sendLastBill();
      // The phone's bill takes the PC's next number.
      expect(s.lastBill!.label, '2');
      expect(s.link!.waiting, 0);

      expect(pc.today.bills, 2);
      expect(product(pc, 'Sugar').stockQty, sugarBefore - 2);
      final r = pc.repo.db
          .select('SELECT * FROM sales WHERE bill_no = 2')
          .first;
      expect(r['user_id'], kumar.id);
      expect(r['total'], total);
      final staff = pc.reports.byStaff(DateTime(2000), DateTime(2100));
      expect(
        staff.map((x) => '${x.name}|${x.where}|${x.bills}'),
        containsAll(['Ram|This PC|1', 'Kumar|Kumar phone|1']),
      );
      // The PC can print it.
      final saved = pc.savedBill(r['id'] as String)!;
      expect(saved.bill.lines.single.product.nameEn, 'Sugar');
      expect(saved.bill.total, total);
      expect(saved.cashier, 'Kumar · Kumar phone');
    },
  );

  test('without Wi-Fi the phone keeps billing and sends later', () async {
    final s = await pairPhone('Counter 2');
    s.login(s.auth.users().first);
    await pc.server!.stop(); // Wi-Fi gone
    s.handleSpoken('salt 1 kg', EntryMethod.voice);
    s.completeBill(PaymentMode.upi);
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.completeBill(PaymentMode.cash);
    await s.sendLastBill();
    expect(s.link!.online, isFalse);
    expect(s.link!.waitingBills, 2);
    expect(s.lastBill!.label, 'M-2');
    expect(pc.today.bills, 0);

    await pc.server!.start(address: InternetAddress.loopbackIPv4);
    await s.link!.syncNow();
    expect(s.link!.online, isTrue);
    expect(s.link!.waiting, 0);
    expect(pc.today.bills, 2);
    // Sending again does not save the bills twice.
    final id = pc.repo.db.select('SELECT id FROM sales LIMIT 1').first['id'];
    s.link!.store.queue(
      'sale',
      s.repo.db.select('SELECT id FROM sales LIMIT 1').first['id'] as String,
    );
    await s.link!.syncNow();
    expect(pc.today.bills, 2);
    expect(id, isNotNull);
  });

  test('credit, new customers and payments from a phone', () async {
    final s = await pairPhone('Kumar phone');
    s.login(s.auth.users().first);
    final c = s.customers.save(
      Customer(id: s.repo.newId(), name: 'Selvi', phone: '9876543210'),
    );
    s.handleSpoken('sugar 1 kg', EntryMethod.voice);
    s.setCustomer(c);
    final total = s.bill.total;
    s.completeBill(PaymentMode.credit);
    await s.sendLastBill();
    expect(pc.customers.byId(c.id)!.balance, total);
    s.customers.receivePayment(c.id, 20, 'CASH');
    await s.link!.syncNow();
    expect(pc.customers.byId(c.id)!.balance, total - 20);
    // The phone shows what the PC says is owed.
    await s.link!.syncNow(pull: true);
    expect(s.customers.byId(c.id)!.balance, total - 20);
  });

  test('a product added on a phone goes to the PC', () async {
    final s = await pairPhone('Owner phone');
    final sugar = product(s, 'Sugar');
    s.saveProduct(sugar.copyWith(sellingPrice: 46));
    final code = s.repo.nextProductCode();
    s.saveProduct(
      sugar.copyWith(
        id: s.repo.newId(),
        code: code,
        nameEn: 'Jaggery',
        nameTa: 'வெல்லம்',
        variants: const [],
      ),
    );
    // Meanwhile the PC used the same code.
    pc.saveProduct(
      product(pc, 'Salt').copyWith(
        id: pc.repo.newId(),
        code: code,
        nameEn: 'Rock salt',
        variants: const [],
      ),
    );
    await s.link!.syncNow(pull: true);
    expect(s.link!.waiting, 0);
    expect(product(pc, 'Sugar').sellingPrice, 46);
    final j = product(pc, 'Jaggery');
    expect(j.code, isNot(code));
    // The phone takes the PC's code back.
    expect(product(s, 'Jaggery').code, j.code);
  });

  test('stock and prices changed on the PC reach the phone', () async {
    final s = await pairPhone('Kumar phone');
    pc.repo.adjustStock(product(pc, 'Sugar').id, 10, 'Delivery');
    pc.saveProduct(product(pc, 'Salt').copyWith(sellingPrice: 30));
    pc.refresh();
    await s.link!.syncNow(pull: true);
    expect(product(s, 'Sugar').stockQty, product(pc, 'Sugar').stockQty);
    expect(product(s, 'Salt').sellingPrice, 30);
  });

  test('a removed phone can no longer send bills', () async {
    final s = await pairPhone('Lost phone');
    pc.sync.removeDevice(pc.sync.devices().single.id);
    s.login(s.auth.users().first);
    s.handleSpoken('salt 1 kg', EntryMethod.voice);
    s.completeBill(PaymentMode.cash);
    await s.link!.syncNow();
    expect(s.link!.removed, isTrue);
    expect(pc.today.bills, 0);
    expect(pc.sync.devices(), isEmpty);
  });

  test('leaving the PC goes back to the phone\'s own shop', () async {
    final s = await pairPhone('Kumar phone');
    expect(s.isLinkedPhone, isTrue);
    await phone.disconnect();
    expect(phoneLinked, isFalse);
    expect(phone.value.isLinkedPhone, isFalse);
  });
}
