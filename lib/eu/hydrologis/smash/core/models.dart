/*
 * Copyright (c) 2019. Antonello Andrea (www.hydrologis.com). All rights reserved.
 * Use of this source code is governed by a GPL3 license that can be
 * found in the LICENSE file.
 */
import 'package:dart_jts/dart_jts.dart' hide Position;
import 'package:flutter/material.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong/latlong.dart';
import 'package:mapsforge_flutter/core.dart';
import 'package:smash/eu/hydrologis/dartlibs/dartlibs.dart';
import 'package:smash/eu/hydrologis/flutterlibs/geo/geo.dart';
import 'package:smash/eu/hydrologis/flutterlibs/geo/geopaparazzi/project_tables.dart';
import 'package:smash/eu/hydrologis/flutterlibs/geo/maps/geopackage.dart';
import 'package:smash/eu/hydrologis/flutterlibs/geo/maps/layers.dart';
import 'package:smash/eu/hydrologis/flutterlibs/workspace.dart';
import 'package:smash/eu/hydrologis/flutterlibs/geo/geopaparazzi/gp_database.dart';
import 'package:smash/eu/hydrologis/flutterlibs/util/logging.dart';
import 'package:smash/eu/hydrologis/flutterlibs/util/preferences.dart';
import 'package:smash/eu/hydrologis/smash/widgets/dashboard_utils.dart';
import 'package:path/path.dart';

const DEBUG_NOTIFICATIONS = true;

class ChangeNotifierPlus with ChangeNotifier {
  void notifyListenersMsg([String msg]) {
    if (DEBUG_NOTIFICATIONS) {
      print("${TimeUtilities.ISO8601_TS_FORMATTER.format(DateTime.now())}:: ${runtimeType.toString()}: ${msg ?? "notify triggered"}");
    }

    notifyListeners();
  }
}

/// Current Gps Status.
///
/// Provides tracking of position and parameters related to GPS state.
class GpsState extends ChangeNotifierPlus {
  GpsStatus _status = GpsStatus.OFF;
  Position _lastPosition;

  bool _isLogging = false;
  int _currentLogId;
  ProjectState _projectState;
  bool _insertInGps = true;

  int gpsMinDistance = 1;
  int gpsMaxDistance = 100;
  int gpsTimeInterval = 1;
  bool doTestLog = false;

  List<LatLng> _currentLogPoints = [];
  GpsStatus _lastGpsStatusBeforeLogging;

  void init() {
    gpsMinDistance = GpPreferences().getIntSync(KEY_GPS_MIN_DISTANCE, 1);
    gpsMaxDistance = GpPreferences().getIntSync(KEY_GPS_MAX_DISTANCE, 100);
    gpsTimeInterval = GpPreferences().getIntSync(KEY_GPS_TIMEINTERVAL, 1);
    doTestLog = GpPreferences().getBooleanSync(KEY_GPS_TESTLOG, false);
  }

  GpsStatus get status => _status;

  Position get lastGpsPosition => _lastPosition;

  set lastGpsPosition(Position position) {
    _lastPosition = position;
    notifyListeners(); //Msg("lastGpsPosition");
  }

  set lastGpsPositionQuiet(Position position) {
    _lastPosition = position;
  }

  /// Set the status without triggering a global notification.
  set statusQuiet(GpsStatus newStatus) {
    _status = newStatus;
  }

