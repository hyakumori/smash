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
        "/projects.json?limit=100000000&include=enabled_modules";

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
          for (Map<String, dynamic> module in ret["enabled_modules"]) {
            /**
             * getting only Projects with gtt_smash module enabled
             */
            if (module["name"] == "gtt_smash") {
              retVal.add(ret);
              break;
            }
          }
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

  static int getPriorityId(String p, List<dynamic> arr) {
    int count = 1;

    for (Map<String, dynamic> a in arr) {
      if (p == a["item"]) {
        break;
      }
      count++;
    }
    return count;
  }

  static Map<String, dynamic> createIssue(Note note, String selectedProj) {
    String geoJson = "{\"type\": \"Feature\",\"properties\": {},"
        "\"geometry\": {\"type\": \"Point\",\"coordinates\": "
        "[${note.lon}, ${note.lat}]}}";

    String projectId = selectedProj;
    String subject = note.text.isEmpty ? "SMASH issue" : note.text;
    String description =
        note.description.isEmpty ? "SMASH issue" : note.description;

    int trackerId = 3;
    int priorityId = 2;
    String isPrivate = "false";

    List<Map<String, dynamic>> customFields = List<Map<String, dynamic>>();

    if (note.hasForm()) {
      final form = json.decode(note.form);
      String sectionName = form["sectionname"];

      if (sectionName == "text note") {
        for (var f in form["forms"][0]["formitems"]) {
          if (f["key"] == "title") {
            subject = f["value"];
          }
          if (f["key"] == "description") {
            description = f["value"];
          }
        }
      } else if (sectionName.startsWith("GTT_")) {
        for (var f in form["forms"][0]["formitems"]) {
          String fKey = f["key"];

          switch (fKey) {
            case "project_id":
              //projectId = f["value"];
              break;
            case "tracker_id":
              trackerId = int.parse(f["value"]);
              break;
            case "priority_id":
              priorityId = getPriorityId(f["value"], f["values"]["items"]);
              break;
            case "is_private":
              isPrivate = f["value"];
              break;
            case "subject":
              subject = f["value"];
              break;
            case "description":
              description = f["value"];
              break;
          }

          if (fKey.startsWith("cf_")) {
            Map<String, dynamic> customField = {
              "id": int.parse(fKey.substring(3)),
              "val": f["value"],
            };

            customFields.add(customField);
          }
        }
      } else {
        description = note.form;
      }
    }

    Map<String, dynamic> params = {
      "project_id": projectId,
      "priority_id": priorityId,
      "tracker_id": trackerId,
      "subject": subject,
      "description": description,
      "is_private": isPrivate,
      "custom_fields": customFields,
      "geojson": geoJson,
    };

    Map<String, dynamic> issue = {
      "issue": params,
    };

    debugPrint("Issue: ${issue.toString()}");

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