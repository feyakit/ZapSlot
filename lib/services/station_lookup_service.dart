import 'dart:convert';
import 'dart:io';

/// 插口实时工作状态
enum GunWorkStatus {
  idle,
  busy,
  fault,
  unknown,
}

/// 云端查询到的充电桩位置信息
class StationLocationInfo {
  const StationLocationInfo({
    required this.displayName,
    required this.fullAddress,
  });

  /// 清洗后的简洁桩名（如 "苏州·香滨水岸8.4地下室"）
  final String displayName;

  /// 完整地址描述（如 "苏州·香滨水岸8.4地下室（苏州市吴中区）"）
  final String fullAddress;
}

/// 单个插口实时详情
class GunLiveDetail {
  const GunLiveDetail({
    required this.status,
    this.remainingMinutes = 0,
    this.currentValue = '',
  });

  final GunWorkStatus status;
  final int remainingMinutes;
  final String currentValue;
}

/// 充电桩实时状态（0-9 插口空闲/占用/剩余时间/电流、设备在线状态、充满自停、电价与套餐）
class StationLiveInfo {
  const StationLiveInfo({
    required this.serialNumber,
    required this.gunStatuses,
    required this.updatedAt,
    this.gunDetails = const {},
    this.totalGunCount,
    this.gunNums = const [],
    this.isDeviceOffline = false,
    this.supportsFullSelfStop = false,
    this.deviceId,
    this.electricityFees,
    this.packages = const [],
    this.locationInfo,
  });

  final String serialNumber;

  /// 1-based slot (1..N) -> GunWorkStatus
  final Map<int, GunWorkStatus> gunStatuses;

  /// 1-based slot (1..N) -> GunLiveDetail（含剩余分钟数与实时电流）
  final Map<int, GunLiveDetail> gunDetails;
  final DateTime updatedAt;
  final int? totalGunCount;
  final List<String> gunNums;
  final bool isDeviceOffline;
  final bool supportsFullSelfStop;
  final String? deviceId;
  final double? electricityFees;
  final List<String> packages;
  final StationLocationInfo? locationInfo;

  int get idleCount =>
      gunStatuses.values.where((s) => s == GunWorkStatus.idle).length;

  int get totalCount => totalGunCount ?? gunStatuses.length;

  StationLiveInfo copyWith({
    Map<int, GunWorkStatus>? gunStatuses,
    Map<int, GunLiveDetail>? gunDetails,
    DateTime? updatedAt,
    int? totalGunCount,
    List<String>? gunNums,
    bool? isDeviceOffline,
    bool? supportsFullSelfStop,
    String? deviceId,
    double? electricityFees,
    List<String>? packages,
    StationLocationInfo? locationInfo,
  }) {
    return StationLiveInfo(
      serialNumber: serialNumber,
      gunStatuses: gunStatuses ?? this.gunStatuses,
      gunDetails: gunDetails ?? this.gunDetails,
      updatedAt: updatedAt ?? this.updatedAt,
      totalGunCount: totalGunCount ?? this.totalGunCount,
      gunNums: gunNums ?? this.gunNums,
      isDeviceOffline: isDeviceOffline ?? this.isDeviceOffline,
      supportsFullSelfStop: supportsFullSelfStop ?? this.supportsFullSelfStop,
      deviceId: deviceId ?? this.deviceId,
      electricityFees: electricityFees ?? this.electricityFees,
      packages: packages ?? this.packages,
      locationInfo: locationInfo ?? this.locationInfo,
    );
  }
}

/// 充电桩位置与实时状态查询服务（对接微云充 / 莱充设备信息与套餐接口）：
/// 仅在有外网时静默拉取，超时 2.5 秒即放弃，不阻塞离线扫码或点选操作。
class StationLookupService {
  const StationLookupService._();

