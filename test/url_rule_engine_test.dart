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
  });
}
