import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:smash/eu/hydrologis/smash/project/objects/notes.dart';
import 'package:smashlibs/smashlibs.dart';

class GttUtilities {
  static final String KEY_GTT_SERVER_URL = "key_gtt_server_url";
  static final String KEY_GTT_SERVER_USER = "key_gtt_server_user";
  static final String KEY_GTT_SERVER_PWD = "key_gtt_server_pwd";
  static final String KEY_GTT_SERVER_KEY = "key_gtt_server_apiKey";

  static Future<String> getApiKey() async {
    String retVal;

    String pwd = GpPreferences().getStringSync(KEY_GTT_SERVER_PWD);
    String usr = GpPreferences().getStringSync(KEY_GTT_SERVER_USER);
    String url =
        "${GpPreferences().getStringSync(KEY_GTT_SERVER_URL)}/my/account.json";

    try {
      Dio dio = NetworkHelper.getNewDioInstance();

      Response response = await dio.get(
        url,
        options: Options(
          headers: {
            "Authorization":
                "Basic " + Base64Encoder().convert("$usr:$pwd".codeUnits),
            "Content-Type": "application/json",
          },
        ),
      );

      debugPrint(
          "Code: ${response.statusCode} Response: ${response.data.toString()}");

      if (response.statusCode == 200) {
        Map<String, dynamic> r = response.data;
        retVal = r["user"]["api_key"];
      }
    } catch (exception) {
      debugPrint("API KEY Error: $exception");
    }

    return retVal;
  }

  static Future<List<Map<String, dynamic>>> getUserProjects() async {
    List<Map<String, dynamic>> retVal = List<Map<String, dynamic>>();

    String url = "${GpPreferences().getStringSync(KEY_GTT_SERVER_URL)}"
        "/projects.json?limit=100000000";

    String apiKey = GpPreferences().getStringSync(KEY_GTT_SERVER_KEY);

    try {
      Dio dio = NetworkHelper.getNewDioInstance();

      Response response = await dio.get(
        url,
        options: Options(
          headers: {
            "X-Redmine-API-Key": apiKey,
            "Content-Type": "application/json",
          },
        ),
      );

      if (response.statusCode == 200) {
        debugPrint("Msg: ${response.statusMessage} Response Records: "
            "${response.data["total_count"]}");

        //retVal = response.data["projects"] as List<Map<String, dynamic>>;
        for (Map<String, dynamic> ret in response.data["projects"]) {
          retVal.add(ret);
        }
      }
    } catch (exception) {
      debugPrint("User Projects Error: $exception");
    }
    return retVal;
  }

  static Future<Map<String, dynamic>> postIssue(
      Map<String, dynamic> params) async {
    Map<String, dynamic> retVal = Map<String, dynamic>();

    String url = "${GpPreferences().getStringSync(KEY_GTT_SERVER_URL)}"
        "/issues.json";

    String apiKey = GpPreferences().getStringSync(KEY_GTT_SERVER_KEY);

    try {
      Dio dio = NetworkHelper.getNewDioInstance();

      Response response = await dio.post(
        url,
        options: Options(
          headers: {
            "X-Redmine-API-Key": apiKey,
            "Content-Type": "application/json",
          },
        ),
        data: params,
      );

      retVal = {
        "status_code": response.statusCode,
        "status_message": response.statusMessage,
      };
    } catch (exception) {
      debugPrint("User Projects Error: $exception");
    }
    return retVal;
  }

  static Map<String, dynamic> createIssue(Note note, String selectedProj) {
    String geoJson = "{\"type\": \"Feature\",\"properties\": {},"
        "\"geometry\": {\"type\": \"Point\",\"coordinates\": "
        "[${note.lon}, ${note.lat}]}}";

    String subject = note.text.isEmpty ? "SMASH issue" : note.text;
    String description =
        note.description.isEmpty ? "SMASH issue" : note.description;

    if (note.hasForm()) {
      final form = json.decode(note.form);
      if ("text note".compareTo(form["sectionname"]) == 0) {
        for (var f in form["forms"][0]["formitems"]) {
          if ("title".compareTo(f["key"]) == 0) {
            subject = f["value"];
          } else if ("description".compareTo(f["key"]) == 0) {
            description = f["value"];
          }
        }
      } else {
        description = note.form;
      }
    }

    Map<String, dynamic> params = {
      "project_id": selectedProj,
      "priority_id": 2,
      "tracker_id": 3,
      "subject": subject,
      "description": description,
      "geojson": geoJson,
    };

    Map<String, dynamic> issue = {
      "issue": params,
    };

    return issue;
  }

  static Widget getResultTile(String name, String description) {
    return ListTile(
      leading: Icon(
        SmashIcons.upload,
        color: SmashColors.mainDecorations,
      ),
      title: Text(name),
      subtitle: Text(description),
      onTap: () {},
    );
  }
}