  set status(GpsStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners(); //Msg("status");
    }
  }

  bool get insertInGps => _insertInGps;

  bool get isLogging => _isLogging;

  int get currentLogId => _currentLogId;

  /// Set the _insertInGps without triggering a global notification.
  set insertInGpsQuiet(bool newInsertInGps) {
    if (_insertInGps != newInsertInGps) {
      _insertInGps = newInsertInGps;
      GpPreferences().setBoolean(KEY_DO_NOTE_IN_GPS, newInsertInGps);
    }
  }

  set insertInGps(bool newInsertInGps) {
    if (_insertInGps != newInsertInGps) {
      insertInGpsQuiet = newInsertInGps;
      notifyListenersMsg("insertInGps");
    }
  }

  set projectState(ProjectState state) {
    _projectState = state;
  }

  Future<void> addLogPoint(double longitude, double latitude, double altitude, int timestamp) async {
    if (_projectState != null) {
      LogDataPoint ldp = LogDataPoint();
      ldp.logid = currentLogId;
      ldp.lon = longitude;
      ldp.lat = latitude;
      ldp.altim = altitude;
      ldp.ts = timestamp;
      await _projectState.projectDb.addGpsLogPoint(currentLogId, ldp);
    }
  }

  Future<int> addGpsLog(String logName) async {
    if (_projectState != null) {
      Log l = new Log();
      l.text = logName;
      l.startTime = DateTime.now().millisecondsSinceEpoch;
      l.endTime = 0;
      l.isDirty = 0;
      l.lengthm = 0;
      LogProperty lp = new LogProperty();
      lp.isVisible = 1;
      lp.color = "#FF0000";
      lp.width = 3;
      var logId = await _projectState.projectDb.addGpsLog(l, lp);
      return logId;
    } else {
      return -1;
    }
  }

  /// Start logging to database.
  ///
  /// This creates a new log with the name [logName] and returns
  /// the id of the created log.
  ///
  /// Once logging, the [_onPositionUpdate] method adds the
  /// points as the come.
  Future<int> startLogging(String logName) async {
    try {
      var logId = await addGpsLog(logName);
      _currentLogId = logId;
      _isLogging = true;

      _lastGpsStatusBeforeLogging = _status;
      _status = GpsStatus.LOGGING;

      notifyListenersMsg("startLogging");

      return logId;
    } catch (e) {
      GpLogger().e("Error creating log", e);
      return null;
    }
  }

  /// Get the list of current log points.
  List<LatLng> get currentLogPoints => _currentLogPoints;

  /// Stop logging to database.
  ///
  /// This also properly closes the recorded log.
  Future<void> stopLogging() async {
    _isLogging = false;
    _currentLogPoints.clear();

    if (_projectState != null) {
      int endTs = DateTime.now().millisecondsSinceEpoch;
      await _projectState.projectDb.updateGpsLogEndts(_currentLogId, endTs);
    }

    if (_lastGpsStatusBeforeLogging == null) _lastGpsStatusBeforeLogging = GpsStatus.ON_NO_FIX;
    _status = _lastGpsStatusBeforeLogging;
    _lastGpsStatusBeforeLogging = null;
    notifyListenersMsg("stopLogging");
  }

  bool hasFix() {
    return _status == GpsStatus.ON_WITH_FIX || _status == GpsStatus.LOGGING;
  }
}

/// Current state of the Map view.
///
/// This provides tracking of map view and general status.
class SmashMapState extends ChangeNotifierPlus {
  static final MAXZOOM = 22.0;
  static final MINZOOM = 1.0;
  Coordinate _center = Coordinate(11.33140, 46.47781);
  double _zoom = 16;
  double _heading = 0;
  MapController mapController;

  /// Defines whether the map should center on the gps position
  bool _centerOnGps = true;

  /// Defines whether the map should rotate following the gps heading
  bool _rotateOnHeading = true;

  void init(Coordinate center, double zoom) {
    _center = center;
    _zoom = zoom;
  }

  Coordinate get center => _center;

  /// Set the center of the map.
  ///
  /// Notify anyone that needs to act accordingly.
  set center(Coordinate newCenter) {
    if (_center == newCenter) {
      // trigger a change in the handler
      // which would not if the coord remains the same
      _center = Coordinate(newCenter.x - 0.00000001, newCenter.y - 0.00000001);
    } else {
      _center = newCenter;
    }
    if (mapController != null) {
      mapController.move(LatLng(_center.y, _center.x), mapController.zoom);
    }
    notifyListenersMsg("set center");
  }

  double get zoom => _zoom;

