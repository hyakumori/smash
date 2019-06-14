/*
 * Copyright (c) 2019. Antonello Andrea (www.hydrologis.com). All rights reserved.
 * Use of this source code is governed by a GPL3 license that can be
 * found in the LICENSE file.
 */
import 'package:sqflite/sqflite.dart';


String NOTES_TABLE = "notes";
/*
 * id of the note, Generated by the db.
 */
String COLUMN_ID = "_id";
/*
 * Longitude of the note in WGS84.
 */
String COLUMN_LON = "lon";
/*
 * Latitude of the note in WGS84.
 */
String COLUMN_LAT = "lat";
/*
 * Elevation of the note.
 */
String COLUMN_ALTIM = "altim";
/*
 * Timestamp of the note.
 */
String COLUMN_TS = "ts";
/*
 * Description of the note.
 */
String COLUMN_DESCRIPTION = "description";
/*
 * Simple text of the note.
 */
String COLUMN_TEXT = "text";
/*
 * Form data of the note.
 */
String COLUMN_FORM = "form";
/*
 * Is dirty field =0 = false, 1 = true)
 */
String COLUMN_ISDIRTY = "isdirty";
/*
 * Style of the note.
 */
String COLUMN_STYLE = "style";

class Note {
  int id;
  String text;
  String description;
  int timeStamp;
  double lon;
  double lat;
  double altim;
  String style;
  String form;
  int isDirty;
}

/// Get the count of the current notes
///
/// Get the count on a given [db], using [onlyDirty] to count only dirty notes.
Future<int> getNotesCount(Database db, bool onlyDirty) async {
  String where = !onlyDirty ? "" : " where ${COLUMN_ISDIRTY} = 1";
  List<Map<String, dynamic>> resNotes =
      await db.rawQuery("SELECT count(*) as count FROM ${NOTES_TABLE} ${where}");

  var resNote = resNotes[0];
  var count = resNote["count"];
  return count;
}

//queryNotes(Database db) async {
//  // NOTES
//  List<Map<String, dynamic>> resNotes =
//      await db.query("notes", columns: ['lat', 'lon', 'text', 'form']);
//  resNotes.forEach((map) {
//    var lat = map["lat"];
//    var lon = map["lon"];
//    var text = map["text"];
//    var label = "note: ${text}\nlat: ${lat}\nlon: ${lon}";
//  });
//}
