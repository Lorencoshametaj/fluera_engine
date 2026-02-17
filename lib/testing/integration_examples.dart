import 'package:flutter/material.dart';
import './brush_testing.dart';

/// 🎨 Esempi di integrazione del Brush Testing Lab
///
/// Questo file mostra come integrare la schermata di test pennelli
/// in diversi contesti dell'app.

// =============================================================================
// EXAMPLE 1: Button in the Home
// =============================================================================

class HomeScreenExample extends StatelessWidget {
  const HomeScreenExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const BrushTestScreen()),
            );
          },
          icon: const Icon(Icons.brush),
          label: const Text('Test Pennelli'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ESEMPIO 2: Menu Debug/Developer
// =============================================================================

class DebugMenuExample extends StatelessWidget {
  const DebugMenuExample({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.brush),
          title: const Text('Brush Testing Lab'),
          subtitle: const Text('Testa tutti i pennelli disponibili'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const BrushTestScreen()),
            );
          },
        ),
        // Altri menu items...
      ],
    );
  }
}

// =============================================================================
// ESEMPIO 3: Floating Action Button
// =============================================================================

class CanvasScreenWithFAB extends StatelessWidget {
  const CanvasScreenWithFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canvas')),
      body: const Center(child: Text('Your Canvas Here')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BrushTestScreen()),
          );
        },
        icon: const Icon(Icons.science),
        label: const Text('Test Brushes'),
      ),
    );
  }
}

// =============================================================================
// ESEMPIO 4: Drawer Menu
// =============================================================================

class AppDrawerExample extends StatelessWidget {
  const AppDrawerExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Menu',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () => Navigator.pop(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brush),
            title: const Text('Brush Testing Lab'),
            subtitle: const Text('Test & comparazione pennelli'),
            onTap: () {
              Navigator.pop(context); // Chiudi drawer
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrushTestScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ESEMPIO 5: Named Route con routing avanzato
// =============================================================================

class AppRoutesExample {
  static const String brushTest = '/brush-test';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case brushTest:
        return MaterialPageRoute(builder: (context) => const BrushTestScreen());

      default:
        return MaterialPageRoute(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: Text('No route defined for ${settings.name}'),
                ),
              ),
        );
    }
  }
}

// Usa così nel main.dart:
// MaterialApp(
//   onGenerateRoute: AppRoutesExample.generateRoute,
// );
//
// E naviga così:
// Navigator.pushNamed(context, AppRoutesExample.brushTest);

// =============================================================================
// ESEMPIO 6: Dialog Popup
// =============================================================================

void showBrushTestDialog(BuildContext context) {
  showDialog(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('🎨 Brush Testing'),
          content: const Text(
            'Vuoi aprire il Brush Testing Lab per testare tutti i pennelli disponibili?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Chiudi dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BrushTestScreen(),
                  ),
                );
              },
              child: const Text('Apri'),
            ),
          ],
        ),
  );
}

// =============================================================================
// ESEMPIO 7: Bottom Sheet
// =============================================================================

void showBrushTestBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder:
        (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.brush, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Brush Testing Lab',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Testa e confronta tutti i pennelli professionali',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Chiudi bottom sheet
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BrushTestScreen(),
                    ),
                  );
                },
                child: const Text('Apri Testing Lab'),
              ),
            ],
          ),
        ),
  );
}

// =============================================================================
// ESEMPIO 8: Gesture - Long Press
// =============================================================================

class LongPressExample extends StatelessWidget {
  const LongPressExample({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BrushTestScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush, color: Colors.white),
            SizedBox(height: 8),
            Text('Long Press per Test', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ESEMPIO 9: Settings/Preferenze
// =============================================================================

class SettingsScreenExample extends StatelessWidget {
  const SettingsScreenExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setzioni')),
      body: ListView(
        children: [
          const ListTile(title: Text('Generali'), dense: true),

          // ... altre opzioni ...
          const Divider(),
          const ListTile(title: Text('Developer'), dense: true),
          ListTile(
            leading: const Icon(Icons.science),
            title: const Text('Brush Testing Lab'),
            subtitle: const Text('Strumenti di testing per sviluppatori'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrushTestScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
