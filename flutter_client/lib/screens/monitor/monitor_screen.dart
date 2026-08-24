import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../services/api_client.dart';

/// Sidebar-Feature: ein schlanker, Netdata-artiger Ressourcenmonitor.
/// Zeigt CPU/RAM/Disk-Verlauf des Containers sowie — wichtiger für den
/// eigentlichen Zweck des Hubs — wie viele Drupal-Installationen über
/// pb_localizer zugreifen, wie oft, und wie teuer (Antwortzeit) das für den
/// Server ist.
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

const _kRanges = {'24h': 1, '7d': 7, '30d': 30};

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  String _range = '7d';
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _summary;
  List<dynamic> _resourceSamples = [];
  List<dynamic> _accessDaily = [];
  List<dynamic> _accessSites = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ApiClient().dio;
      final results = await Future.wait([
        dio.get('/monitor/summary'),
        dio.get('/monitor/resources', queryParameters: {'range': _range}),
        dio.get('/monitor/access', queryParameters: {'range': _range}),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0].data as Map<String, dynamic>;
        _resourceSamples = results[1].data as List<dynamic>;
        _accessDaily = (results[2].data as Map<String, dynamic>)['daily'] as List<dynamic>;
        _accessSites = (results[2].data as Map<String, dynamic>)['sites'] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ressourcendaten konnten nicht geladen werden.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final attrs = AppTheme.getAttributes(ref.watch(themeProvider).themeId);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(attrs, isMobile),
          const SizedBox(height: 20),
          if (_loading && _summary == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(_error!, style: TextStyle(color: attrs.textMuted)),
              ),
            )
          else ...[
            _buildSummaryCards(attrs, isMobile),
            const SizedBox(height: 20),
            _buildChartCard(
              attrs,
              title: 'CPU-Last',
              subtitle: '% eines Kerns, gemittelt über 5-Minuten-Fenster',
              icon: LucideIcons.cpu,
              child: _buildCpuChart(attrs),
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              attrs,
              title: 'Arbeitsspeicher',
              subtitle: 'MB genutzt vs. Container-Limit',
              icon: LucideIcons.memoryStick,
              child: _buildMemChart(attrs),
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              attrs,
              title: 'Plattenplatz',
              subtitle: 'App-Code, Daten (alle Sprachen), Datenbank',
              icon: LucideIcons.hardDrive,
              child: _buildDiskChart(attrs),
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              attrs,
              title: 'Zugriffe von Drupal-Seiten',
              subtitle: 'Requests/Tag über pb_localizer, mit Ø-Antwortzeit',
              icon: LucideIcons.globe,
              child: _buildAccessChart(attrs),
            ),
            const SizedBox(height: 16),
            _buildSitesTable(attrs, isMobile),
          ],
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeAttributes attrs, bool isMobile) {
    return Row(
      children: [
        Container(
          width: isMobile ? 48 : 56,
          height: isMobile ? 48 : 56,
          decoration: BoxDecoration(
            color: attrs.brand600,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(LucideIcons.activitySquare,
              color: Colors.white, size: isMobile ? 24 : 28),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ressourcenmonitor',
                style: TextStyle(
                  fontSize: isMobile ? 22 : 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'CPU, RAM, Plattenplatz und API-Zugriffe von Drupal-Installationen',
                style: TextStyle(fontSize: 13, color: attrs.textMuted),
              ),
            ],
          ),
        ),
        if (!isMobile) _buildRangeSelector(attrs),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Aktualisieren',
          onPressed: _fetchAll,
          icon: Icon(LucideIcons.refreshCw, color: attrs.textMuted),
        ),
      ],
    );
  }

  Widget _buildRangeSelector(ThemeAttributes attrs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: attrs.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: attrs.borderMain),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _kRanges.keys.map((r) {
          final isActive = r == _range;
          return InkWell(
            onTap: () {
              if (r != _range) {
                setState(() => _range = r);
                _fetchAll();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? attrs.brand600 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r,
                style: TextStyle(
                  color: isActive ? Colors.white : attrs.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Summary cards ───────────────────────────────────────────────────────

  Widget _buildSummaryCards(ThemeAttributes attrs, bool isMobile) {
    final s = _summary!;
    final today = s['today'] as Map<String, dynamic>? ?? {};

    final cpuPercent = (s['cpuPercent'] as num?)?.toDouble();
    final memUsed = s['memUsedMb'] as int?;
    final memLimit = s['memLimitMb'] as int?;
    final diskCode = s['diskCodeMb'] as int?;
    final diskData = s['diskDataMb'] as int?;
    final diskDb = s['diskDbMb'] as int?;
    final diskTotal = (diskCode ?? 0) + (diskData ?? 0) + (diskDb ?? 0);

    final cards = [
      _SummaryCardData(
        icon: LucideIcons.cpu,
        color: Colors.tealAccent.shade400,
        label: 'CPU (jetzt)',
        value: cpuPercent != null ? '${cpuPercent.toStringAsFixed(1)} %' : '—',
      ),
      _SummaryCardData(
        icon: LucideIcons.memoryStick,
        color: Colors.amber,
        label: 'RAM',
        value: memUsed != null
            ? '$memUsed MB${memLimit != null ? ' / $memLimit MB' : ''}'
            : '—',
      ),
      _SummaryCardData(
        icon: LucideIcons.hardDrive,
        color: Colors.lightBlueAccent,
        label: 'Plattenplatz gesamt',
        value: diskTotal > 0 ? '${(diskTotal / 1024).toStringAsFixed(2)} GB' : '—',
        sub: diskTotal > 0
            ? 'Code ${diskCode ?? 0} MB · Daten ${diskData ?? 0} MB · DB ${diskDb ?? 0} MB'
            : null,
      ),
      _SummaryCardData(
        icon: LucideIcons.globe,
        color: Colors.purpleAccent,
        label: 'Zugriffe heute',
        value: '${today['requests'] ?? 0}',
        sub: '${today['knownSites'] ?? 0} bekannte Seite(n)'
            '${(today['unattributedRequests'] ?? 0) > 0 ? ' + ${today['unattributedRequests']} ohne Header' : ''}',
      ),
      _SummaryCardData(
        icon: LucideIcons.timer,
        color: Colors.orangeAccent,
        label: 'Ø Antwortzeit heute',
        value: today['avgResponseMs'] != null ? '${today['avgResponseMs']} ms' : '—',
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) => _SummaryCard(data: c, attrs: attrs)).toList(),
    );
  }

  // ── Charts ──────────────────────────────────────────────────────────────

  Widget _buildChartCard(
    ThemeAttributes attrs, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return GlassContainer(
      borderRadius: 16,
      backgroundColor: attrs.bgCard,
      border: Border.all(color: attrs.borderMain),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: attrs.brand600),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: attrs.textMain)),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: attrs.textMuted)),
          const SizedBox(height: 16),
          SizedBox(height: 200, child: child),
        ],
      ),
    );
  }

  double _xFor(String isoTs) => DateTime.parse(isoTs).millisecondsSinceEpoch.toDouble();

  String _fmtX(double ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return _range == '24h' ? DateFormat.Hm().format(dt) : DateFormat('dd.MM').format(dt);
  }

  List<FlSpot> _spotsFor(String field) {
    final spots = <FlSpot>[];
    for (final row in _resourceSamples) {
      final v = row[field];
      if (v == null) continue;
      spots.add(FlSpot(_xFor(row['sampled_at'] as String), (v as num).toDouble()));
    }
    return spots;
  }

  LineChartData _baseLineChartData(ThemeAttributes attrs, List<LineChartBarData> bars, {double? minY}) {
    if (_resourceSamples.isEmpty) {
      return LineChartData(lineBarsData: []);
    }
    final xs = _resourceSamples.map((r) => _xFor(r['sampled_at'] as String)).toList();
    return LineChartData(
      minX: xs.reduce((a, b) => a < b ? a : b),
      maxX: xs.reduce((a, b) => a > b ? a : b),
      minY: minY,
      lineBarsData: bars,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: null,
        getDrawingHorizontalLine: (_) => FlLine(color: attrs.borderMain, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: (xs.last - xs.first) / 4 == 0 ? null : (xs.last - xs.first) / 4,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_fmtX(value),
                  style: TextStyle(fontSize: 9, color: attrs.textMuted)),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0),
                style: TextStyle(fontSize: 9, color: attrs.textMuted)),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => attrs.bgSidebar,
        ),
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
    );
  }

  Widget _buildCpuChart(ThemeAttributes attrs) {
    if (_resourceSamples.isEmpty) return _emptyChart(attrs);
    return LineChart(_baseLineChartData(
      attrs,
      [_line(_spotsFor('cpu_percent'), Colors.tealAccent.shade400)],
      minY: 0,
    ));
  }

  Widget _buildMemChart(ThemeAttributes attrs) {
    if (_resourceSamples.isEmpty) return _emptyChart(attrs);
    return LineChart(_baseLineChartData(
      attrs,
      [
        _line(_spotsFor('mem_used_mb'), Colors.amber),
        _line(_spotsFor('mem_limit_mb'), Colors.redAccent),
      ],
      minY: 0,
    ));
  }

  Widget _buildDiskChart(ThemeAttributes attrs) {
    if (_resourceSamples.isEmpty) return _emptyChart(attrs);
    return LineChart(_baseLineChartData(
      attrs,
      [
        _line(_spotsFor('disk_code_mb'), Colors.lightBlueAccent),
        _line(_spotsFor('disk_data_mb'), Colors.purpleAccent),
        _line(_spotsFor('disk_db_mb'), Colors.greenAccent),
      ],
      minY: 0,
    ));
  }

  Widget _buildAccessChart(ThemeAttributes attrs) {
    if (_accessDaily.isEmpty) return _emptyChart(attrs);
    final spots = <FlSpot>[];
    for (final row in _accessDaily) {
      final x = DateTime.parse(row['day'] as String).millisecondsSinceEpoch.toDouble();
      spots.add(FlSpot(x, ((row['requests'] as num?) ?? 0).toDouble()));
    }
    return LineChart(_baseLineChartData(
      attrs,
      [_line(spots, Colors.purpleAccent)],
      minY: 0,
    ));
  }

  Widget _emptyChart(ThemeAttributes attrs) => Center(
        child: Text('Noch keine Daten — der erste Sample-Zyklus läuft alle 5 Minuten.',
            style: TextStyle(color: attrs.textMuted, fontSize: 12)),
      );

  // ── Sites table ──────────────────────────────────────────────────────────

  Widget _buildSitesTable(ThemeAttributes attrs, bool isMobile) {
    return GlassContainer(
      borderRadius: 16,
      backgroundColor: attrs.bgCard,
      border: Border.all(color: attrs.borderMain),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.server, size: 16, color: attrs.brand600),
              const SizedBox(width: 8),
              Text('Zugreifende Drupal-Seiten',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: attrs.textMain)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Aus dem X-PB-Site-Url-Header (pb_localizer). Seiten ohne Eintrag laufen mit einer älteren Modulversion, die den Header noch nicht sendet.',
            style: TextStyle(fontSize: 11, color: attrs.textMuted),
          ),
          const SizedBox(height: 12),
          if (_accessSites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Keine Zugriffe im gewählten Zeitraum.',
                  style: TextStyle(color: attrs.textMuted, fontSize: 12)),
            )
          else
            ..._accessSites.map((s) => _buildSiteRow(s as Map<String, dynamic>, attrs)),
        ],
      ),
    );
  }

  Widget _buildSiteRow(Map<String, dynamic> s, ThemeAttributes attrs) {
    final siteUrl = s['siteUrl'] as String?;
    final requests = s['requests'] ?? 0;
    final avgMs = s['avgResponseMs'];
    final lastIp = s['lastIp'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            siteUrl != null ? LucideIcons.checkCircle2 : LucideIcons.helpCircle,
            size: 14,
            color: siteUrl != null ? Colors.tealAccent.shade400 : attrs.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              siteUrl ?? 'Unbekannt (nur IP: ${lastIp ?? '?'})',
              style: TextStyle(
                color: siteUrl != null ? attrs.textMain : attrs.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$requests Zugriffe',
              style: TextStyle(color: attrs.textMuted, fontSize: 11)),
          if (avgMs != null) ...[
            const SizedBox(width: 12),
            Text('Ø $avgMs ms',
                style: TextStyle(color: attrs.textMuted, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _SummaryCardData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? sub;
  _SummaryCardData({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
  });
}

class _SummaryCard extends StatelessWidget {
  final _SummaryCardData data;
  final ThemeAttributes attrs;
  const _SummaryCard({required this.data, required this.attrs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: attrs.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: attrs.borderMain),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 14, color: data.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: attrs.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: attrs.textMain,
            ),
          ),
          if (data.sub != null) ...[
            const SizedBox(height: 4),
            Text(data.sub!,
                style: TextStyle(fontSize: 10, color: attrs.textMuted)),
          ],
        ],
      ),
    );
  }
}
