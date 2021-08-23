import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:http/http.dart' as http;

const EVENTS_KEY = "fetch_events";

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// This "Headless Task" is run when app is terminated.
void backgroundFetchHeadlessTask(HeadlessTask task) async {
  var taskId = task.taskId;
  var timeout = task.timeout;
  if (timeout) {
    print("[BackgroundFetch] Headless task timed-out: $taskId");
    BackgroundFetch.finish(taskId);
    return;
  }

  print("[BackgroundFetch] Headless event received: $taskId");

  var timestamp = DateTime.now();

  var prefs = await SharedPreferences.getInstance();

  // Read fetch_events from SharedPreferences
  var events = <String>[];
  var json = prefs.getString(EVENTS_KEY);
  if (json != null) {
    events = jsonDecode(json).cast<String>();
  }
  // Add new event.
  events.insert(0, "$taskId@$timestamp [Headless]");
  // Persist fetch events in SharedPreferences
  prefs.setString(EVENTS_KEY, jsonEncode(events));

  if (taskId == 'flutter_background_fetch') {
    /* DISABLED:  uncomment to fire a scheduleTask in headlessTask.
    BackgroundFetch.scheduleTask(TaskConfig(
        taskId: "com.transistorsoft.customtask",
        delay: 5000,
        periodic: false,
        forceAlarmManager: false,
        stopOnTerminate: false,
        enableHeadless: true˝
    ));
     */
  }
  BackgroundFetch.finish(taskId);
}

