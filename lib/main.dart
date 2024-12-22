import 'dart:convert'; // For JSON decoding
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For input formatters
import 'package:my_amplify_app/models/ModelProvider.dart';
import 'package:my_amplify_app/models/Verifiers.dart'; // Import the Verifiers model
import 'package:my_amplify_app/models/Todo.dart'; // Import the Todo model
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
      verified: jsonEncode([]), // Initialize with an empty list
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
              trailing: IconButton(
                icon: const Icon(Icons.visibility),
                onPressed: () {
                  _showVerifiersModal(todo);
                },
                tooltip: 'View Verifiers',
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

  /// Fetches and displays verifiers associated with a Todo in a modal.
  Future<void> _showVerifiersModal(Todo todo) async {
    List<Verifiers> verifiers = [];
    List<String> verifiedIds = [];

    // Parse the 'verified' JSON field to extract verifier IDs
    if (todo.verified != null && todo.verified!.isNotEmpty) {
      try {
        // Assuming 'verified' is a JSON-encoded list of verifier IDs
        verifiedIds =
            List<String>.from(jsonDecode(todo.verified!) as List<dynamic>);
      } catch (e) {
        safePrint('Error parsing verified JSON: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to parse verified data.')),
        );
        return;
      }
    }

    // Fetch Verifier objects
    try {
      final request = ModelQueries.list(Verifiers.classType);
      final response = await Amplify.API.query(request: request).response;

      if (response.hasErrors) {
        safePrint('Errors: ${response.errors}');
        // Handle errors appropriately in your app
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch Verifiers.')),
        );
        return;
      }

      final allVerifiers = response.data?.items;
      if (allVerifiers != null) {
        verifiers = allVerifiers
            .whereType<Verifiers>() // Filters out any nulls
            .toList();
      }
    } catch (e) {
      safePrint('Exception fetching Verifiers: $e');
      // Handle exceptions appropriately in your app
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('An error occurred while fetching Verifiers.')),
      );
      return;
    }

    // Display the verifiers in a modal
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Use StatefulBuilder to manage state within the dialog
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Verifiers'),
              content: verifiers.isEmpty
                  ? const Text('No verifiers available.')
                  : SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: verifiers.length,
                        itemBuilder: (context, index) {
                          final verifier = verifiers[index];
                          bool isVerified = verifiedIds.contains(verifier.id);
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(verifier.name ?? 'Unnamed Verifier'),
                            trailing: isVerified
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    onPressed: () {
                                      _showPasscodeDialog(todo, verifier,
                                          (bool success) {
                                        if (success) {
                                          setState(() {
                                            verifiedIds.add(verifier.id);
                                          });
                                        }
                                      });
                                    },
                                    tooltip: 'Verify Verifier',
                                  ),
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  child: const Text('Create New Verifier'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the current dialog
                    _showAddVerifierDialog(
                        todo); // Open the Add Verifier dialog
                  },
                ),
                TextButton(
                  child: const Text('Close'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Displays a dialog to add a new Verifier.
  void _showAddVerifierDialog(Todo todo) {
    String verifierName = '';
    String verifierPasscode = '';
    String? passcodeError;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Use StatefulBuilder to manage state within the dialog
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add New Verifier'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'Enter verifier name',
                      ),
                      onChanged: (value) {
                        verifierName = value;
                      },
                    ),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Passcode',
                        hintText: 'Enter 6-digit passcode',
                        errorText: passcodeError,
                      ),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (value) {
                        verifierPasscode = value;
                      },
                      onSubmitted: (value) async {
                        if (_validatePasscode(value, setState)) {
                          Navigator.of(context).pop();
                          await _addVerifier(
                              todo, verifierName, verifierPasscode);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                ElevatedButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    if (_validatePasscode(verifierPasscode, setState)) {
                      Navigator.of(context).pop();
                      await _addVerifier(todo, verifierName, verifierPasscode);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Validates that the passcode is a 6-digit integer.
  bool _validatePasscode(
      String passcode, void Function(void Function()) setState) {
    if (passcode.isEmpty) {
      setState(() {
        // Update the error message
        // Assuming passcodeError is defined in the calling context
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode cannot be empty.')),
      );
      return false;
    }

    if (passcode.length != 6) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be exactly 6 digits.')),
      );
      return false;
    }

    return true;
  }

  /// Adds a new Verifier and optionally associates it with the given Todo.
  Future<void> _addVerifier(Todo todo, String name, String passcode) async {
    if (name.trim().isEmpty || passcode.trim().isEmpty) {
      // Show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and passcode cannot be empty.')),
      );
      return;
    }

    int passcodeInt;
    try {
      passcodeInt = int.parse(passcode);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be a number.')),
      );
      return;
    }

    // Ensure passcode is exactly 6 digits
    if (passcodeInt < 100000 || passcodeInt > 999999) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be a 6-digit number.')),
      );
      return;
    }

    final newVerifier = Verifiers(
      id: uuid.v4(),
      name: name.trim(),
      passcode: passcodeInt,
    );

    // Create the Verifier in the API
    final createRequest = ModelMutations.create(newVerifier);
    final createResponse =
        await Amplify.API.mutate(request: createRequest).response;

    if (createResponse.hasErrors) {
      safePrint('Creating Verifier failed: ${createResponse.errors}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to add Verifier. Please try again.')),
      );
      return;
    } else {
      safePrint('Creating Verifier successful.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifier added successfully.')),
      );
      _refreshTodos();
    }
  }

  /// Displays a dialog to enter passcode for verification.
  void _showPasscodeDialog(
      Todo todo, Verifiers verifier, Function(bool) onVerificationResult) {
    String enteredPasscode = '';
    bool isError = false;
    String? passcodeError;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Enter Passcode'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '6-digit passcode',
                    errorText: passcodeError,
                  ),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (value) {
                    enteredPasscode = value;
                  },
                  onSubmitted: (value) {
                    _verifyPasscode(todo, verifier, enteredPasscode, context,
                        onVerificationResult);
                  },
                ),
                if (isError)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Incorrect passcode. Please try again.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                child: const Text('Verify'),
                onPressed: () {
                  _verifyPasscode(todo, verifier, enteredPasscode, context,
                      onVerificationResult);
                },
              ),
            ],
          );
        });
      },
    );
  }

  /// Verifies the entered passcode against the verifier's passcode.
  Future<void> _verifyPasscode(
      Todo todo,
      Verifiers verifier,
      String enteredPasscode,
      BuildContext dialogContext,
      Function(bool) onVerificationResult) async {
    if (enteredPasscode.trim().isEmpty) {
      // Show error within the dialog
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode cannot be empty.')),
      );
      return;
    }

    if (enteredPasscode.length != 6) {
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be exactly 6 digits.')),
      );
      return;
    }

    int enteredPasscodeInt;
    try {
      enteredPasscodeInt = int.parse(enteredPasscode);
    } catch (e) {
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode must be a number.')),
      );
      return;
    }

    if (enteredPasscodeInt != verifier.passcode) {
      // Incorrect passcode
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect passcode. Please try again.')),
      );
      return;
    }

    // Correct passcode
    // Add verifier ID to the 'verified' list
    List<String> verifiedIds = [];
    if (todo.verified != null && todo.verified!.isNotEmpty) {
      try {
        verifiedIds =
            List<String>.from(jsonDecode(todo.verified!) as List<dynamic>);
      } catch (e) {
        safePrint('Error parsing verified JSON: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to parse verified data.')),
        );
        return;
      }
    }

    if (!verifiedIds.contains(verifier.id)) {
      verifiedIds.add(verifier.id);
    }

    // Update the Todo's 'verified' field
    Todo updatedTodo = todo.copyWith(
      verified: jsonEncode(verifiedIds),
    );

    final updateRequest = ModelMutations.update(updatedTodo);
    final updateResponse =
        await Amplify.API.mutate(request: updateRequest).response;

    if (updateResponse.hasErrors) {
      safePrint('Updating Todo failed: ${updateResponse.errors}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to verify Verifier. Please try again.')),
      );
    } else {
      safePrint('Todo updated successfully.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifier verified successfully.')),
      );
      onVerificationResult(true);
      Navigator.of(dialogContext).pop(); // Close the passcode dialog
      _refreshTodos(); // Refresh the Todo list to reflect changes
    }
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
