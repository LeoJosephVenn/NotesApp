import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';

import 'package:flutter/material.dart';
import 'package:my_amplify_app/models/ModelProvider.dart';
import 'package:intl/intl.dart'; // For date and time formatting
import 'package:uuid/uuid.dart'; // For generating unique IDs

import 'amplify_outputs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _configureAmplify();
    runApp(const MyApp());
  } on AmplifyException catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Error configuring Amplify: ${e.message}"),
        ),
      ),
    ));
  }
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins(
      [
        AmplifyAuthCognito(),
        AmplifyAPI(
          options: APIPluginOptions(
            modelProvider: ModelProvider.instance,
          ),
        ),
      ],
    );
    await Amplify.configure(amplifyConfig);
    safePrint('Successfully configured Amplify');
  } on Exception catch (e) {
    safePrint('Error configuring Amplify: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: Authenticator.builder(),
        home: const SafeArea(
          child: Scaffold(
            body: Column(
              children: [
                SignOutButton(),
                Expanded(child: TodoScreen()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  // Map to hold grouped todos. Key: formatted date string, Value: List of Todos
  Map<String, List<Todo>> _groupedTodos = {};

  // Map to hold filtered grouped todos based on search
  Map<String, List<Todo>> _filteredGroupedTodos = {};

  final Uuid uuid = Uuid(); // Initialize UUID generator

  String _searchString = ''; // State variable for search input

  final ScrollController _scrollController =
      ScrollController(); // ScrollController

  @override
  void initState() {
    super.initState();
    _refreshTodos();
  }

  @override
  void dispose() {
    _scrollController.dispose(); // Dispose the controller
    super.dispose();
  }

  /// Fetches todos from the API, groups them by creation date, and updates the state.
  Future<void> _refreshTodos() async {
    try {
      final request = ModelQueries.list(Todo.classType);
      final response = await Amplify.API.query(request: request).response;

      if (response.hasErrors) {
        safePrint('Errors: ${response.errors}');
        return;
      }

      final todos = response.data?.items;
      if (todos == null || todos.isEmpty) {
        safePrint('No todos found.');
        setState(() {
          _groupedTodos = {};
          _filteredGroupedTodos = {};
        });
        return;
      }

      // Sort todos by creation date ascending
      todos.sort((a, b) {
        final aCreatedAt = a?.createdAt;
        final bCreatedAt = b?.createdAt;
        if (aCreatedAt == null || bCreatedAt == null) {
          return 0;
        }
        return aCreatedAt.compareTo(bCreatedAt);
      });

      // Group todos by day using local time
      Map<String, List<Todo>> grouped = {};
      for (var todo in todos) {
        if (todo?.createdAt != null) {
          // Convert to local time for correct grouping
          String dateKey =
              _formatDate(todo!.createdAt!.getDateTimeInUtc().toLocal());
          if (grouped.containsKey(dateKey)) {
            grouped[dateKey]!.add(todo);
          } else {
            grouped[dateKey] = [todo];
          }
        }
      }

      setState(() {
        _groupedTodos = grouped;
      });

      _filterTodos(); // Apply initial filter

      safePrint('Todos refreshed and grouped successfully.');

      _scrollToBottom(); // Scroll to bottom after refreshing todos
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
  }

  /// Filters the grouped todos based on the search string.
  void _filterTodos() {
    if (_searchString.isEmpty) {
      setState(() {
        _filteredGroupedTodos = Map.from(_groupedTodos);
      });
      _scrollToBottom(); // Scroll to bottom after filtering
      return;
    }

    Map<String, List<Todo>> filtered = {};

    _groupedTodos.forEach((date, todos) {
      List<Todo> matchingTodos = todos
          .where((todo) =>
              todo.content != null &&
              todo.content!.toLowerCase().contains(_searchString.toLowerCase()))
          .toList();
      if (matchingTodos.isNotEmpty) {
        filtered[date] = matchingTodos;
      }
    });

    setState(() {
      _filteredGroupedTodos = filtered;
    });

    _scrollToBottom(); // Scroll to bottom after filtering
  }

  /// Adds a new Todo to the API and refreshes the list upon success.
  Future<void> _addTodo(String content) async {
    if (content.trim().isEmpty) {
      // Show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todo content cannot be empty.')),
      );
      return;
    }

    final newTodo = Todo(
      id: uuid.v4(),
      content: content.trim(),
      isDone: false,
      // Assuming 'createdAt' is auto-managed by Amplify; if not, uncomment the next line
      // createdAt: DateTime.now().toUtc(),
    );

    final request = ModelMutations.create(newTodo);
    final response = await Amplify.API.mutate(request: request).response;

    if (response.hasErrors) {
      safePrint('Creating Todo failed: ${response.errors}');
      // Show an error message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add Todo. Please try again.')),
      );
    } else {
      safePrint('Creating Todo successful.');
      _refreshTodos();
    }
  }

  /// Displays a dialog to add a new Todo.
  void _showAddTodoDialog() {
    String todoContent = '';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Todo'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter todo content',
            ),
            onChanged: (value) {
              todoContent = value;
            },
            onSubmitted: (value) {
              Navigator.of(context).pop();
              _addTodo(value);
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                Navigator.of(context).pop();
                _addTodo(todoContent);
              },
            ),
          ],
        );
      },
    );
  }

  /// Formats a DateTime object to a 'YYYY-MM-DD' string for grouping.
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Formats the date key back to a more readable format for display.
  String _formatDisplayDate(String dateKey) {
    try {
      DateTime date = DateTime.parse(dateKey);
      return DateFormat('MMMM d, yyyy').format(date);
    } catch (e) {
      safePrint('Error parsing dateKey: $e');
      return dateKey; // Fallback to the original string if parsing fails
    }
  }

  /// Builds the UI for each date group.
  Widget _buildDateGroup(String date, List<Todo> todos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            _formatDisplayDate(date),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // List of Todos for this date
        ...todos.map((todo) => ListTile(
              leading: Text(
                _formatTime(todo.createdAt!.getDateTimeInUtc().toLocal()),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              title: Text(
                todo.content ?? '',
                style: const TextStyle(fontSize: 16),
              ),
              onTap: () {
                // Optionally, handle tap events
              },
            )),
        const Divider(),
      ],
    );
  }

  /// Formats DateTime to 'HH:mm' format.
  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  /// Scrolls the ListView to the bottom.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine which grouped todos to display based on search
    Map<String, List<Todo>> displayGroupedTodos =
        _searchString.isEmpty ? _groupedTodos : _filteredGroupedTodos;

    // Get a sorted list of dates in ascending order (earliest first)
    List<String> sortedDates = displayGroupedTodos.keys.toList()
      ..sort((a, b) => a.compareTo(b));

    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Truth Notes'),
      //   // Removed the search field from the AppBar
      // ),
      // Removed the previous AppBar bottom containing the search field
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(
                bottom: 80.0), // Space for the bottom controls
            child: displayGroupedTodos.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "The list is empty.\nAdd some items by clicking the add button below.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController, // Assign the controller
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      String date = sortedDates[index];
                      List<Todo> todos = displayGroupedTodos[date]!;
                      return _buildDateGroup(date, todos);
                    },
                  ),
          ),
          // Positioned at the bottom: Search field and Add button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  // Expanded search field
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search Todos',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchString = value;
                          _filterTodos();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // Add Todo button
                  FloatingActionButton.extended(
                    label: const Text('Note'),
                    icon: const Icon(Icons.add),
                    onPressed: _showAddTodoDialog,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