  static const String _apiSalt = 'laichongchefu@2022';
  static final Uri _lookupEndpoint = Uri.parse(
    'http://weixin.weiyunchong.com/api/wyc/app_get_device_by_code/hash',
  );
  static final Uri _commodityEndpoint = Uri.parse(
    'http://weixin.weiyunchong.com/api/wyc/app_get_device_commodity/hash',
  );

  /// 判断当前别名是否为系统自动生成的默认占位名（只有占位名才自动覆盖为云端名称）。
  static bool isDefaultPlaceholderAlias(String alias, String serialNumber) {
    final trimmed = alias.trim();
    final sn = serialNumber.trim().toUpperCase();
    if (trimmed.isEmpty || trimmed == sn || trimmed == '未命名充电桩') {
      return true;
    }
    return trimmed.startsWith('车库桩 ');
  }

  /// 清洗服务端返回的 device_name（去掉末尾重复的 "、W52001414" 桩号）。
  static String cleanDeviceName(String rawName, String serialNumber) {
    var name = rawName.trim();
    if (name.isEmpty) return '';
    final sn = serialNumber.trim().toUpperCase();
    if (sn.isNotEmpty) {
      final escapedSn = RegExp.escape(sn);
      name = name
          .replaceFirst(
            RegExp('[、,，\\s\\-_/]*$escapedSn\$', caseSensitive: false),
            '',
          )
          .trim();
    }
    return name;
  }

  /// 从 `gun_info_list` 按槽位顺序 (1..N) 解析插口实时状态（1=空闲，2=充电中，其余=故障）。
  static Map<int, GunWorkStatus> parseGunStatuses(dynamic rawGunList) {
    final result = <int, GunWorkStatus>{};
    if (rawGunList is! List) return result;

    for (var i = 0; i < rawGunList.length && i < 12; i++) {
      final item = rawGunList[i];
      if (item is! Map) continue;
      final slot = i + 1;
      final workStatus = '${item['work_status'] ?? ''}'.trim();
      result[slot] = switch (workStatus) {
        '1' => GunWorkStatus.idle,
        '2' => GunWorkStatus.busy,
        '0' || '3' || '4' => GunWorkStatus.fault,
        _ => GunWorkStatus.unknown,
      };
    }
    return result;
  }

  /// 从 `gun_info_list` 提取每个插口真实的 `gun_num` 编号（兼容 0 起始、1 起始或跳号）。
  static List<String> parseGunNums(dynamic rawGunList) {
    final result = <String>[];
    if (rawGunList is! List) return result;
    for (var i = 0; i < rawGunList.length && i < 12; i++) {
      final item = rawGunList[i];
      if (item is! Map) continue;
      final numStr = '${item['gun_num'] ?? i}'.trim();
      if (numStr.isNotEmpty) {
        result.add(numStr);
      }
    }
    return result;
  }

  /// 从 `gun_info_list` 解析每个插口的详细状态（含剩余时间、实时电流）。
  static Map<int, GunLiveDetail> parseGunDetails(dynamic rawGunList) {
    final result = <int, GunLiveDetail>{};
    if (rawGunList is! List) return result;
    for (var i = 0; i < rawGunList.length && i < 12; i++) {
      final item = rawGunList[i];
      if (item is! Map) continue;
      final slot = i + 1;
      final workStatus = '${item['work_status'] ?? ''}'.trim();
      final status = switch (workStatus) {
        '1' => GunWorkStatus.idle,
        '2' => GunWorkStatus.busy,
        '0' || '3' || '4' => GunWorkStatus.fault,
        _ => GunWorkStatus.unknown,
      };
      final remMin = int.tryParse('${item['remaining_time'] ?? '0'}') ?? 0;
      final cur = '${item['cur'] ?? ''}'.trim();
      result[slot] = GunLiveDetail(
        status: status,
        remainingMinutes: remMin < 0 ? 0 : remMin,
        currentValue: cur,
      );
    }
    return result;
  }

