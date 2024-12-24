import 'dart:convert'; // For JSON decoding, Base64 encoding/decoding
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

// 1. Import Geolocator
import 'package:geolocator/geolocator.dart';

// 2. Import Google Maps Flutter
import 'package:google_maps_flutter/google_maps_flutter.dart';

// 3. Import image_picker to handle taking photos from the camera
import 'package:image_picker/image_picker.dart';

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
        home: const TodoScreen(), // Directly set TodoScreen as the home
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

  final Uuid uuid = const Uuid(); // Initialize UUID generator

  String _searchString = ''; // State variable for search input

  final ScrollController _scrollController =
      ScrollController(); // ScrollController

  final TextEditingController _todoController =
      TextEditingController(); // Controller for the input TextField

  @override
  void initState() {
    super.initState();
    _refreshTodos();
  }

  @override
  void dispose() {
    _scrollController.dispose(); // Dispose the controller
    _todoController.dispose(); // Dispose the input controller
    super.dispose();
  }

  /// STEP A: Create a helper method to request location permissions
  /// and get the current location.
  Future<Position?> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      safePrint('Location services are disabled.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        safePrint('Location permission denied by the user.');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      safePrint('Location permission is permanently denied.');
      return null;
    }

    // If permission is granted, get the position
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return position;
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
        safePrint('No notes found.');
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

      safePrint('Notes refreshed and grouped successfully.');

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

  /// STEP B: Use the new _determinePosition() method to fetch location
  /// and store it in your Todo.
  Future<void> _submitTodo() async {
    String content = _todoController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note content cannot be empty.')),
      );
      return;
    }

    // 1. Get the device location (may be null if user denies permission)
    Position? position = await _determinePosition();

    // 2. Create a new Todo with location = lat/long if available
    final newTodo = Todo(
      id: uuid.v4(),
      content: content,
      isDone: false,
      verified: jsonEncode([]), // Initialize with an empty list
      location: position != null
          ? Location(
              lat: position.latitude,
              long: position.longitude,
            )
          : null,
      // Initialize the image as empty so we can populate later
      image: '',
    );

    // 3. Send the mutation to create the Todo
    final request = ModelMutations.create(newTodo);
    final response = await Amplify.API.mutate(request: request).response;

    if (response.hasErrors) {
      safePrint('Creating Note failed: ${response.errors}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add Note. Please try again.')),
      );
    } else {
      safePrint('Creating Note successful.');
      _todoController.clear(); // Clear the input field
      _refreshTodos(); // Refresh the Todo list
    }
  }

  /// Displays a dialog with THREE tabs: Verifiers tab, Location tab, Picture tab.
  Future<void> _showTodoDetailsModal(Todo todo) async {
    // We'll fetch verifiers here (same logic as before)
    List<Verifiers> verifiers = [];
    List<String> verifiedIds = [];

    // Parse the 'verified' JSON field to extract verifier IDs
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

    // Build the THREE-tab dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // We can use a Dialog with a fixed height, or let it size itself.
        return Dialog(
          child: DefaultTabController(
            length: 3, // 3 tabs now
            child: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  width: double.maxFinite,
                  height: 400, // Adjust as desired
                  child: Column(
                    children: [
                      // TabBar
                      Container(
                        color: Theme.of(context).primaryColor,
                        child: const TabBar(
                          labelColor: Colors.white,
                          indicatorColor: Colors.white,
                          tabs: [
                            Tab(text: 'Verifiers'),
                            Tab(text: 'Location'),
                            Tab(text: 'Picture'),
                          ],
                        ),
                      ),
                      // TabBarView
                      Expanded(
                        child: TabBarView(
                          children: [
                            // 1) Verifiers Tab
                            _buildVerifiersTab(
                              context: context,
                              todo: todo,
                              verifiers: verifiers,
                              verifiedIds: verifiedIds,
                              setState: setState,
                            ),

                            // 2) Location Tab
                            _buildLocationTab(todo),

                            // 3) Picture Tab
                            _buildPictureTab(todo, setState),
                          ],
                        ),
                      ),
                      // Close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Verifiers tab content
  Widget _buildVerifiersTab({
    required BuildContext context,
    required Todo todo,
    required List<Verifiers> verifiers,
    required List<String> verifiedIds,
    required void Function(void Function()) setState,
  }) {
    return verifiers.isEmpty
        ? const Center(child: Text('No verifiers available.'))
        : ListView.builder(
            shrinkWrap: true,
            itemCount: verifiers.length,
            itemBuilder: (context, index) {
              final verifier = verifiers[index];
              bool isVerified = verifiedIds.contains(verifier.id);
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(verifier.name ?? 'Unnamed Verifier'),
                trailing: isVerified
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          _showPasscodeDialog(todo, verifier, (bool success) {
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
          );
  }

  /// Location tab content: **displays a Google Map** with a marker pinned.
  Widget _buildLocationTab(Todo todo) {
    if (todo.location == null) {
      return const Center(child: Text('No location data available.'));
    }

    final double lat = todo.location!.lat ?? 0;
    final double long = todo.location!.long ?? 0;

    // Create a marker to show the Todo's location
    final marker = Marker(
      markerId: MarkerId(todo.id),
      position: LatLng(lat, long),
      infoWindow: const InfoWindow(title: 'Todo Location'),
    );

    // Return a GoogleMap widget
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        height: 300, // Adjust as desired
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(lat, long),
            zoom: 14,
          ),
          markers: {marker},
        ),
      ),
    );
  }

  /// Picture tab content: displays current image (if any) and a button to take a new photo.
  Widget _buildPictureTab(Todo todo, void Function(void Function()) setState) {
    final String? base64Image = todo.image;

    Widget imageWidget;
    if (base64Image != null && base64Image.isNotEmpty) {
      try {
        final decodedBytes = base64Decode(base64Image);
        imageWidget = Image.memory(decodedBytes, fit: BoxFit.cover);
      } catch (e) {
        imageWidget = const Text(
          'Error decoding image.',
          style: TextStyle(color: Colors.red),
        );
      }
    } else {
      imageWidget = const Text('No image available for this Todo.');
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(child: Center(child: imageWidget)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
              onPressed: () async {
                await _takePicture(todo);
                setState(() {}); // Refresh local widget state
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Uses the image_picker to capture a photo with the camera,
  /// then updates the Todo's `image` field with the base64 string.
  Future<void> _takePicture(Todo todo) async {
    final picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.camera);

    if (pickedFile == null) {
      safePrint('User canceled taking a photo.');
      return;
    }

    // Read the file as bytes
    final bytes = await pickedFile.readAsBytes();
    // Convert to Base64
    final base64String = base64Encode(bytes);

    // Create an updated copy of the Todo with the new image
    final updatedTodo = todo.copyWith(image: base64String);

    // Save the updated Todo
    final updateRequest = ModelMutations.update(updatedTodo);
    final updateResponse =
        await Amplify.API.mutate(request: updateRequest).response;

    if (updateResponse.hasErrors) {
      safePrint('Updating Note with image failed: ${updateResponse.errors}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Failed to save the image. Please try again. ${updateResponse.errors}')),
      );
    } else {
      safePrint('Note updated successfully with new image.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image saved successfully.')),
      );
      // Optionally refresh the entire list to show changes on main screen
      _refreshTodos();
    }
  }

  /// Displays a dialog to add a new Verifier
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
                  onPressed: () => Navigator.of(context).pop(),
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
      setState(() {});
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

  /// Displays a dialog to enter passcode for verification
  void _showPasscodeDialog(
      Todo todo, Verifiers verifier, Function(bool) onVerificationResult) {
    String enteredPasscode = '';

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
                  decoration:
                      const InputDecoration(hintText: '6-digit passcode'),
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
              ],
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
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

  /// Verifies the entered passcode against the verifier's passcode
  Future<void> _verifyPasscode(
      Todo todo,
      Verifiers verifier,
      String enteredPasscode,
      BuildContext dialogContext,
      Function(bool) onVerificationResult) async {
    if (enteredPasscode.trim().isEmpty) {
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

    // Correct passcode -> Add verifier ID to the 'verified' list
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
      safePrint('Updating Note failed: ${updateResponse.errors}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to verify Verifier. Please try again.')),
      );
    } else {
      safePrint('Note updated successfully.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifier verified successfully.')),
      );
      onVerificationResult(true);
      Navigator.of(dialogContext).pop(); // Close the passcode dialog
      _refreshTodos(); // Refresh the Todo list to reflect changes
    }
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

  /// Formats DateTime to 'HH:mm' format.
  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
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
                // Now it opens the 3-tab dialog
                _showTodoDetailsModal(todo);
              },
            )),
        const Divider(),
      ],
    );
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
      appBar: AppBar(
        title: SizedBox(
          height: 40,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search Notes',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchString = value;
                _filterTodos();
              });
            },
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: SignOutButton(), // Sign Out button on the right
          ),
        ],
        backgroundColor: Colors.blue, // Customize as needed
        elevation: 4.0,
      ),
      body: Column(
        children: [
          Expanded(
            child: displayGroupedTodos.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        "The list is empty.\nAdd some items by typing below.",
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
          // New Input Area
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: Colors.white,
            child: Row(
              children: [
                // Expanded TextField
                Expanded(
                  child: TextField(
                    controller: _todoController, // Assign the controller
                    decoration: const InputDecoration(
                      hintText: 'Enter a new Note',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      _submitTodo();
                    },
                  ),
                ),
                const SizedBox(width: 8.0),
                // Add Button
                ElevatedButton(
                  onPressed: _submitTodo,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14.0),
                  ),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
