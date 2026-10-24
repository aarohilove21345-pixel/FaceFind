import 'package:flutter/material.dart';

import '../services/facefind_api.dart';
import '../services/history_store.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    HistoryStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    HistoryStore.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Future<Map<String, dynamic>> _load() async {
    if (!FaceFindApi.isConfigured) {
      throw ApiException('The app is not configured: backend URL is missing.');
    }
    final FaceFindApi api = FaceFindApi();
    try {
      return await api.getUsage();
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _message(
            icon: Icons.error_outline,
            title: 'Could not load credits',
            text: '${snap.error}',
            color: Colors.redAccent,
          );
        }
        final Map<String, dynamic> data = snap.data ?? {};
        final int limit = (data['daily_limit'] as num?)?.toInt() ?? 0;
        final int left = (data['remaining_today'] as num?)?.toInt() ?? 0;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.storage, size: 48, color: Color(0xFF0A84FF)),
            const SizedBox(height: 8),
            const Center(
              child: Text('Credits',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: Column(
                children: [
                  Text('$left',
                      style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A84FF))),
                  Text('of $limit searches left today',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'FaceFind uses a free search service with a limited monthly '
              'allowance, so the number of searches is capped each day. '
              'The limit resets every day.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        );
      },
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
