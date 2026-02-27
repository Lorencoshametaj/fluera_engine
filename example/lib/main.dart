import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluera_engine/fluera_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SQLite storage is only available on native platforms.
  // On web, the canvas runs without persistence (in-memory only).
  SqliteStorageAdapter? storage;
  if (!kIsWeb) {
    storage = SqliteStorageAdapter();
    await storage.initialize();
  }

  runApp(FlueraEngineDemo(storage: storage));
}

class FlueraEngineDemo extends StatelessWidget {
  final SqliteStorageAdapter? storage;
  const FlueraEngineDemo({super.key, this.storage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluera Engine Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CanvasDemoPage(),
    );
  }
}

class CanvasDemoPage extends StatefulWidget {
  const CanvasDemoPage({super.key});

  @override
  State<CanvasDemoPage> createState() => _CanvasDemoPageState();
}

class _CanvasDemoPageState extends State<CanvasDemoPage> {
  late final LayerController _layerController;

  @override
  void initState() {
    super.initState();
    _layerController = LayerController();
  }

  @override
  void dispose() {
    _layerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final demo = context.findAncestorWidgetOfExactType<FlueraEngineDemo>();
    return FlueraCanvasScreen(
      config: FlueraCanvasConfig(
        layerController: _layerController,
        // Storage is null on web — canvas runs in-memory
        storageAdapter: demo?.storage,
      ),
    );
  }
}