void main() {
  // Enable integration testing with the Flutter Driver extension.
  // See https://flutter.io/testing/ for more info.
  runApp(MyApp());

  // Register to receive BackgroundFetch events after app is terminated.
  // Requires {stopOnTerminate: false, enableHeadless: true}
  BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _enabled = true;
  int _status = 0;
  List<String> _events = [];

  @override
  void initState() {
    super.initState();
    initNotification();
    initPlatformState();
  }

  Future<void> initNotification() async {
    var flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    // initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
    const initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    final initializationSettingsIOS = IOSInitializationSettings();
    final initializationSettingsMacOS = MacOSInitializationSettings();
    final initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
        macOS: initializationSettingsMacOS);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onSelectNotification: selectNotification);
  }

  void _requestPermissions() {
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> _showNotification(String text) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
            'your channel id', 'your channel name', 'your channel description',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: false);
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
        0, 'plain title', text, platformChannelSpecifics);
  }

  Future selectNotification(String payload) async {
    if (payload != null) {
      debugPrint('notification payload: $payload');
    }
    print('clicked');
    // await Navigator.push(
    //   context,
    //   MaterialPageRoute<void>(builder: (context) => SecondScreen(payload)),
    // );
  }

  Future<http.Response> fetchAlbum() {
    return http.get(Uri.parse('https://www.google.com/'));
  }

  Future<void> fetchAlbumAndNotify() async {
    _showNotification((await fetchAlbum()).statusCode?.toString());
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // Load persisted fetch events from SharedPreferences
    var prefs = await SharedPreferences.getInstance();
    var json = prefs.getString(EVENTS_KEY);
    if (json != null) {
      setState(() {
        _events = jsonDecode(json).cast<String>();
      });
    }

    // Configure BackgroundFetch.
    try {
      var status = await BackgroundFetch.configure(
          BackgroundFetchConfig(
            minimumFetchInterval: 15,
            forceAlarmManager: false,
            stopOnTerminate: false,
            startOnBoot: true,
            enableHeadless: true,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresStorageNotLow: false,
            requiresDeviceIdle: false,
            requiredNetworkType: NetworkType.ANY,
          ),
          _onBackgroundFetch,
          _onBackgroundFetchTimeout);
      print('[BackgroundFetch] configure success: $status');
      _showNotification('fetconfigure successch');
      setState(() {
        _status = status;
      });

      // Schedule a "one-shot" custom-task in 10000ms.
      // These are fairly reliable on Android (particularly with forceAlarmManager) but not iOS,
      // where device must be powered (and delay will be throttled by the OS).
      BackgroundFetch.scheduleTask(TaskConfig(
          taskId: "com.transistorsoft.customtask",
          delay: 10000,
          periodic: false,
          forceAlarmManager: true,
          stopOnTerminate: false,
          enableHeadless: true));
    } catch (e) {
      print("[BackgroundFetch] configure ERROR: $e");
      setState(() {
        _status = e;
      });
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
  }

  void _onBackgroundFetch(String taskId) async {
    var prefs = await SharedPreferences.getInstance();
    var timestamp = new DateTime.now();
    // This is the fetch-event callback.
    print("[BackgroundFetch] Event received: $taskId");

    setState(() {
      _events.insert(0, "$taskId@${timestamp.toString()}");
    });
    // Persist fetch events in SharedPreferences
    prefs.setString(EVENTS_KEY, jsonEncode(_events));
    var response = await fetchAlbum();

    if (taskId == "flutter_background_fetch") {
      _showNotification('background_check' + response.statusCode?.toString());
      // Schedule a one-shot task when fetch event received (for testing).
      /*
      BackgroundFetch.scheduleTask(TaskConfig(
          taskId: "com.transistorsoft.customtask",
          delay: 5000,
          periodic: false,
          forceAlarmManager: true,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresNetworkConnectivity: true,
          requiresCharging: true
      ));
       */
    } else {
      _showNotification('fetch' + response.statusCode?.toString());
    }
    // IMPORTANT:  You must signal completion of your fetch task or the OS can punish your app
    // for taking too long in the background.
    BackgroundFetch.finish(taskId);
  }

  /// This event fires shortly before your task is about to timeout.  You must finish any outstanding work and call BackgroundFetch.finish(taskId).
  void _onBackgroundFetchTimeout(String taskId) {
    print("[BackgroundFetch] TIMEOUT: $taskId");
    BackgroundFetch.finish(taskId);
  }

  void _onClickEnable(enabled) {
    setState(() {
      _enabled = enabled;
    });
    if (enabled) {
      BackgroundFetch.start().then((int status) {
        print('[BackgroundFetch] start success: $status');
      }).catchError((e) {
        print('[BackgroundFetch] start FAILURE: $e');
      });
    } else {
      BackgroundFetch.stop().then((int status) {
        print('[BackgroundFetch] stop success: $status');
      });
    }
  }

  void _onClickStatus() async {
    var status = await BackgroundFetch.status;
    print('[BackgroundFetch] status: $status');
    setState(() {
      _status = status;
    });
  }

  void _onClickClear() async {
    var prefs = await SharedPreferences.getInstance();
    prefs.remove(EVENTS_KEY);
    setState(() {
      _events = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    const EMPTY_TEXT = Center(
        child: Text(
            'Waiting for fetch events.  Simulate one.\n [Android] \$ ./scripts/simulate-fetch\n [iOS] XCode->Debug->Simulate Background Fetch'));

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
            title: const Text('BackgroundFetch Example',
                style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.amberAccent,
            brightness: Brightness.light,
            actions: <Widget>[
              Switch(value: _enabled, onChanged: _onClickEnable),
            ]),
        body: (_events.isEmpty)
            ? EMPTY_TEXT
            : Container(
                child: ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (BuildContext context, int index) {
                      var event = _events[index].split("@");
                      return InputDecorator(
                          decoration: InputDecoration(
                              contentPadding: EdgeInsets.only(
                                  left: 5.0, top: 5.0, bottom: 5.0),
                              labelStyle:
                                  TextStyle(color: Colors.blue, fontSize: 20.0),
                              labelText: "[${event[0].toString()}]"),
                          child: Text(event[1],
                              style: TextStyle(
                                  color: Colors.black, fontSize: 16.0)));
                    }),
              ),
        bottomNavigationBar: BottomAppBar(
            child: Container(
                padding: EdgeInsets.only(left: 5.0, right: 5.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      RaisedButton(
                          onPressed: _onClickStatus,
                          child: Text('Status: $_status')),
                      RaisedButton(
                          onPressed: _onClickClear, child: Text('Clear')),
                      RaisedButton(
                          onPressed: _requestPermissions,
                          child: Text('Permission')),
                      RaisedButton(
                        onPressed: fetchAlbumAndNotify,
                        child: Text('fetch'),
                      )
                    ]))),
      ),
    );
  }
}
