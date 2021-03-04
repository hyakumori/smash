/*
 * Copyright (c) 2019-2020. Antonello Andrea (www.hydrologis.com). All rights reserved.
 * Use of this source code is governed by a GPL3 license that can be
 * found in the LICENSE file.
 */

import 'dart:async';
import 'dart:convert';

import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:smash/eu/hydrologis/smash/gtt/gtt_uilities.dart';
import 'package:smash/eu/hydrologis/smash/project/objects/images.dart';
import 'package:smash/eu/hydrologis/smash/project/objects/logs.dart';
import 'package:smash/eu/hydrologis/smash/project/objects/notes.dart';
import 'package:smash/eu/hydrologis/smash/project/project_database.dart';
import 'package:smashlibs/smashlibs.dart';

class GttExportWidget extends StatefulWidget {
  final GeopaparazziProjectDb projectDb;

  GttExportWidget(this.projectDb, {Key key}) : super(key: key);

  @override
  _GttExportWidgetState createState() => new _GttExportWidgetState();
}

class _GttExportWidgetState extends State<GttExportWidget> {
  /*
   * 0 = loading data stats
   * 1 = show data stats
   * 2 = uploading data
   *
   *  7 = no Projects Listed for User
   *  8 = no server apiKey available
   *  9 = no server user available
   * 10 = no server pwd available
   * 11 = no server url available
   * 12 = upload error
   */
  int _status = 0;

  String _serverUrl;
  String _authHeader;
  String _uploadDataUrl;

  int _gpsLogCount;
  int _simpleNotesCount;
  int _formNotesCount;
  int _imagesCount;

  List<Widget> _uploadTiles;
  List<DropdownMenuItem> _projects = List<DropdownMenuItem>();
  String _selectedProj;

  @override
  void initState() {
    init();

    super.initState();
  }

  Future<void> init() async {
    _serverUrl = GpPreferences().getStringSync(GttUtilities.KEY_GTT_SERVER_URL);

    if (_serverUrl == null) {
      setState(() {
        _status = 11;
      });
      return;
    }

    String pwd = GpPreferences().getStringSync(GttUtilities.KEY_GTT_SERVER_PWD);

    if (pwd == null || pwd.trim().isEmpty) {
      setState(() {
        _status = 10;
      });
      return;
    }

    String usr =
        GpPreferences().getStringSync(GttUtilities.KEY_GTT_SERVER_USER);

    if (usr == null || usr.trim().isEmpty) {
      setState(() {
        _status = 9;
      });
      return;
    }

    /**
     * Getting GTT API Key
     */
    String key = GpPreferences().getStringSync(GttUtilities.KEY_GTT_SERVER_KEY);

    if (key == null || key.trim().isEmpty) {
      String apiKey = await GttUtilities.getApiKey();

      if (apiKey == null || apiKey.trim().isEmpty) {
        setState(() {
          _status = 8;
        });
        return;
      }

      await GpPreferences().setString(GttUtilities.KEY_GTT_SERVER_KEY, apiKey);
      debugPrint("API Key: $apiKey");
    }

    /**
     * Getting User Projects List
     */
    List<Map<String, dynamic>> projects = await GttUtilities.getUserProjects();

    if (projects.isEmpty) {
      setState(() {
        _status = 7;
      });
      return;
    }

    for (Map<String, dynamic> p in projects) {
      String s = p["name"];
      String v = "${p["id"]}";
      debugPrint("$v,$s");

      String sub = s.length < 25 ? s : "${s.substring(0, 20)}...";
      _projects.add(DropdownMenuItem(child: Text(sub), value: v));
    }

    _selectedProj = "${projects[0]["id"]}";

    //_uploadDataUrl = _serverUrl + GssUtilities.SYNCH_PATH;
    //_authHeader = await GssUtilities.getAuthHeader(pwd);

    /**
     * now gather data stats from db
     */
    gatherStats();
  }

  gatherStats() {
    /**
     * now gather data stats from db
     */
    var db = widget.projectDb;
    _gpsLogCount = db.getGpsLogCount(true);
    _simpleNotesCount = db.getSimpleNotesCount(true);
    _formNotesCount = db.getFormNotesCount(true);
    _imagesCount = db.getImagesCount(true);

    var allCount =
        _gpsLogCount + _simpleNotesCount + _formNotesCount + _imagesCount;
    setState(() {
      _status = allCount > 0 ? 1 : -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget projWidget = Container(
      padding: EdgeInsets.all(10),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SmashUI.normalText(
              "Choose GTT Project:",
              bold: true,
              color: Colors.blue,
            ),
            DropdownButton(
                items: _projects,
                value: _selectedProj,
                onChanged: (s) => setState(() => _selectedProj = s)),
          ],
        ),
      ),
    );

