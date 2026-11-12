import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardstreet_admin/core/platform/open_url.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('manda la liga completa al lanzador del sistema', () async {
    const url =
        'https://www.google.com/maps/search/?api=1&query=21.09%2C-89.57';

    expect(await hsOpenUrl(url), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'launch');
    expect(
      (calls.single.arguments as Map)['url'],
      url,
      reason: 'la consulta viaja entera; no se corta en el &',
    );
  });

  test('no abre esquemas que no sean http(s)', () async {
    expect(await hsOpenUrl('mailto:hola@hardstreet.mx'), isFalse);
    expect(await hsOpenUrl('javascript:alert(1)'), isFalse);
    expect(calls, isEmpty);
  });
}
