import 'package:cobble/domain/calendar/calendar_list.dart';
import 'package:cobble/domain/calendar/device_calendar_plugin_provider.dart';
import 'package:cobble/domain/connection/connection_state_provider.dart';
import 'package:cobble/domain/permissions.dart';
import 'package:cobble/infrastructure/datasources/paired_storage.dart';
import 'package:cobble/infrastructure/datasources/preferences.dart';
import 'package:cobble/infrastructure/pigeons/pigeons.g.dart';
import 'package:cobble/ui/common/icons/watch_icon.dart';
import 'package:cobble/ui/devoptions/dev_options_page.dart';
import 'package:cobble/ui/router/cobble_navigator.dart';
import 'package:cobble/ui/router/cobble_scaffold.dart';
import 'package:cobble/ui/router/cobble_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/all.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../common/icons/fonts/rebble_icons.dart';

class TestTab extends HookWidget implements CobbleScreen {
  final NotificationsControl notifications = NotificationsControl();

  final ConnectionControl connectionControl = ConnectionControl();
  final DebugControl debug = DebugControl();

  @override
  Widget build(BuildContext context) {
    final connectionState = useProvider(connectionStateProvider.state);
    final defaultWatch = useProvider(defaultWatchProvider);
    final calendars = useProvider(calendarListProvider.state);
    final calendarSelector = useProvider(calendarListProvider);
    final calendarControl = useProvider(calendarControlProvider);

    final permissionControl = useProvider(permissionControlProvider);
    final permissionCheck = useProvider(permissionCheckProvider);

    final preferences = useProvider(preferencesProvider);
    final calendarSyncEnabled = useProvider(calendarSyncEnabledProvider);
    final phoneNotificationsMuteEnabled =
        useProvider(phoneNotificationsMuteProvider);
    final phoneCallsMuteEnabled = useProvider(phoneCallsMuteProvider);

    useEffect(() {
      Future.microtask(() async {
        if (!(await permissionCheck.hasCalendarPermission()).value) {
          await permissionControl.requestCalendarPermission();
        }
        if (!(await permissionCheck.hasLocationPermission()).value) {
          await permissionControl.requestLocationPermission();
        }

        if (defaultWatch != null) {
          if (!(await permissionCheck.hasNotificationAccess()).value) {
            permissionControl.requestNotificationAccess();
          }

          if (!(await permissionCheck.hasBatteryExclusionEnabled()).value) {
            permissionControl.requestBatteryExclusion();
          }
        }
      });
      return null;
    }, ["one-time"]);

    String statusText;
    if (connectionState.isConnecting == true) {
      statusText = "Connecting to ${connectionState.currentWatchAddress}";
    } else if (connectionState.isConnected == true) {
      PebbleWatchModel model = PebbleWatchModel.rebble_logo;
      String fwVersion = "unknown";

      if (connectionState.currentConnectedWatch != null) {
        model = connectionState.currentConnectedWatch.model;
        fwVersion =
            connectionState.currentConnectedWatch.runningFirmware.version;
      }

      statusText = "Connected to ${connectionState.currentWatchAddress}" +
          " ($model, firmware $fwVersion)";
    } else {
      statusText = "Disconnected";
    }

    return CobbleScaffold.tab(
      title: "Testing",
      subtitle: 'Testing subtitle',
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              RaisedButton(
                onPressed: () {
                  notifications.sendTestNotification();
                },
                child: Text("Test Notification"),
              ),
              RaisedButton(
                onPressed: () {
                  ListWrapper l = ListWrapper();
                  l.value = [
                    0x00,
                    0x05,
                    0x07,
                    0xD1,
                    0x00,
                    0x00,
                    0x00,
                    0x05,
                    0x39
                  ];
                  connectionControl.sendRawPacket(l);
                },
                child: Text("Ping"),
              ),
              RaisedButton(
                onPressed: () {
                  connectionControl.disconnect();
                },
                child: Text("Disconnect"),
              ),
              RaisedButton(
                onPressed: () {
                  debug.collectLogs();
                },
                child: Text("Send logs"),
              ),
              Text(statusText),
              Card(
                margin: EdgeInsets.all(16.0),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(),
                      Text(
                        "Some debug options",
                        style: Theme.of(context).textTheme.headline5,
                      ),
                      SizedBox(height: 8.0),
                      FlatButton.icon(
                        label: Text("Open developer options"),
                        icon: Icon(RebbleIcons.developer_connection_console,
                            size: 25.0),
                        textColor: Theme.of(context).accentColor,
                        onPressed: () => context.push(DevOptionsPage()),
                      ),
                      FlatButton.icon(
                          label: Text("Here's another button"),
                          icon: Icon(RebbleIcons.settings, size: 25.0),
                          textColor: Theme.of(context).accentColor,
                          onPressed: () => {}),
                    ],
                  ),
                ),
              ),
              // TODO Separate call and notification mute is only possible on
              //  Android 7 (SDK 24) and newer. On older releases,
              //  we should only display one switch that controls both.
              Row(children: [
                Switch(
                  value: phoneNotificationsMuteEnabled.data?.value ?? false,
                  onChanged: (value) async {
                    await preferences.data?.value
                        ?.setPhoneNotificationMute(value);
                  },
                ),
                Text("Mute phone notification sounds when watch connected")
              ]),
              Row(children: [
                Switch(
                  value: phoneCallsMuteEnabled.data?.value ?? false,
                  onChanged: (value) async {
                    await preferences.data?.value?.setPhoneCallsMute(value);
                  },
                ),
                Text("Mute phone call ringing when watch connected")
              ]),
              Row(children: [
                Switch(
                  value: calendarSyncEnabled.data?.value ?? false,
                  onChanged: (value) async {
                    await preferences.data?.value
                        ?.setCalendarSyncEnabled(value);

                    if (!value) {
                      calendarControl.deleteCalendarPinsFromWatch();
                    }
                  },
                ),
                Text("Show calendar on the watch")
              ]),
              Text("Calendars: "),
              ...calendars.data?.value?.map((e) {
                    return Row(
                      children: [
                        Checkbox(
                          value: e.enabled,
                          onChanged: (enabled) {
                            calendarSelector.setCalendarEnabled(e.id, enabled);
                            calendarControl.requestCalendarSync();
                          },
                        ),
                        Text(e.name),
                      ],
                    );
                  })?.toList() ??
                  [],
            ],
          ),
        ),
      ),
    );
  }

  void showSyncError(BuildContext context, String errorMsg) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text("Sync error"),
              content: Text(errorMsg),
              actions: <Widget>[
                TextButton(
                  child: Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ));
  }
}
