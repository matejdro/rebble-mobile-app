import 'package:cobble/domain/db/models/app.dart';
import 'package:cobble/domain/db/models/next_sync_action.dart';
import 'package:cobble/domain/db/models/timeline_pin.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid_type/uuid_type.dart';

import '../cobble_database.dart';

class AppDao {
  Future<Database> _dbFuture;

  AppDao(this._dbFuture);

  Future<void> insertOrUpdateApp(App app) async {
    final db = await _dbFuture;

    db.insert(tableApps, app.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<App>> getAllInstalledApps() async {
    final db = await _dbFuture;

    final receivedApps = (await db.query(
      tableApps,
      where:
          "nextSyncAction != \"Delete\" AND nextSyncAction != \"DeleteThenIgnore\"",
    ));

    return receivedApps.map((e) => App.fromMap(e)).toList();
  }

  Future<App?> getApp(Uuid itemId) async {
    final db = await _dbFuture;

    final list = (await db.query(tableApps,
            where: "uuid = ?", whereArgs: [itemId.toString()]))
        .map((e) => App.fromMap(e))
        .toList();

    if (!list.isEmpty) {
      return list.first;
    } else {
      return null;
    }
  }

  Future<List<App>> getAllAppsWithPendingUpload() async {
    final db = await _dbFuture;

    return (await db.query(tableApps, where: "nextSyncAction = \"Upload\""))
        .map((e) => App.fromMap(e))
        .toList();
  }

  Future<List<App>> getAllAppsWithPendingDelete() async {
    final db = await _dbFuture;

    return (await db.query(tableApps,
            where:
                "nextSyncAction = \"Delete\" OR nextSyncAction = \"DeleteThenIgnore\""))
        .map((e) => App.fromMap(e))
        .toList();
  }

  Future<void> setSyncAction(
      Uuid appId, NextSyncAction newNextSyncAction) async {
    final db = await _dbFuture;

    await db.update(
        tableApps,
        {
          "nextSyncAction":
              TimelinePin.nextSyncActionEnumMap()[newNextSyncAction]
        },
        where: "uuid = ?",
        whereArgs: [appId.toString()]);
  }

  Future<void> delete(Uuid itemId) async {
    final db = await _dbFuture;

    await db
        .delete(tableApps, where: "uuid = ?", whereArgs: [itemId.toString()]);
  }

  Future<void> resetSyncStatus() async {
    final db = await _dbFuture;

    // Watch has been reset. We can delete all apps that were pending
    // deletion
    await db.delete(tableApps, where: "nextSyncAction = ?", whereArgs: [
      TimelinePin.nextSyncActionEnumMap()[NextSyncAction.Delete]
    ]);

    // Mark all apps to re-upload
    await db.update(
        tableApps,
        {
          "nextSyncAction":
              TimelinePin.nextSyncActionEnumMap()[NextSyncAction.Upload]
        },
        where: "nextSyncAction = ?",
        whereArgs: [
          TimelinePin.nextSyncActionEnumMap()[NextSyncAction.Nothing]
        ]);
  }
}

final AutoDisposeProvider<AppDao> appDaoProvider = Provider.autoDispose((ref) {
  final dbFuture = ref.watch(databaseProvider.future);
  return AppDao(dbFuture);
});

const tableApps = "app";