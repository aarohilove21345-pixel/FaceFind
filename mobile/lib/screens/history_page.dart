import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ad_manager.dart';
import '../models/scan_result.dart';
import '../services/history_store.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  static String _when(DateTime t) {
    const List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year}, $h:$m';
  }

  Future<void> _open(BuildContext context, String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    AdManager.instance.skipNextAppOpen();
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryStore.changes,
      builder: (context, version, child) {
        return FutureBuilder<List<HistoryEntry>>(
          key: ValueKey<int>(version),
          future: HistoryStore.load(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<HistoryEntry> entries = snap.data ?? [];
            if (entries.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: Color(0xFF0A84FF)),
                      SizedBox(height: 12),
                      Text('No scans yet',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8),
                      Text(
                        'Your last scans are saved on this phone only and will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Scan History',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Saved on this phone only.',
                    style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 12),
                for (final HistoryEntry e in entries) _entry(context, e),
              ],
            );
          },
        );
      },
    );
  }

  Widget _entry(BuildContext context, HistoryEntry e) {
    final int n = e.matches.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.history, color: Color(0xFF0A84FF)),
          title: Text(_when(e.time)),
          subtitle: Text(
            n == 0 ? 'No matches' : '$n page${n == 1 ? '' : 's'} found',
            style: const TextStyle(color: Colors.white54),
          ),
          children: [
            if (n == 0)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matches were found for this photo.'),
              ),
            for (final MatchResult m in e.matches)
              ListTile(
                dense: true,
                leading: m.previewUrl == null
                    ? const Icon(Icons.public)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(m.previewUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.public)),
                      ),
                title: Text(m.title ?? m.platform ?? 'Web page',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: m.platform == null ? null : Text(m.platform!),
                trailing: m.profileUrl == null
                    ? null
                    : TextButton(
                        onPressed: () => _open(context, m.profileUrl!),
                        child: const Text('Open Page'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
