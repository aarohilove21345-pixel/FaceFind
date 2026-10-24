import 'package:flutter/material.dart';

import '../services/history_store.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _clearHistory(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
            'All saved scans on this phone will be deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await HistoryStore.clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared.')),
      );
    }
  }

  Widget _section(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.person, size: 56, color: Color(0xFF0A84FF)),
        const SizedBox(height: 8),
        const Center(
          child: Text('FaceFind',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text('FaceFind Version 1.0.0',
              style: TextStyle(color: Colors.white54)),
        ),
        const SizedBox(height: 24),
        _section(
          'How it works',
          'Select a photo and FaceFind searches the web for pages where the '
              'photo or similar photos appear. Results are web pages, not '
              'confirmed identities.',
        ),
        _section(
          'Your photo',
          'The photo you select is sent to our server and to an external '
              'image-search service. It is kept only for a few minutes while '
              'the search runs and is deleted right after.',
        ),
        _section(
          'Responsible use',
          'Only upload photos of yourself or of people who have given you '
              'permission. Matches may be wrong and are not proof of identity.',
        ),
        _section(
          'Saved history',
          'Your last scans are saved on this phone only. You can delete them '
              'at any time.',
        ),
        OutlinedButton.icon(
          onPressed: () => _clearHistory(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear history'),
        ),
      ],
    );
  }
}
