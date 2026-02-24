/*
 * Copyright (c) 2019-2026. Antonello Andrea (https://g-ant.eu). All rights reserved.
 * Use of this source code is governed by a GPL3 license that can be
 * found in the LICENSE file.
 */

import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart'
    hide TextStyle;
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:smash/eu/hydrologis/smash/project/project_database.dart';
import 'package:smash/generated/l10n.dart';
import 'package:smashlibs/smashlibs.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';

class LogCompare extends StatefulWidget {
  const LogCompare({Key? key}) : super(key: key);

  @override
  State<LogCompare> createState() => _LogCompareState();
}

class _LogCompareState extends State<LogCompare> {
  Future<void>? _loadFuture;

  final Map<String, ProjectDb> _projectDbsMap = <String, ProjectDb>{};

  // two independent panes (top/bottom)
  final _PaneState _top = _PaneState();
  final _PaneState _bottom = _PaneState();

  // tweak as you like
  static const double _wideBreakpoint = 900;
  static const double _initialLeftPaneWidth = 360;
  static const double _minLeftPaneWidth = 260;
  static const double _minChartPaneWidth = 320;
  static const double _dividerWidth = 10;

  double _leftPaneWidth = _initialLeftPaneWidth;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadProjects();
  }

  @override
  void dispose() {
    _top.dispose();
    _bottom.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projectsFolder = await Workspace.getProjectsFolder();

    final projectFilePaths = await projectsFolder
        .list()
        .where((f) => f.path.endsWith('.gpap'))
        .map((f) => f.path)
        .toList();

    _projectDbsMap.clear();
    for (final projectFilePath in projectFilePaths) {
      final projectDb = await GeopaparazziProjectDb(projectFilePath);
      projectDb.createNecessaryExtraTables();
      final name = FileUtilities.nameFromFile(projectFilePath, false);
      _projectDbsMap[name] = projectDb;
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<List<Log>> _loadLogs(ProjectDb db) async {
    final logs = await db.getLogs();
    return logs.where((log) => log.parentLogId == null).toList();
  }

  Future<void> _enterLogsMode(_PaneState pane, String projectName) async {
    final db = _projectDbsMap[projectName];
    if (db == null) return;

    pane.selectedProjectName = projectName;
    pane.selectedProjectDb = db;
    pane.selectedLog = null;
    pane.logs = const [];
    pane.isInLogsMode = true;

    if (!mounted) return;
    setState(() {});

    final logs = await _loadLogs(db);
    if (!mounted) return;

    pane.logs = logs;
    setState(() {});
  }

  void _backToProjects(_PaneState pane) {
    pane.isInLogsMode = false;
    pane.selectedProjectName = null;
    pane.selectedProjectDb = null;
    pane.selectedLog = null;
    pane.logs = const [];
    pane.logsFilterController.text = '';
    setState(() {});
  }

  void _selectLog(_PaneState pane, Log log) {
    pane.selectedLog = log;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snap) {
        final isLoading = snap.connectionState != ConnectionState.done;
        final hasError = snap.hasError;

        return Scaffold(
          appBar: AppBar(
            title: Text(SL.of(context).logCompare_title),
            actions: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
          body: hasError
              ? SmashUI.errorWidget(snap.error.toString())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= _wideBreakpoint;
                    return isWide
                        ? _buildWide(constraints.maxWidth)
                        : _buildNarrow();
                  },
                ),
        );
      },
    );
  }

  Widget _buildWide(double totalWidth) {
    final allProjectNames = _projectDbsMap.keys.toList()..sort();
    final maxLeftPaneWidth = math.max(
        _minLeftPaneWidth, totalWidth - _minChartPaneWidth - _dividerWidth);
    final leftPaneWidth =
        _leftPaneWidth.clamp(_minLeftPaneWidth, maxLeftPaneWidth).toDouble();

    return Row(
      children: [
        SizedBox(
          width: leftPaneWidth,
          child: Column(
            children: [
              Expanded(
                child: _SelectorPane(
                  title: 'RED',
                  pane: _top,
                  projectNames: allProjectNames,
                  onSelectProject: (name) => _enterLogsMode(_top, name),
                  onBackToProjects: () => _backToProjects(_top),
                  onSelectLog: (log) => _selectLog(_top, log),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _SelectorPane(
                  title: 'BLUE',
                  pane: _bottom,
                  projectNames: allProjectNames,
                  onSelectProject: (name) => _enterLogsMode(_bottom, name),
                  onBackToProjects: () => _backToProjects(_bottom),
                  onSelectLog: (log) => _selectLog(_bottom, log),
                ),
              ),
            ],
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              final next = (_leftPaneWidth + details.delta.dx)
                  .clamp(_minLeftPaneWidth, maxLeftPaneWidth)
                  .toDouble();
              if (next != _leftPaneWidth) {
                setState(() => _leftPaneWidth = next);
              }
            },
            child: SizedBox(
              width: _dividerWidth,
              child: const Center(
                child: VerticalDivider(width: 1, thickness: 1),
              ),
            ),
          ),
        ),
        Expanded(
          child: _ChartArea(
            logA: _top.selectedLog,
            logB: _bottom.selectedLog,
            projectA: _top.selectedProjectName,
            projectB: _bottom.selectedProjectName,
            projectDbsMap: _projectDbsMap,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow() {
    final allProjectNames = _projectDbsMap.keys.toList()..sort();
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            child: TabBar(
              labelColor: SmashColors.mainDecorationsDarker,
              unselectedLabelColor: SmashColors.mainDecorations,
              tabs: [
                Tab(text: SL.of(context).logCompare_log1),
                Tab(text: SL.of(context).logCompare_log2),
                Tab(text: SL.of(context).logCompare_chartTab),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SelectorPane(
                  title: 'RED',
                  pane: _top,
                  projectNames: allProjectNames,
                  onSelectProject: (name) => _enterLogsMode(_top, name),
                  onBackToProjects: () => _backToProjects(_top),
                  onSelectLog: (log) => _selectLog(_top, log),
                ),
                _SelectorPane(
                  title: 'BLUE',
                  pane: _bottom,
                  projectNames: allProjectNames,
                  onSelectProject: (name) => _enterLogsMode(_bottom, name),
                  onBackToProjects: () => _backToProjects(_bottom),
                  onSelectLog: (log) => _selectLog(_bottom, log),
                ),
                _ChartArea(
                  logA: _top.selectedLog,
                  logB: _bottom.selectedLog,
                  projectA: _top.selectedProjectName,
                  projectB: _bottom.selectedProjectName,
                  projectDbsMap: _projectDbsMap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneState {
  bool isInLogsMode = false;

  final TextEditingController projectsFilterController =
      TextEditingController();
  final TextEditingController logsFilterController = TextEditingController();

  final FocusNode projectsFilterFocus = FocusNode(debugLabel: 'projectsFilter');
  final FocusNode logsFilterFocus = FocusNode(debugLabel: 'logsFilter');

  String? selectedProjectName;
  ProjectDb? selectedProjectDb;

  List<Log> logs = const [];
  Log? selectedLog;

  void dispose() {
    projectsFilterController.dispose();
    logsFilterController.dispose();

    projectsFilterFocus.dispose();
    logsFilterFocus.dispose();
  }

  List<Log> filteredLogs() {
    final f = logsFilterController.text.trim().toLowerCase();
    if (f.isEmpty) return logs;
    return logs.where((l) {
      final label = (l.text ?? '').toLowerCase();
      final idStr = '${l.id}';
      return label.contains(f) || idStr.contains(f);
    }).toList();
  }
}

class _SelectorPane extends StatelessWidget {
  const _SelectorPane({
    required this.title,
    required this.pane,
    required this.projectNames, // full list (sorted)
    required this.onSelectProject,
    required this.onBackToProjects,
    required this.onSelectLog,
  });

  final String title;
  final _PaneState pane;

  final List<String> projectNames;
  final void Function(String projectName) onSelectProject;
  final VoidCallback onBackToProjects;
  final void Function(Log log) onSelectLog;

  Color get _paneColor => title == 'RED' ? Colors.red : Colors.blue;

  List<String> _filterProjects(List<String> all, String filter) {
    final f = filter.trim().toLowerCase();
    if (f.isEmpty) return all;
    return all.where((n) => n.toLowerCase().contains(f)).toList();
  }

  List<Log> _filterLogs(List<Log> all, String filter) {
    final f = filter.trim().toLowerCase();
    if (f.isEmpty) return all;
    return all.where((l) {
      final label = (l.text ?? '').toLowerCase();
      final idStr = '${l.id}';
      return label.contains(f) || idStr.contains(f);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = pane.isInLogsMode
        ? pane.logsFilterController
        : pane.projectsFilterController;

    final fn =
        pane.isInLogsMode ? pane.logsFilterFocus : pane.projectsFilterFocus;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              SmashUI.normalText(
                pane.isInLogsMode
                    ? SL.of(context).logCompare_selectLog
                    : SL.of(context).logCompare_selectProject,
                bold: true,
                color: _paneColor,
              ),
              const Spacer(),
              if (pane.isInLogsMode)
                Tooltip(
                  message: SL.of(context).logCompare_backToProjects,
                  child: IconButton(
                    onPressed: onBackToProjects,
                    icon: Icon(Icons.arrow_back,
                        color: SmashColors.mainDecorationsDarker),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            focusNode: fn,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: pane.isInLogsMode
                  ? SL.of(context).logCompare_filterLogs
                  : SL.of(context).logCompare_filterProjects,
              isDense: true,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: _paneColor, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _paneColor, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _paneColor, width: 2),
              ),
              suffixIcon: ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: SL.of(context).logCompare_clearFilter,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        ctrl.clear();

                        // re-focus so user can type again immediately
                        fn.requestFocus();

                        // trigger rebuild so list updates + suffix icon disappears
                        (context as Element).markNeedsBuild();
                      },
                    ),
            ),
            onChanged: (_) {
              (context as Element).markNeedsBuild();
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _paneColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: ctrl,
                builder: (context, value, _) {
                  if (pane.isInLogsMode) {
                    final logs = _filterLogs(pane.logs, value.text);
                    return _buildLogsList(context, logs);
                  } else {
                    final names = _filterProjects(projectNames, value.text);
                    return _buildProjectsList(context, names);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectsList(BuildContext context, List<String> names) {
    if (names.isEmpty) {
      return Center(
        child: SmashUI.titleText(
          SL.of(context).logCompare_noProjects,
          color: SmashColors.mainDecorationsDarker,
          bold: true,
        ),
      );
    }

    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (context, idx) {
        final name = names[idx];
        final selected = pane.selectedProjectName == name && !pane.isInLogsMode;

        return ListTile(
          dense: true,
          selected: selected,
          leading:
              Icon(MdiIcons.database, color: SmashColors.mainDecorationsDarker),
          title: Tooltip(
            message: name,
            child: SmashUI.smallText(
              name,
              overflow: TextOverflow.ellipsis,
              color: SmashColors.mainDecorationsDarker,
            ),
          ),
          onTap: () => onSelectProject(name),
        );
      },
    );
  }

  Widget _buildLogsList(BuildContext context, List<Log> logs) {
    if (pane.selectedProjectName == null) {
      return Center(child: Text(SL.of(context).logCompare_selectProjectFirst));
    }
    if (pane.logs.isEmpty) {
      return Center(child: Text(SL.of(context).logCompare_noLogsOrLoading));
    }
    if (logs.isEmpty) {
      return Center(child: Text(SL.of(context).logCompare_noLogsMatchFilter));
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, idx) {
        final log = logs[idx];
        final selectedColor = _paneColor;
        final label = (log.text == null || log.text!.trim().isEmpty)
            ? 'Log ${log.id}'
            : log.text!.trim();
        final selected = pane.selectedLog?.id == log.id;

        return ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: selectedColor.withValues(alpha: 0.08),
          leading: Icon(
            MdiIcons.vectorPolyline,
            color: selected ? selectedColor : SmashColors.mainDecorationsDarker,
          ),
          title: Tooltip(
            message: label,
            child: SmashUI.smallText(
              label,
              overflow: TextOverflow.ellipsis,
              color:
                  selected ? selectedColor : SmashColors.mainDecorationsDarker,
              bold: selected,
            ),
          ),
          subtitle: SmashUI.smallText(
            'id: ${log.id}',
            color: selected ? selectedColor : SmashColors.mainDecorationsDarker,
            bold: selected,
          ),
          onTap: () => onSelectLog(log),
        );
      },
    );
  }
}

class _ChartArea extends StatelessWidget {
  const _ChartArea({
    required this.logA,
    required this.logB,
    required this.projectA,
    required this.projectB,
    required this.projectDbsMap,
  });

  final Log? logA;
  final Log? logB;
  final String? projectA;
  final String? projectB;
  final Map<String, ProjectDb> projectDbsMap;

  String _logLabel(Log log) {
    final text = log.text?.trim();
    if (text == null || text.isEmpty) return 'Log ${log.id}';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final sl = SL.of(context);
    if (logA == null && logB == null) {
      return Center(child: Text(sl.logCompare_selectAtLeastOneLog));
    }
    List<List<LogDataPoint>> logDataA = const [];
    List<List<LogDataPoint>> logDataB = const [];

    if (logA != null && projectA != null) {
      final dbA = projectDbsMap[projectA];
      if (dbA != null) {
        logDataA = logA!.getLogData(dbA);
      }
    }

    if (logB != null && projectB != null) {
      final dbB = projectDbsMap[projectB];
      if (dbB != null) {
        logDataB = logB!.getLogData(dbB);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (logA != null)
                    Text(
                      _logLabel(logA!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  if (logA != null && logB != null)
                    Text(
                      sl.logCompare_vs,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (logB != null)
                    Text(
                      _logLabel(logB!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: LogCompareChartWithToggles(
                      redSegments: logDataA,
                      blueSegments: logDataB,
                      redLabel: sl.logCompare_log1,
                      blueLabel: sl.logCompare_log2,
                      initialXAxis: CompareXAxis.distance,
                      initialYAxis: CompareYAxis.altitude,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////
// HELPER METHODS FOR CHART PREPARATION BELOW
//////////////////////////////////////////////////
class PreparedMulti {
  PreparedMulti(this.segments, this.minX, this.maxX, this.minY, this.maxY);

  final List<List<FlSpot>> segments;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

double _lon(LogDataPoint p) => p.filtered_lon ?? p.lon;
double _lat(LogDataPoint p) => p.filtered_lat ?? p.lat;

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // meters
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

/// Converts List<List<LogDataPoint>> (main + children) into
/// one continuous FlSpot series (children appended after parent) + global bounds.
/// Dart 2 compatible.
PreparedMulti prepareMultiSeries(
  List<List<LogDataPoint>> segments, {
  required CompareXAxis xAxis,
  required CompareYAxis yAxis,
  SpeedSeriesMode speedMode = SpeedSeriesMode.smoothed,
  bool computeSpeedIfMissing = true,
  bool sortByTsWithinSegment = true,
  int maxPointsPerSegment = 2500,
}) {
  if (segments.isEmpty) {
    return PreparedMulti(const [], 0, 1, 0, 1);
  }

  final mergedSpots = <FlSpot>[];
  var xOffset = 0.0;
  const segmentJoinEps = 1e-6;

  double minX = double.infinity;
  double maxX = -double.infinity;
  double minY = double.infinity;
  double maxY = -double.infinity;

  for (final rawSeg in segments) {
    if (rawSeg.isEmpty) continue;

    final seg = <LogDataPoint>[...rawSeg];

    if (sortByTsWithinSegment) {
      seg.sort((a, b) {
        final ta = a.ts;
        final tb = b.ts;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });
    }

    // Find first usable point
    int startIdx = 0;
    while (startIdx < seg.length) {
      if (xAxis == CompareXAxis.time && seg[startIdx].ts == null) {
        startIdx++;
      } else {
        break;
      }
    }
    if (startIdx >= seg.length) continue;

    final startTs = seg[startIdx].ts ?? 0;

    final n = seg.length - startIdx;
    final stride =
        (n > maxPointsPerSegment) ? (n / maxPointsPerSegment).ceil() : 1;

    final spots = <FlSpot>[];
    double cumDist = 0.0;

    LogDataPoint? prevKept;
    double? emaY;

    for (int i = startIdx; i < seg.length; i += stride) {
      final p = seg[i];

      // X
      double x;
      if (xAxis == CompareXAxis.time) {
        if (p.ts == null) {
          prevKept = p;
          continue;
        }
        // epoch millis -> minutes from segment start
        x = (p.ts! - startTs) / 60000.0;
      } else {
        if (prevKept != null) {
          final d = _haversineMeters(
            _lat(prevKept),
            _lon(prevKept),
            _lat(p),
            _lon(p),
          );
          if (d.isFinite && d >= 0) cumDist += d;
        }
        x = cumDist; // meters
      }

      // Y
      double? y;
      switch (yAxis) {
        case CompareYAxis.speed:
          y = p.speed;
          if ((y == null || !y.isFinite) && computeSpeedIfMissing) {
            if (prevKept != null && prevKept.ts != null && p.ts != null) {
              final dt = (p.ts! - prevKept.ts!) / 1000.0;
              if (dt >= 1.0 && dt <= 60.0) {
                final d = _haversineMeters(
                  _lat(prevKept),
                  _lon(prevKept),
                  _lat(p),
                  _lon(p),
                );
                final sp = d / dt; // m/s
                if (sp.isFinite && sp >= 0 && sp <= 20.0) y = sp;
              }
            }
          }
          break;

        case CompareYAxis.altitude:
          y = p.altim;
          break;
      }

      if (y != null && y.isFinite && speedMode == SpeedSeriesMode.smoothed) {
        const alpha = 0.1;
        emaY = emaY == null ? y : (alpha * y + (1 - alpha) * emaY);
        y = emaY;
      }

      if (y == null || !y.isFinite) {
        prevKept = p;
        continue;
      }

      final mergedX = xOffset + x;
      spots.add(FlSpot(mergedX, y));

      if (mergedX < minX) minX = mergedX;
      if (mergedX > maxX) maxX = mergedX;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      prevKept = p;
    }

    if (spots.isNotEmpty) {
      mergedSpots.addAll(spots);
      xOffset = spots.last.x + segmentJoinEps;
    }
  }

  if (mergedSpots.isEmpty) {
    return PreparedMulti(const [], 0, 1, 0, 1);
  }

  // pad Y a bit so lines aren't glued to borders
  final spanY = (maxY - minY).abs();
  final pad = spanY == 0 ? (maxY.abs() * 0.1 + 1) : spanY * 0.06;

  return PreparedMulti(
    [mergedSpots],
    minX.isFinite ? minX : 0,
    maxX.isFinite ? maxX : 1,
    (minY - pad).isFinite ? (minY - pad) : 0,
    (maxY + pad).isFinite ? (maxY + pad) : 1,
  );
}

enum CompareXAxis { time, distance }

enum CompareYAxis { speed, altitude }

enum SpeedSeriesMode { raw, smoothed }

/// Drop-in header: legend + toggles.
/// Put this above the LineChart in your chart area.
class LogCompareHeader extends StatelessWidget {
  const LogCompareHeader({
    Key? key,
    required this.redLabel,
    required this.blueLabel,
    required this.xAxis,
    required this.yAxis,
    required this.onXAxisChanged,
    required this.onYAxisChanged,
    required this.speedMode,
    required this.onSpeedModeChanged,
    this.onToggleRedVisible,
    this.onToggleBlueVisible,
    this.redVisible = true,
    this.blueVisible = true,
  }) : super(key: key);

  final String redLabel;
  final String blueLabel;

  final CompareXAxis xAxis;
  final CompareYAxis yAxis;
  final SpeedSeriesMode speedMode;

  final ValueChanged<CompareXAxis> onXAxisChanged;
  final ValueChanged<CompareYAxis> onYAxisChanged;
  final ValueChanged<SpeedSeriesMode> onSpeedModeChanged;

  // Optional: allow hiding/showing series by tapping legend
  final VoidCallback? onToggleRedVisible;
  final VoidCallback? onToggleBlueVisible;
  final bool redVisible;
  final bool blueVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sl = SL.of(context);

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      spacing: 12,
      children: [
        _LegendRow(
          redLabel: redLabel,
          blueLabel: blueLabel,
          redVisible: redVisible,
          blueVisible: blueVisible,
          onToggleRedVisible: onToggleRedVisible,
          onToggleBlueVisible: onToggleBlueVisible,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${sl.logCompare_xAxis}:', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            ToggleButtons(
              isSelected: [
                xAxis == CompareXAxis.distance,
                xAxis == CompareXAxis.time,
              ],
              onPressed: (idx) {
                onXAxisChanged(
                    idx == 0 ? CompareXAxis.distance : CompareXAxis.time);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(sl.logCompare_distance),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(sl.logCompare_time),
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${sl.logCompare_yAxis}:', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            ToggleButtons(
              isSelected: [
                yAxis == CompareYAxis.altitude,
                yAxis == CompareYAxis.speed,
              ],
              onPressed: (idx) {
                final v = idx == 0 ? CompareYAxis.altitude : CompareYAxis.speed;
                onYAxisChanged(v);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(sl.logCompare_altitude),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(sl.logCompare_speed),
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Smoothing:', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            ToggleButtons(
              isSelected: [
                speedMode == SpeedSeriesMode.raw,
                speedMode == SpeedSeriesMode.smoothed,
              ],
              onPressed: (idx) {
                onSpeedModeChanged(
                    idx == 0 ? SpeedSeriesMode.raw : SpeedSeriesMode.smoothed);
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('Raw'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('Smoothed'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.redLabel,
    required this.blueLabel,
    required this.redVisible,
    required this.blueVisible,
    this.onToggleRedVisible,
    this.onToggleBlueVisible,
  });

  final String redLabel;
  final String blueLabel;

  final bool redVisible;
  final bool blueVisible;

  final VoidCallback? onToggleRedVisible;
  final VoidCallback? onToggleBlueVisible;

  @override
  Widget build(BuildContext context) {
    Widget item({
      required Color color,
      required String label,
      required bool visible,
      required VoidCallback? onTap,
    }) {
      final textStyle = TextStyle(
        fontWeight: FontWeight.w600,
        decoration: visible ? null : TextDecoration.lineThrough,
        color: visible ? null : Theme.of(context).disabledColor,
      );

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: visible ? color : Theme.of(context).disabledColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: textStyle),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(
          color: Colors.red,
          label: redLabel,
          visible: redVisible,
          onTap: onToggleRedVisible,
        ),
        const SizedBox(width: 12),
        item(
          color: Colors.blue,
          label: blueLabel,
          visible: blueVisible,
          onTap: onToggleBlueVisible,
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Example: Updated chart widget that uses the header + toggles.
/// You can merge this into your existing _ChartArea.
/// ---------------------------------------------------------------------------

class LogCompareChartWithToggles extends StatefulWidget {
  const LogCompareChartWithToggles({
    Key? key,
    required this.redSegments,
    required this.blueSegments,
    this.redLabel = 'RED',
    this.blueLabel = 'BLUE',
    this.initialXAxis = CompareXAxis.distance,
    this.initialYAxis = CompareYAxis.altitude,
  }) : super(key: key);

  final List<List<LogDataPoint>> redSegments;
  final List<List<LogDataPoint>> blueSegments;

  final String redLabel;
  final String blueLabel;

  final CompareXAxis initialXAxis;
  final CompareYAxis initialYAxis;

  @override
  State<LogCompareChartWithToggles> createState() =>
      _LogCompareChartWithTogglesState();
}

class _LogCompareChartWithTogglesState
    extends State<LogCompareChartWithToggles> {
  late CompareXAxis _xAxis = widget.initialXAxis;
  late CompareYAxis _yAxis = widget.initialYAxis;
  SpeedSeriesMode _speedMode = SpeedSeriesMode.smoothed;

  bool _redVisible = true;
  bool _blueVisible = true;
  double? _touchX;
  double? _touchRedY;
  double? _touchBlueY;

  @override
  Widget build(BuildContext context) {
    final red = prepareMultiSeries(widget.redSegments,
        xAxis: _xAxis, yAxis: _yAxis, speedMode: _speedMode);
    final blue = prepareMultiSeries(widget.blueSegments,
        xAxis: _xAxis, yAxis: _yAxis, speedMode: _speedMode);

    if ((red.segments.isEmpty || !_redVisible) &&
        (blue.segments.isEmpty || !_blueVisible)) {
      return Center(child: Text(SL.of(context).logCompare_noChartableData));
    }

    final hasRed = _redVisible && red.segments.isNotEmpty;
    final hasBlue = _blueVisible && blue.segments.isNotEmpty;

    final minX = hasRed && hasBlue
        ? math.min(red.minX, blue.minX)
        : (hasRed ? red.minX : blue.minX);
    final maxX = hasRed && hasBlue
        ? math.max(red.maxX, blue.maxX)
        : (hasRed ? red.maxX : blue.maxX);
    final minY = hasRed && hasBlue
        ? math.min(red.minY, blue.minY)
        : (hasRed ? red.minY : blue.minY);
    final maxY = hasRed && hasBlue
        ? math.max(red.maxY, blue.maxY)
        : (hasRed ? red.maxY : blue.maxY);

    final bars = <LineChartBarData>[];

    if (_redVisible) {
      for (final segSpots in red.segments) {
        bars.add(
          LineChartBarData(
            spots: segSpots,
            isCurved: false,
            barWidth: 2,
            color: Colors.red,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    if (_blueVisible) {
      for (final segSpots in blue.segments) {
        bars.add(
          LineChartBarData(
            spots: segSpots,
            isCurved: false,
            barWidth: 2,
            color: Colors.blue,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    String xTitle() => _xAxis == CompareXAxis.time
        ? SL.of(context).logCompare_timeAxisTitle
        : SL.of(context).logCompare_distanceAxisTitle;
    String xReadoutLabel() => _xAxis == CompareXAxis.time
        ? SL.of(context).logCompare_time
        : SL.of(context).logCompare_distance;
    String yTitle() {
      if (_yAxis == CompareYAxis.speed) {
        return SL.of(context).logCompare_speedAxisTitle;
      }
      return SL.of(context).logCompare_altitudeAxisTitle;
    }

    String yReadoutLabel() {
      if (_yAxis == CompareYAxis.speed) return SL.of(context).logCompare_speed;
      return SL.of(context).logCompare_altitude;
    }

    String toIntTick(double v) => v.round().toString();

    String timeLabelFromMinutes(double v) {
      final total = v.round();
      final sign = total < 0 ? '-' : '';
      final absTotal = total.abs();
      final hours = absTotal ~/ 60;
      final minutes = absTotal % 60;
      return '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    }

    String xValueLabel(double v) =>
        _xAxis == CompareXAxis.time ? timeLabelFromMinutes(v) : _fmt(v);

    double niceIntInterval(double min, double max) {
      final span = (max - min).abs();
      if (span == 0 || !span.isFinite) return 1;
      final raw = span / 6.0;
      if (raw <= 1) return 1;

      final pow10 =
          math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
      final norm = raw / pow10;
      final step = norm < 1.5
          ? 1.0
          : (norm < 3.0)
              ? 2.0
              : (norm < 7.0)
                  ? 5.0
                  : 10.0;
      return math.max(1, (step * pow10).round()).toDouble();
    }

    FlSpot? nearestSpotAtX(List<List<FlSpot>> segments, double x) {
      FlSpot? best;
      var bestDx = double.infinity;
      for (final seg in segments) {
        for (final p in seg) {
          final dx = (p.x - x).abs();
          if (dx < bestDx) {
            bestDx = dx;
            best = p;
          }
        }
      }
      return best;
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          LogCompareHeader(
            redLabel: widget.redLabel,
            blueLabel: widget.blueLabel,
            xAxis: _xAxis,
            yAxis: _yAxis,
            redVisible: _redVisible,
            blueVisible: _blueVisible,
            onToggleRedVisible: () =>
                setState(() => _redVisible = !_redVisible),
            onToggleBlueVisible: () =>
                setState(() => _blueVisible = !_blueVisible),
            onXAxisChanged: (v) => setState(() => _xAxis = v),
            onYAxisChanged: (v) => setState(() => _yAxis = v),
            speedMode: _speedMode,
            onSpeedModeChanged: (v) => setState(() => _speedMode = v),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            child: Align(
              alignment: Alignment.center,
              child: _touchX == null
                  ? const SizedBox.shrink()
                  : Builder(
                      builder: (context) {
                        final baseStyle =
                            (Theme.of(context).textTheme.bodySmall ??
                                    const TextStyle(fontSize: 12))
                                .copyWith(fontWeight: FontWeight.w700);
                        return Text.rich(
                          TextSpan(
                            style: baseStyle,
                            children: [
                              TextSpan(
                                  text:
                                      '${xReadoutLabel()}: ${xValueLabel(_touchX!)}'),
                              TextSpan(text: '   ${yReadoutLabel()}: '),
                              TextSpan(
                                text: _touchRedY == null
                                    ? '-'
                                    : _fmt(_touchRedY!),
                                style: baseStyle.copyWith(color: Colors.red),
                              ),
                              const TextSpan(text: ' / '),
                              TextSpan(
                                text: _touchBlueY == null
                                    ? '-'
                                    : _fmt(_touchBlueY!),
                                style: baseStyle.copyWith(color: Colors.blue),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                extraLinesData: ExtraLinesData(
                  verticalLines: _touchX == null
                      ? const []
                      : [
                          VerticalLine(
                            x: _touchX!,
                            color: Theme.of(context).colorScheme.outline,
                            strokeWidth: 1.5,
                            dashArray: [4, 4],
                          ),
                        ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    axisNameSize: 44,
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(xTitle()),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: niceIntInterval(minX, maxX),
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          _xAxis == CompareXAxis.time
                              ? timeLabelFromMinutes(v)
                              : toIntTick(v),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameSize: 32,
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(yTitle()),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 58,
                      interval: niceIntInterval(minY, maxY),
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          toIntTick(v),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) {
                    final touched = response?.lineBarSpots;
                    if (touched == null || touched.isEmpty) {
                      if (_touchX != null ||
                          _touchRedY != null ||
                          _touchBlueY != null) {
                        setState(() {
                          _touchX = null;
                          _touchRedY = null;
                          _touchBlueY = null;
                        });
                      }
                      return;
                    }

                    final spot = touched.first;
                    final touchX = spot.x;
                    double? redY;
                    double? blueY;

                    if (_redVisible && red.segments.isNotEmpty) {
                      final redSpot = nearestSpotAtX(red.segments, touchX);
                      if (redSpot != null) {
                        redY = redSpot.y;
                      }
                    }

                    if (_blueVisible && blue.segments.isNotEmpty) {
                      final blueSpot = nearestSpotAtX(blue.segments, touchX);
                      if (blueSpot != null) {
                        blueY = blueSpot.y;
                      }
                    }

                    if (touchX != _touchX ||
                        redY != _touchRedY ||
                        blueY != _touchBlueY) {
                      setState(() {
                        _touchX = touchX;
                        _touchRedY = redY;
                        _touchBlueY = blueY;
                      });
                    }
                  },
                ),
                lineBarsData: bars,
              ),
              duration: const Duration(milliseconds: 180),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  static double _niceInterval(double min, double max) {
    if (!min.isFinite || !max.isFinite) return 1;
    final span = (max - min).abs();
    if (span == 0) return 1;
    final raw = span / 6.0;
    final pow10 = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / pow10;
    double step;
    if (norm < 1.5)
      step = 1;
    else if (norm < 3)
      step = 2;
    else if (norm < 7)
      step = 5;
    else
      step = 10;
    return step * pow10;
  }
}