  /// Set the zoom of the map.
  ///
  /// Notify anyone that needs to act accordingly.
  set zoom(double newZoom) {
    _zoom = newZoom;
    if (mapController != null) {
      mapController.move(mapController.center, newZoom);
    }
    notifyListenersMsg("set zoom");
  }

  /// Set the center and zoom of the map.
  ///
  /// Notify anyone that needs to act accordingly.
  void setCenterAndZoom(Coordinate newCenter, double newZoom) {
    _center = newCenter;
    _zoom = newZoom;
    if (mapController != null) {
      mapController.move(LatLng(newCenter.y, newCenter.x), newZoom);
    }
    notifyListenersMsg("setCenterAndZoom");
  }

  /// Set the map bounds to a given envelope.
  ///
  /// Notify anyone that needs to act accordingly.
  void setBounds(Envelope envelope) {
    if (mapController != null) {
      mapController.fitBounds(LatLngBounds(
        LatLng(envelope.getMinY(), envelope.getMinX()),
        LatLng(envelope.getMaxY(), envelope.getMaxX()),
      ));
      notifyListenersMsg("setBounds");
    }
  }

  double get heading => _heading;

  set heading(double heading) {
    _heading = heading;
    if (mapController != null) {
      if (rotateOnHeading) {
        if (heading < 0) {
          heading = 360 + heading;
        }
        mapController.rotate(-heading);
      } else {
        mapController.rotate(0);
      }
    }
    notifyListenersMsg("set heading");
  }

  /// Store the last position in memory and to the preferences.
  void setLastPosition(Coordinate newCenter, double newZoom) {
    _center = newCenter;
    _zoom = newZoom;
    GpPreferences().setLastPosition(_center.x, _center.y, newZoom);
  }

  bool get centerOnGps => _centerOnGps;

  set centerOnGpsQuiet(bool newCenterOnGps) {
    _centerOnGps = newCenterOnGps;
    GpPreferences().setCenterOnGps(newCenterOnGps);
  }

  set centerOnGps(bool newCenterOnGps) {
    centerOnGpsQuiet = newCenterOnGps;
    notifyListenersMsg("centerOnGps");
  }

  bool get rotateOnHeading => _rotateOnHeading;

  set rotateOnHeadingQuiet(bool newRotateOnHeading) {
    _rotateOnHeading = newRotateOnHeading;
    GpPreferences().setRotateOnHeading(newRotateOnHeading);
  }

  set rotateOnHeading(bool newRotateOnHeading) {
    rotateOnHeadingQuiet = newRotateOnHeading;
    notifyListenersMsg("rotateOnHeading");
  }

  void zoomIn() {
    if (mapController != null) {
      var z = mapController.zoom + 1;
      if (z > MAXZOOM) z = MAXZOOM;
      zoom = z;
    }
  }

  void zoomOut() {
    if (mapController != null) {
      var z = mapController.zoom - 1;
      if (z < MINZOOM) z = MINZOOM;
      zoom = z;
    }
  }
}

/// The provider object of the current project status
///
/// This provides the project database and triggers notification when that changes.
class ProjectState extends ChangeNotifierPlus {
  String _projectName = "No project loaded";
  String _projectPath;
  GeopaparazziProjectDb _db;
  ProjectData _projectData;

  BuildContext context;
  GlobalKey<ScaffoldState> scaffoldKey;

  String get projectPath => _projectPath;

  String get projectName => _projectName;

  GeopaparazziProjectDb get projectDb => _db;

  ProjectData get projectData => _projectData;

  Future<void> setNewProject(String path) async {
    GpLogger().d("Set new project: $path");
    await close();
    _projectPath = path;
    await openDb(_projectPath);

    notifyListenersMsg("setNewProject");
  }

