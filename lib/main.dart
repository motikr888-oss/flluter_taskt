import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNotifications();
  runApp(const VoiceTaskApp());
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final FlutterTts flutterTts = FlutterTts();
Database? taskDatabase;

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('app_icon');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: onNotificationTapped,
  );

  await flutterTts.setLanguage("en-US");
}

void onNotificationTapped(NotificationResponse response) {}

Future<Database> initDatabase() async {
  final String path = join(await getDatabasesPath(), 'voice_tasks.db');
  return openDatabase(
    path,
    onCreate: (db, version) {
      return db.execute(
        'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, date TEXT, time TEXT, isDone INTEGER DEFAULT 0)',
      );
    },
    version: 1,
  );
}

class VoiceTaskApp extends StatelessWidget {
  const VoiceTaskApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceTask',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const VoiceTaskHome(),
    );
  }
}

class VoiceTaskHome extends StatefulWidget {
  const VoiceTaskHome({Key? key}) : super(key: key);

  @override
  State<VoiceTaskHome> createState() => _VoiceTaskHomeState();
}

class _VoiceTaskHomeState extends State<VoiceTaskHome> {
  List<Map<String, dynamic>> tasks = [];
  Timer? reminderTimer;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    taskDatabase = await initDatabase();
    await _loadTasks();
    _startReminderTimer();
  }

  Future<void> _loadTasks() async {
    final List<Map<String, dynamic>> allTasks =
        await taskDatabase!.query('tasks');
    setState(() {
      tasks = allTasks;
    });
  }

  void _startReminderTimer() {
    reminderTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      final now = DateTime.now();
      for (var task in tasks) {
        if (task['isDone'] == 0) {
          final taskDate = task['date'];
          final taskTime = task['time'];
          final taskDateTime = DateTime.parse('$taskDate $taskTime');

          if (now.isAfter(taskDateTime) &&
              now.difference(taskDateTime).inSeconds < 5) {
            _showNotificationAndSpeak(task['title']);
          }
        }
      }
    });
  }

  Future<void> _showNotificationAndSpeak(String title) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'voice_task_channel',
      'Voice Task Reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Task Reminder',
      title,
      platformChannelSpecifics,
    );

    for (int i = 0; i < 3; i++) {
      await flutterTts.speak(title);
      await Future.delayed(Duration(seconds: 4));
    }
  }

  Future<void> _addTask(String title, String date, String time) async {
    await taskDatabase!.insert(
      'tasks',
      {'title': title, 'date': date, 'time': time, 'isDone': 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _loadTasks();
  }

  Future<void> _markTaskDone(int id) async {
    await taskDatabase!.update(
      'tasks',
      {'isDone': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTasks();
  }

  Future<void> _deleteTask(int id) async {
    await taskDatabase!.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _loadTasks();
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add New Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration:
                          const InputDecoration(hintText: 'Enter task title'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                      child: Text(
                          'Date: ${selectedDate.year}-${selectedDate.month}-${selectedDate.day}'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                      child: Text(
                          'Time: ${selectedTime.hour}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      _addTask(
                        titleController.text,
                        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00',
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    reminderTimer?.cancel();
    taskDatabase?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceTask'),
      ),
      body: tasks.isEmpty
          ? const Center(child: Text('No tasks. Add one to get started!'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  leading: Checkbox(
                    value: task['isDone'] == 1,
                    onChanged: (value) {
                      if (value!) {
                        _markTaskDone(task['id']);
                      }
                    },
                  ),
                  title: Text(task['title']),
                  subtitle: Text('${task['date']} at ${task['time']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteTask(task['id']),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
