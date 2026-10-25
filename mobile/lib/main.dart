import 'package:flutter/material.dart';

import 'ad_manager.dart';
import 'nav.dart';
import 'screens/credits_page.dart';
import 'screens/history_page.dart';
import 'screens/home_page.dart';
import 'screens/profile_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FaceFindApp());
  Future.delayed(const Duration(seconds: 2), () {
    AdManager.instance.initialize().catchError((_) {});
  });
}

class FaceFindApp extends StatelessWidget {
  const FaceFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceFind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0A84FF),
          onPrimary: Colors.white,
          secondary: Color(0xFF00C6FB),
        ),
        cardColor: const Color(0xFF121212),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    tabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final int? i = tabRequest.value;
    if (i != null && mounted) {
      setState(() => _index = i);
      tabRequest.value = null;
    }
  }

  static const List<Widget> _pages = [
    HomePage(),
    HistoryPage(),
    CreditsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdManager.instance.bannerSlot(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.storage_outlined),
                selectedIcon: Icon(Icons.storage),
                label: 'Credits',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