  Future<void> openDb([String projectPath]) async {
    _projectPath = projectPath;
    if (_projectPath == null) {
      _projectPath = await GpPreferences().getString(KEY_LAST_GPAPPROJECT);
      GpLogger().d("Read db path from preferences: $_projectPath");
    }
    if (_projectPath == null) {
      GpLogger().w("No project path found creating default");
      var projectsFolder = await Workspace.getProjectsFolder();
      _projectPath = FileUtilities.joinPaths(projectsFolder.path, "smash.gpap");
    }
    try {
      GpLogger().d("Opening db $_projectPath...");
      _db = GeopaparazziProjectDb(_projectPath);
      await _db.openOrCreate();
      GpLogger().d("Db opened: $_projectPath");
    } catch (e) {
      GpLogger().e("Error opening project db: ", e);
    }

    await _db.createNecessaryExtraTables();
    await GpPreferences().setString(KEY_LAST_GPAPPROJECT, _projectPath);
    _projectName = FileUtilities.nameFromFile(_projectPath, false);
  }

  Future<void> close() async {
    if (_db != null && _db.isOpen()) {
      await _db.close();
      GpLogger().d("Closed db: ${_db.path}");
    }
    _db = null;
    _projectPath = null;
    context = null;
    scaffoldKey = null;
  }

  Future<void> reloadProject() async {
    if (projectDb == null) return;
    await reloadProjectQuiet();
    notifyListenersMsg('reloadProject');
  }

  Future<void> reloadProjectQuiet() async {
    if (projectDb == null) return;
    ProjectData tmp = ProjectData();
    tmp.projectName = basenameWithoutExtension(projectDb.path);
    tmp.projectDirName = dirname(projectDb.path);
    tmp.simpleNotesCount = await projectDb.getSimpleNotesCount(false);
    var imageNotescount = await projectDb.getImagesCount(false);
    tmp.simpleNotesCount += imageNotescount;
    tmp.logsCount = await projectDb.getGpsLogCount(false);
    tmp.formNotesCount = await projectDb.getFormNotesCount(false);

    List<Marker> tmpList = [];
    DataLoaderUtilities.loadImageMarkers(projectDb, tmpList, this);
    DataLoaderUtilities.loadNotesMarkers(projectDb, tmpList, this);
    tmp.geopapMarkers = tmpList;
    tmp.geopapLogs = await DataLoaderUtilities.loadLogLinesLayer(projectDb);
    _projectData = tmp;
  }
}

class ProjectData {
  String projectName;
  String projectDirName;
  int simpleNotesCount;
  int logsCount;
  int formNotesCount;
  List<Marker> geopapMarkers;
  PolylineLayerOptions geopapLogs;
}

class MapTapState extends ChangeNotifier {
  LatLng tappedLatLong;

  tap(LatLng newTapPosition) {
    tappedLatLong = newTapPosition;
    notifyListeners();
  }
}

class InfoToolState extends ChangeNotifier {
  bool isEnabled = false;
  bool isSearching = false;

  double xTapPosition;
  double yTapPosition;
  double tapRadius;

  void setTapAreaCenter(double x, double y) {
    xTapPosition = x;
    yTapPosition = y;
    notifyListeners();
  }

  void setEnabled(bool isEnabled) {
    this.isEnabled = isEnabled;
    if (isEnabled) {
      // when enabled the tap position is reset
      xTapPosition = null;
      yTapPosition = null;
    }
    notifyListeners();
  }

  void setSearching(bool isSearching) {
    this.isSearching = isSearching;
    notifyListeners();
  }

  void tappedOn(LatLng tapLatLong, BuildContext context) async {
    if (isEnabled) {
      var env = Envelope.fromCoordinate(Coordinate(tapLatLong.longitude, tapLatLong.latitude));
      env.expandByDistance(0.001);
      List<LayerSource> visibleVectorLayers = LayerManager().getActiveLayers().where((l) => l is VectorLayerSource && l.isActive()).toList();
      for (var vLayer in visibleVectorLayers) {
        if (vLayer is GeopackageSource) {
          var db = await ConnectionsHandler().open(vLayer.getAbsolutePath());
          QueryResult queryResult = await db.getTableData(vLayer.getName(), envelope: env);
          if (queryResult.data.isNotEmpty) {
            print("Found data for: " + vLayer.getName());
          }
        }
      }
    }
  }
}
