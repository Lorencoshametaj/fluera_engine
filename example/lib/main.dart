import 'package:flutter/material.dart';
import 'package:nebula_engine/nebula_engine.dart';

void main() {
  runApp(const NebulaEngineDemo());
}

class NebulaEngineDemo extends StatelessWidget {
  const NebulaEngineDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nebula Engine Demo',
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
    return NebulaCanvasScreen(
      config: NebulaCanvasConfig(layerController: _layerController),
    );
  }
}
