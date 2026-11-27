import '../services/storage_service.dart';

enum StatsScope {
  week,
  month,
  all,
}

class TimeSlotStat {
  const TimeSlotStat({
    required this.label,
    required this.count,
    required this.ratio,
  });

  final String label;
  final int count;
  final double ratio;
}

class PeriodBarStat {
  const PeriodBarStat({
    required this.label,
    required this.count,
    required this.spend,
    required this.isCurrent,
  });

  final String label;
  final int count;
  final double spend;
  final bool isCurrent;
}

class ChargingStats {
  const ChargingStats({
    required this.scope,
    required this.totalCount,
    required this.thisWeekCount,
    required this.thisMonthCount,
    required this.allTimeCount,
    required this.averageIntervalDays,
    required this.periodSpend,
    required this.thisWeekSpend,
    required this.thisMonthSpend,
    required this.allTimeSpend,
    required this.recordedSpendCount,
    required this.averageSpend,
    required this.topStationName,
    required this.topStationCount,
    required this.topStationPercent,
    required this.topSocketLabel,
    required this.topSocketCount,
    required this.timeBuckets,
    required this.periodBars,
  });

  final StatsScope scope;
  final int totalCount;
  final int thisWeekCount;
  final int thisMonthCount;
  final int allTimeCount;
  final double? averageIntervalDays;
  final double periodSpend;
  final double thisWeekSpend;
  final double thisMonthSpend;
  final double allTimeSpend;
  final int recordedSpendCount;
  final double? averageSpend;
  final String? topStationName;
  final int topStationCount;
  final int topStationPercent;
  final String? topSocketLabel;
  final int topSocketCount;
  final List<TimeSlotStat> timeBuckets;
  final List<PeriodBarStat> periodBars;

  factory ChargingStats.fromRecords(
    List<ChargingHistoryRecord> records, {
    StatsScope scope = StatsScope.week,
    DateTime? now,
  }) {
    final refNow = now ?? DateTime.now();
    final todayStart = DateTime(refNow.year, refNow.month, refNow.day);
    final weekStart = todayStart.subtract(Duration(days: refNow.weekday - 1));
    final monthStart = DateTime(refNow.year, refNow.month, 1);

    final weekRecords =
        records.where((r) => !r.triggeredAt.isBefore(weekStart)).toList();
    final monthRecords =
        records.where((r) => !r.triggeredAt.isBefore(monthStart)).toList();

    final thisWeekSpend = _sumSpend(weekRecords);
    final thisMonthSpend = _sumSpend(monthRecords);
    final allTimeSpend = _sumSpend(records);

    final scoped = switch (scope) {
      StatsScope.week => weekRecords,
      StatsScope.month => monthRecords,
      StatsScope.all => records,
    };

    final periodBars = switch (scope) {
      StatsScope.week => _buildWeekBars(records, refNow, weekStart),
      StatsScope.month => _buildMonthBars(monthRecords, refNow),
      StatsScope.all => _buildSixMonthBars(records, refNow),
    };

    if (scoped.isEmpty) {
      return ChargingStats(
        scope: scope,
        totalCount: 0,
        thisWeekCount: weekRecords.length,
        thisMonthCount: monthRecords.length,
        allTimeCount: records.length,
        averageIntervalDays: null,
        periodSpend: 0,
        thisWeekSpend: thisWeekSpend,
        thisMonthSpend: thisMonthSpend,
        allTimeSpend: allTimeSpend,
        recordedSpendCount: 0,
        averageSpend: null,
        topStationName: null,
        topStationCount: 0,
        topStationPercent: 0,
        topSocketLabel: null,
        topSocketCount: 0,
        timeBuckets: const [
          TimeSlotStat(label: '早 06-11', count: 0, ratio: 0),
          TimeSlotStat(label: '午 11-17', count: 0, ratio: 0),
          TimeSlotStat(label: '晚 17-22', count: 0, ratio: 0),
          TimeSlotStat(label: '夜 22-06', count: 0, ratio: 0),
        ],
        periodBars: periodBars,
      );
    }

    final sorted = [...scoped]
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    final total = sorted.length;

    double? avgIntervalDays;
    if (total >= 2) {
      final spanMinutes = sorted.first.triggeredAt
          .difference(sorted.last.triggeredAt)
          .inMinutes
          .abs();
      avgIntervalDays = (spanMinutes / 60.0 / 24.0) / (total - 1);
    }

    final stationCounts = <String, int>{};
    final socketCounts = <String, int>{};
    var morning = 0;
    var afternoon = 0;
    var evening = 0;
    var night = 0;
    var periodSpend = 0.0;
    var recordedSpendCount = 0;

    for (final r in sorted) {
      stationCounts[r.stationAlias] = (stationCounts[r.stationAlias] ?? 0) + 1;
      final socketKey = '${r.socketLabel}号口';
      socketCounts[socketKey] = (socketCounts[socketKey] ?? 0) + 1;

      if (r.amountYuan != null && r.amountYuan! > 0) {
        periodSpend += r.amountYuan!;
        recordedSpendCount++;
      }

      final h = r.triggeredAt.hour;
      if (h >= 6 && h < 11) {
        morning++;
      } else if (h >= 11 && h < 17) {
        afternoon++;
      } else if (h >= 17 && h < 22) {
        evening++;
      } else {
        night++;
      }
    }

    final topStationEntry = stationCounts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final topSocketEntry = socketCounts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    return ChargingStats(
      scope: scope,
      totalCount: total,
      thisWeekCount: weekRecords.length,
      thisMonthCount: monthRecords.length,
      allTimeCount: records.length,
      averageIntervalDays: avgIntervalDays,
      periodSpend: periodSpend,
      thisWeekSpend: thisWeekSpend,
      thisMonthSpend: thisMonthSpend,
      allTimeSpend: allTimeSpend,
      recordedSpendCount: recordedSpendCount,
      averageSpend:
          recordedSpendCount > 0 ? periodSpend / recordedSpendCount : null,
      topStationName: topStationEntry.key,
      topStationCount: topStationEntry.value,
      topStationPercent: ((topStationEntry.value / total) * 100).round(),
      topSocketLabel: topSocketEntry.key,
      topSocketCount: topSocketEntry.value,
      timeBuckets: [
        TimeSlotStat(label: '早 06-11', count: morning, ratio: morning / total),
        TimeSlotStat(
          label: '午 11-17',
          count: afternoon,
          ratio: afternoon / total,
        ),
        TimeSlotStat(label: '晚 17-22', count: evening, ratio: evening / total),
        TimeSlotStat(label: '夜 22-06', count: night, ratio: night / total),
      ],
      periodBars: periodBars,
    );
  }

