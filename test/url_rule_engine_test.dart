import 'package:charge_quick/models/app_settings.dart';
import 'package:charge_quick/models/charging_station.dart';
import 'package:charge_quick/services/url_rule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlRuleEngine', () {
    test('extractSerialNumber extracts uppercase SN from raw URL or OCR text',
        () {
      expect(
        UrlRuleEngine.extractSerialNumber(
          'https://charge.example.com/start?sn=w52001715&from=qr',
        ),
        'W52001715',
      );
      expect(
        UrlRuleEngine.extractSerialNumber('NO. w52001414  220V'),
        'W52001414',
      );
      expect(
        UrlRuleEngine.extractSerialNumber('invalid text without serial'),
        isNull,
      );
    });

    test('extractBaseTemplateFromUrl replaces serial with {SN}', () {
      expect(
        UrlRuleEngine.extractBaseTemplateFromUrl(
          'https://charge.example.com/start?sn=W52001715&v=2',
          'W52001715',
        ),
        'https://charge.example.com/start?sn={SN}&v=2',
      );
    });

    test('buildTargetUri prioritizes customDeepLinkTemplate over global and raw',
        () {
      final station = ChargingStation(
        id: '1',
        alias: 'B2-A区 1号桩',
        serialNumber: 'W52001715',
        rawUrl: 'https://raw.example.com?sn=W52001715',
        customDeepLinkTemplate: 'weixin://dl/business/?t=FIXED_TICKET',
        lastUsedPort: 3,
        lastUsedDate: DateTime(2026, 1, 1),
      );
      const settings = AppSettings(
        ruleMode: UrlRuleMode.globalTemplate,
        globalUrlTemplate:
            'alipays://platformapi/startapp?appId=123&query=sn%3D{SN}%26port%3D{PORT}',
      );

      final uri = UrlRuleEngine.buildTargetUri(station, 5, settings);
      expect(uri.toString(), 'weixin://dl/business/?t=FIXED_TICKET');
    });

    test('buildTargetUri uses globalTemplate when globalTemplate mode active',
        () {
      final station = ChargingStation(
        id: '2',
        alias: 'B2-B区 2号桩',
        serialNumber: 'W52001414',
        rawUrl: 'https://raw.example.com?sn=W52001414',
        lastUsedPort: 2,
        lastUsedDate: DateTime(2026, 1, 1),
      );
      const settings = AppSettings(
        ruleMode: UrlRuleMode.globalTemplate,
        globalUrlTemplate:
            'alipays://platformapi/startapp?appId=2021000000000000&query=sn%3D{SN}%26port%3D{PORT}',
      );

      final uri = UrlRuleEngine.buildTargetUri(station, 7, settings);
      expect(
        uri.toString(),
        'alipays://platformapi/startapp?appId=2021000000000000&query=sn%3DW52001414%26port%3D7',
      );
    });

    test('buildTargetUri falls back to rawUrl in rawUrlFirst mode', () {
      final station = ChargingStation(
        id: '3',
        alias: 'B2-C区 3号桩',
        serialNumber: 'W52001999',
        rawUrl: 'https://raw.example.com/pay?sn=W52001999&port={PORT}',
        lastUsedPort: 1,
        lastUsedDate: DateTime(2026, 1, 1),
      );
      const settings = AppSettings(
        ruleMode: UrlRuleMode.rawUrlFirst,
        globalUrlTemplate: 'https://global.example.com?sn={SN}',
      );

      final uri = UrlRuleEngine.buildTargetUri(station, 4, settings);
      expect(
        uri.toString(),
        'https://raw.example.com/pay?sn=W52001999&port=4',
      );
    });

    test('real WeiYunChong QR codes (W52001414 & W52001715) end-to-end parsing',
        () {
      const qr1 =
          'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001414';
      const qr2 =
          'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715';

      final sn1 = UrlRuleEngine.extractSerialNumber(qr1);
      final sn2 = UrlRuleEngine.extractSerialNumber(qr2);
      expect(sn1, 'W52001414');
      expect(sn2, 'W52001715');

      final baseTemplate = UrlRuleEngine.extractBaseTemplateFromUrl(qr1, sn1!);
      expect(
        baseTemplate,
        'http://weixin.weiyunchong.com/payQRcode.html?device_no={SN}',
      );

      final alipayTemplate = UrlRuleEngine.buildAlipayH5Template(baseTemplate);
      expect(
        alipayTemplate,
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3D{SN}',
      );

      const defaultSettings = AppSettings();
      final station1 = ChargingStation(
        id: 'qr1',
        alias: '车库桩 1414',
        serialNumber: sn1,
        rawUrl: qr1,
        lastUsedPort: 8,
        lastUsedDate: DateTime(2026, 11, 26),
      );
      final station2 = ChargingStation(
        id: 'qr2',
        alias: '车库桩 1715',
        serialNumber: sn2!,
        rawUrl: qr2,
        lastUsedPort: 9,
        lastUsedDate: DateTime(2026, 11, 26),
      );

      expect(
        UrlRuleEngine.buildTargetUri(station1, 8, defaultSettings).toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001414',
      );
      expect(
        UrlRuleEngine.buildTargetUri(station2, 9, defaultSettings).toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715',
      );
    });

    test('supports {RAW_URL_ENCODED} and falls back cleanly when rawUrl empty',
        () {
      const settings = AppSettings(
        ruleMode: UrlRuleMode.globalTemplate,
        globalUrlTemplate:
            'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_ENCODED}',
      );

      final withRaw = ChargingStation(
        id: 'raw1',
        alias: '微云充 1715',
        serialNumber: 'W52001715',
        rawUrl:
            'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715',
        lastUsedDate: DateTime(2026, 11, 26),
      );
      expect(
        UrlRuleEngine.buildTargetUri(withRaw, 3, settings).toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715',
      );

      final withoutRaw = ChargingStation(
        id: 'raw2',
        alias: '手动输入桩',
        serialNumber: 'W52001414',
        rawUrl: '',
        lastUsedDate: DateTime(2026, 11, 26),
      );
      expect(UrlRuleEngine.buildTargetUri(withoutRaw, 3, settings), isNull);
    });

    test('validateRegex and validateTemplate catch invalid inputs', () {
      expect(UrlRuleEngine.validateRegex(r'W\d{8}'), isNull);
      expect(UrlRuleEngine.validateRegex('[unclosed'), isNotNull);

      expect(
        UrlRuleEngine.validateTemplate(AppSettings.defaultGlobalTemplate),
        isNull,
      );
      expect(UrlRuleEngine.validateTemplate(''), isNotNull);
      expect(UrlRuleEngine.validateTemplate('no-scheme-url/{SN}'), isNotNull);
    });

    test('supports {PORT_0} (0-based gun_num) for WeiYunChong payQRcode.html',
        () {
      const settings = AppSettings(
        ruleMode: UrlRuleMode.globalTemplate,
        globalUrlTemplate:
            'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3D{SN}%26gun_num%3D{PORT_0}',
      );
      final station = ChargingStation(
        id: 'qr2',
        alias: '微云充 1715',
        serialNumber: 'W52001715',
        rawUrl:
            'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715',
        lastUsedPort: 1,
        lastUsedDate: DateTime(2026, 11, 26),
      );

      // 1号口 -> gun_num=0，10号口 -> gun_num=9
      expect(
        UrlRuleEngine.buildTargetUri(station, 1, settings).toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715%26gun_num%3D0',
      );
      expect(
        UrlRuleEngine.buildTargetUri(station, 10, settings).toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715%26gun_num%3D9',
      );
    });

    test('{RAW_URL_PORT0_ENCODED} preserves extra signature/store params and appends gun_num',
        () {
      const settings = AppSettings(
        ruleMode: UrlRuleMode.globalTemplate,
        globalUrlTemplate:
            'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_PORT0_ENCODED}',
      );
      final signedStation = ChargingStation(
        id: 'signed1',
        alias: '带签名参数桩',
        serialNumber: 'W52001715',
        rawUrl:
            'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715&store=sz01&sign=abc123',
        lastUsedPort: 8,
        lastUsedDate: DateTime(2026, 11, 26),
      );

      final uri = UrlRuleEngine.buildTargetUri(signedStation, 8, settings);
      expect(uri, isNotNull);
      final innerUrl = Uri.decodeComponent(uri!.queryParameters['url']!);
      final parsedInner = Uri.parse(innerUrl);
      expect(parsedInner.queryParameters['device_no'], 'W52001715');
      expect(parsedInner.queryParameters['store'], 'sz01');
      expect(parsedInner.queryParameters['sign'], 'abc123');
      expect(parsedInner.queryParameters['gun_num'], '7');
      expect(UrlRuleEngine.templateUsesPort(signedStation, settings), isTrue);

      const defaultSettings = AppSettings();
      expect(
        UrlRuleEngine.templateUsesPort(signedStation, defaultSettings),
        isFalse,
      );
    });
  });
}
