import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceTaskApp());
}

final FlutterTts flutterTts = FlutterTts();
Database? taskDatabase;

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

Future<void> initializeTts() async {
  await flutterTts.setLanguage("hi-IN");
  await flutterTts.setSpeechRate(0.5);
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
    await initializeTts();
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
      final currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      for (var task in tasks) {
        if (task['isDone'] == 0) {
          final taskTime = task['time'].substring(0, 5);

          if (currentTime == taskTime) {
            _playVoiceReminder(task['title']);
          }
        }
      }
    });
  }

  Future<void> _playVoiceReminder(String title) async {
    String message = 'Yaad raha! $title karna hai!';

    await flutterTts.speak(message);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 10),
      ),
    );
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
              title: const Text('Naya Task Add Karo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'Task likho',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
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
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                          'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setState(() => selectedTime = picked);
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(
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
        centerTitle: true,
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.task_alt, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text('Koi task nahi! Add karo!'),
                ],
              ),
            )
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
                  subtitle: Text(
                    '${task['date']} - ${task['time'].substring(0, 5)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
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