  static double _sumSpend(List<ChargingHistoryRecord> list) {
    var sum = 0.0;
    for (final r in list) {
      if (r.amountYuan != null && r.amountYuan! > 0) {
        sum += r.amountYuan!;
      }
    }
    return sum;
  }

  static List<PeriodBarStat> _buildWeekBars(
    List<ChargingHistoryRecord> records,
    DateTime now,
    DateTime weekStart,
  ) {
    const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
    return List.generate(7, (idx) {
      final day = weekStart.add(Duration(days: idx));
      final matches = records.where(
        (r) =>
            r.triggeredAt.year == day.year &&
            r.triggeredAt.month == day.month &&
            r.triggeredAt.day == day.day,
      );
      final count = matches.length;
      final spend = _sumSpend(matches.toList());
      final isCurrent = day.year == now.year &&
          day.month == now.month &&
          day.day == now.day;
      return PeriodBarStat(
        label: isCurrent ? '今' : weekNames[idx],
        count: count,
        spend: spend,
        isCurrent: isCurrent,
      );
    });
  }

  static List<PeriodBarStat> _buildMonthBars(
    List<ChargingHistoryRecord> monthRecords,
    DateTime now,
  ) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final weekCount = ((daysInMonth - 1) ~/ 7) + 1;
    final currentWeekIdx = (now.day - 1) ~/ 7;
    return List.generate(weekCount, (idx) {
      final startDay = idx * 7 + 1;
      final endDay = (idx + 1) * 7;
      final matches = monthRecords.where(
        (r) => r.triggeredAt.day >= startDay && r.triggeredAt.day <= endDay,
      );
      return PeriodBarStat(
        label: '第${idx + 1}周',
        count: matches.length,
        spend: _sumSpend(matches.toList()),
        isCurrent: idx == currentWeekIdx,
      );
    });
  }

  static List<PeriodBarStat> _buildSixMonthBars(
    List<ChargingHistoryRecord> records,
    DateTime now,
  ) {
    return List.generate(6, (idx) {
      final target = DateTime(now.year, now.month - (5 - idx), 1);
      final matches = records.where(
        (r) =>
            r.triggeredAt.year == target.year &&
            r.triggeredAt.month == target.month,
      );
      return PeriodBarStat(
        label: '${target.month}月',
        count: matches.length,
        spend: _sumSpend(matches.toList()),
        isCurrent: idx == 5,
      );
    });
  }
}