  static String formatPackageLabel(Map<String, dynamic> item) {
    final price = item['charge_price'];
    final minutes = int.tryParse('${item['charge_duration'] ?? ''}') ?? 0;
    if (price != null && minutes > 0) {
      if (minutes % 60 == 0) {
        return '$price元/${minutes ~/ 60}h';
      }
      return '$price元/$minutes分';
    }
    return (item['commodity_name'] as String? ?? '').trim();
  }

  /// 查询微云充设备位置信息（兼容已有调用）。
  static Future<StationLocationInfo?> fetchStationInfo(
    String serialNumber, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final live = await fetchLiveStatus(
      serialNumber,
      includePackages: false,
      timeout: timeout,
    );
    return live?.locationInfo;
  }

  /// 查询微云充设备实时状态（插口空闲/占用/电流/剩余时间、位置、可选电价与套餐）。
  static Future<StationLiveInfo?> fetchLiveStatus(
    String serialNumber, {
    bool includePackages = true,
    double? cachedElectricityFees,
    List<String>? cachedPackages,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final sn = serialNumber.trim().toUpperCase();
    if (sn.isEmpty) return null;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final decoded = await _postWyc(
        client,
        _lookupEndpoint,
        {'device_no': sn},
        timeout,
      );
      if (decoded == null || decoded['status'] != true) return null;

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;

      final deviceId = (data['device_id'] as String? ?? '').trim();
      final gunDetails = parseGunDetails(data['gun_info_list']);
      final gunStatuses = {
        for (final e in gunDetails.entries) e.key: e.value.status,
      };
      final gunNums = parseGunNums(data['gun_info_list']);
      final parsedTotal = int.tryParse('${data['total_gun_num'] ?? ''}');
      final totalGunCount = (parsedTotal != null && parsedTotal >= 1 && parsedTotal <= 12)
          ? parsedTotal
          : (gunStatuses.isNotEmpty ? gunStatuses.length.clamp(1, 12) : null);

      final isDeviceOffline = '${data['net_status'] ?? ''}'.trim() == '2';
      final supportsFullSelfStop =
          '${data['full_self_stop_type'] ?? ''}'.trim() == '2';

      final cleanedName = cleanDeviceName(
        data['device_name'] as String? ?? '',
        sn,
      );
      final neighbourhood = (data['neighbourhood_name'] as String? ?? '').trim();
      final province = (data['province_name'] as String? ?? '').trim();
      final city = (data['city_name'] as String? ?? '').trim();
      final district = (data['district_name'] as String? ?? '').trim();
      final detail = (data['device_address'] as String? ?? '').trim();

      final regionParts = <String>[
        if (city.isNotEmpty) city else if (province.isNotEmpty) province,
        if (district.isNotEmpty) district,
        if (detail.isNotEmpty && detail != district) detail,
      ].join();

      final displayName = cleanedName.isNotEmpty
          ? cleanedName
          : (neighbourhood.isNotEmpty ? neighbourhood : regionParts);

      StationLocationInfo? locationInfo;
      if (displayName.isNotEmpty) {
        locationInfo = StationLocationInfo(
          displayName: displayName,
          fullAddress: displayName,
        );
      }

      var fees = cachedElectricityFees;
      var packages = cachedPackages ?? const <String>[];
      if (includePackages &&
          deviceId.isNotEmpty &&
          (fees == null || packages.isEmpty)) {
        final comm = await _postWyc(
          client,
          _commodityEndpoint,
          {'device_id': deviceId},
          timeout,
        );
        final commData = comm?['data'];
        if (commData is Map<String, dynamic>) {
          final rawFee = commData['electricity_fees'];
          if (rawFee is num) {
            fees = rawFee.toDouble();
          }
          final rawList = commData['list'];
          if (rawList is List) {
            packages = rawList
                .whereType<Map<String, dynamic>>()
                .map(formatPackageLabel)
                .where((s) => s.isNotEmpty)
                .take(4)
                .toList();
          }
        }
      }

      return StationLiveInfo(
        serialNumber: sn,
        gunStatuses: gunStatuses,
        gunDetails: gunDetails,
        updatedAt: DateTime.now(),
        totalGunCount: totalGunCount,
        gunNums: gunNums,
        isDeviceOffline: isDeviceOffline,
        supportsFullSelfStop: supportsFullSelfStop,
        deviceId: deviceId.isEmpty ? null : deviceId,
        electricityFees: fees,
        packages: packages,
        locationInfo: locationInfo,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _postWyc(
    HttpClient client,
    Uri endpoint,
    Map<String, dynamic> params,
    Duration timeout,
  ) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final sign = md5Hex('$_apiSalt$ts');

    final req = await client.postUrl(endpoint).timeout(timeout);
    req.headers.set('Content-Type', 'application/json; charset=utf-8');
    req.headers.set('sign', sign);
    req.headers.set('timestamp', ts);
    req.headers.set('User-Agent', 'ZapSlot/1.0');
    req.add(utf8.encode(jsonEncode({'params': params})));

    final res = await req.close().timeout(timeout);
    if (res.statusCode != 200) return null;

    final body = await utf8.decodeStream(res).timeout(timeout);
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// 标准 RFC-1321 MD5（纯 Dart 实现，零外部包依赖）。
  static String md5Hex(String input) {
    final bytes = utf8.encode(input);
    final bitLen = bytes.length * 8;
    final paddedLen = ((bytes.length + 8) ~/ 64 + 1) * 64;
    final padded = List<int>.filled(paddedLen, 0);
    for (var i = 0; i < bytes.length; i++) {
      padded[i] = bytes[i];
    }
    padded[bytes.length] = 0x80;
    for (var i = 0; i < 8; i++) {
      padded[paddedLen - 8 + i] = (bitLen >> (8 * i)) & 0xff;
    }

    const s = <int>[
      7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const k = <int>[
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
      0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
      0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
      0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
      0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
      0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
      0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
      0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
      0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
      0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
      0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
      0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
      0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
      0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
      0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
      0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];

    var a0 = 0x67452301;
    var b0 = 0xefcdab89;
    var c0 = 0x98badcfe;
    var d0 = 0x10325476;

    for (var offset = 0; offset < paddedLen; offset += 64) {
      final m = List<int>.filled(16, 0);
      for (var j = 0; j < 16; j++) {
        final idx = offset + j * 4;
        m[j] = padded[idx] |
            (padded[idx + 1] << 8) |
            (padded[idx + 2] << 16) |
            (padded[idx + 3] << 24);
      }

      var a = a0;
      var b = b0;
      var c = c0;
      var d = d0;

      for (var i = 0; i < 64; i++) {
        late int f;
        late int g;
        if (i < 16) {
          f = (b & c) | ((~b & 0xffffffff) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d & 0xffffffff) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | (~d & 0xffffffff));
          g = (7 * i) % 16;
        }

        final sum = (a + f + k[i] + m[g]) & 0xffffffff;
        a = d;
        d = c;
        c = b;
        final rot = s[i];
        final rotated = ((sum << rot) | (sum >> (32 - rot))) & 0xffffffff;
        b = (b + rotated) & 0xffffffff;
      }

      a0 = (a0 + a) & 0xffffffff;
      b0 = (b0 + b) & 0xffffffff;
      c0 = (c0 + c) & 0xffffffff;
      d0 = (d0 + d) & 0xffffffff;
    }

    String toLeHex(int val) {
      final buf = StringBuffer();
      for (var i = 0; i < 4; i++) {
        final byte = (val >> (8 * i)) & 0xff;
        buf.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      return buf.toString();
    }

    return '${toLeHex(a0)}${toLeHex(b0)}${toLeHex(c0)}${toLeHex(d0)}';
  }
}