    return new Scaffold(
      appBar: new AppBar(
        title: new Text("GTT Export"),
        actions: _status < 2
            ? <Widget>[
                IconButton(
                  icon: Icon(MdiIcons.restore),
                  onPressed: () async {
                    var doIt = await SmashDialogs.showConfirmDialog(context,
                        "Set project to DIRTY?", "This can't be undone!");
                    if (doIt) {
                      widget.projectDb.updateDirty(true);
                      setState(() {
                        _status = 0;
                      });
                      gatherStats();
                    }
                  },
                  tooltip: "Restore project as all dirty.",
                ),
                IconButton(
                  icon: Icon(MdiIcons.wiperWash),
                  onPressed: () async {
                    var doIt = await SmashDialogs.showConfirmDialog(context,
                        "Set project to CLEAN?", "This can't be undone!");
                    if (doIt) {
                      widget.projectDb.updateDirty(false);
                      setState(() {
                        _status = 0;
                      });
                      gatherStats();
                    }
                  },
                  tooltip: "Restore project as all clean.",
                ),
              ]
            : <Widget>[],
      ),
      body: _status == -1
          ? Center(child: SmashUI.errorWidget("Nothing to sync.", bold: true))
          : _status == 0
              ? Center(
                  child:
                      SmashCircularProgress(label: "Collecting sync stats..."),
                )
              : _status == 12
                  ? Center(
                      child: Padding(
                        padding: SmashUI.defaultPadding(),
                        child: SmashUI.errorWidget(
                            "Unable to sync due to an error, check diagnostics."),
                      ),
                    )
                  : _status == 11
                      ? Center(
                          child: Padding(
                            padding: SmashUI.defaultPadding(),
                            child: SmashUI.titleText(
                                "No GSS server url has been set. "
                                "Check your settings."),
                          ),
                        )
                      : _status == 10
                          ? Center(
                              child: Padding(
                                padding: SmashUI.defaultPadding(),
                                child: SmashUI.titleText(
                                    "No GSS server password has been set. "
                                    "Check your settings."),
                              ),
                            )
                          : _status == 9
                              ? Center(
                                  child: Padding(
                                    padding: SmashUI.defaultPadding(),
                                    child: SmashUI.titleText(
                                        "No GSS server user has been set. "
                                        "Check your settings."),
                                  ),
                                )
                              : _status == 7
                                  ? Center(
                                      child: Padding(
                                        padding: SmashUI.defaultPadding(),
                                        child: SmashUI.titleText(
                                            "Unable to retrieve GTT Projects "
                                            "List. Check your settings."),
                                      ),
                                    )
                                  : _status == 8
                                      ? Center(
                                          child: Padding(
                                            padding: SmashUI.defaultPadding(),
                                            child: SmashUI.titleText(
                                                "Unable to retrieve GTT Api Key. "
                                                "Check your settings."),
                                          ),
                                        )
                                      : _status == 1
                                          ? // View stats
                                          Center(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  Padding(
                                                    padding: SmashUI
                                                        .defaultPadding(),
                                                    child: SmashUI.titleText(
                                                        "Sync Stats",
                                                        bold: true),
                                                  ),
                                                  Padding(
                                                    padding: SmashUI
                                                        .defaultPadding(),
                                                    child: SmashUI.smallText(
                                                        "The following data will be uploaded upon sync.",
                                                        color: Colors.grey),
                                                  ),
                                                  Expanded(
                                                    child: ListView(
                                                      children: <Widget>[
                                                        projWidget,
                                                        ListTile(
                                                          leading: Icon(
                                                            SmashIcons.logIcon,
                                                            color: SmashColors
                                                                .mainDecorations,
                                                          ),
                                                          title: SmashUI.normalText(
                                                              "Gps Logs: $_gpsLogCount"),
                                                        ),
                                                        ListTile(
                                                          leading: Icon(
                                                            SmashIcons
                                                                .simpleNotesIcon,
                                                            color: SmashColors
                                                                .mainDecorations,
                                                          ),
                                                          title: SmashUI.normalText(
                                                              "Simple Notes: $_simpleNotesCount"),
                                                        ),
                                                        ListTile(
                                                          leading: Icon(
                                                            SmashIcons
                                                                .formNotesIcon,
                                                            color: SmashColors
                                                                .mainDecorations,
                                                          ),
                                                          title: SmashUI.normalText(
                                                              "Form Notes: $_formNotesCount"),
                                                        ),
                                                        ListTile(
                                                          leading: Icon(
                                                            SmashIcons
                                                                .imagesNotesIcon,
                                                            color: SmashColors
                                                                .mainDecorations,
                                                          ),
                                                          title: SmashUI.normalText(
                                                              "Images: $_imagesCount"),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : _status == 2
                                              ? Center(
                                                  child: ListView(
                                                    children: _uploadTiles,
                                                  ),
                                                )
                                              : Container(
                                                  child:
                                                      Text("Should not happen"),
                                                ),
      floatingActionButton: _status < 2 && _status != -1
          ? FloatingActionButton.extended(
              icon: Icon(SmashIcons.upload),
              onPressed: () async {
                if (!await NetworkUtilities.isConnected()) {
                  SmashDialogs.showOperationNeedsNetwork(context);
                } else {
                  await uploadProjectData();
                }
              },
              label: Text("Upload"))
          : null,
    );
  }

  Map<String, dynamic> createIssue(Note note) {
    String geoJson = "{\"type\": \"Feature\",\"properties\": {},"
        "\"geometry\": {\"type\": \"Point\",\"coordinates\": "
        "[${note.lon}, ${note.lat}]}}";

    if (note.hasForm()) {
      final form = json.decode(note.form);
      if ("text note".compareTo(form["sectionname"]) == 0) {
        for (var f in form["forms"][0]["formitems"]) {
          debugPrint("KEY:  ${f["key"]}");
        }
      }
    }
    Map<String, dynamic> params = {
      "project_id": _selectedProj,
      "priority_id": 2,
      "tracker_id": 3,
      "subject": note.text.isEmpty ? "SMASH issue" : note.text,
      "description": note.hasForm() ? note.form : "SMASH issue",
      "geojson": geoJson,
    };

    Map<String, dynamic> issue = {
      "issue": params,
    };

    return issue;
  }

  Future uploadProjectData() async {
    var db = widget.projectDb;
    Dio dio = NetworkHelper.getNewDioInstance();
    ValueNotifier<int> uploadOrder = ValueNotifier<int>(0);
    int order = 0;

    _uploadTiles = [];

    List<Note> simpleNotes = db.getNotes(doSimple: true, onlyDirty: true);
    for (Note note in simpleNotes) {
      Map<String, dynamic> ret =
          await GttUtilities.postIssue(createIssue(note));
      debugPrint("SimpleNote status_code: ${ret["status_code"]}, "
          "status_message: ${ret["status_message"]}");
      /*
      var uploadWidget = ProjectDataUploadListTileProgressWidget(
        dio,
        db,
        _uploadDataUrl,
        note,
        authHeader: _authHeader,
        orderNotifier: uploadOrder,
        order: order++,
      );
      _uploadTiles.add(uploadWidget);
       */
    }
    List<Note> formNotes = db.getNotes(doSimple: false, onlyDirty: true);
    for (Note note in formNotes) {
      Map<String, dynamic> ret =
          await GttUtilities.postIssue(createIssue(note));
      debugPrint("FormNote status_code: ${ret["status_code"]}, "
          "status_message: ${ret["status_message"]}");
      /*
      var uploadWidget = ProjectDataUploadListTileProgressWidget(
        dio,
        db,
        _uploadDataUrl,
        note,
        authHeader: _authHeader,
        orderNotifier: uploadOrder,
        order: order++,
      );
      _uploadTiles.add(uploadWidget);
       */
    }
    List<DbImage> imagesList = db.getImages(onlyDirty: true);
    for (var image in imagesList) {
      /*
      var uploadWidget = ProjectDataUploadListTileProgressWidget(
        dio,
        db,
        _uploadDataUrl,
        image,
        authHeader: _authHeader,
        orderNotifier: uploadOrder,
        order: order++,
      );
      _uploadTiles.add(uploadWidget);
       */
    }

    List<Log> logsList = db.getLogs(onlyDirty: true);
    for (Log log in logsList) {
      /*
      var uploadWidget = ProjectDataUploadListTileProgressWidget(
        dio,
        db,
        _uploadDataUrl,
        log,
        authHeader: _authHeader,
        orderNotifier: uploadOrder,
        order: order++,
      );
      _uploadTiles.add(uploadWidget);
       */
    }

    setState(() {
      _status = 2;
    });
  }
}
