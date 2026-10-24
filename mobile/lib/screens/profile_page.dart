import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SizedBox(height: 24),
        Icon(Icons.person, size: 56, color: Color(0xFF0A84FF)),
        SizedBox(height: 12),
        Center(
          child: Text('FaceFind',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        SizedBox(height: 4),
        Center(
          child: Text('FaceFind Version 1.0.0',
              style: TextStyle(color: Colors.white54)),
        ),
        SizedBox(height: 24),
        Text(
          'Privacy and responsible use',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Text(
          'Photos you select are uploaded to an external face-search service '
          'to look for matching public profiles. Only upload photos of '
          'yourself or of people who have given you permission. Match scores '
          'are not proof of identity and results may be wrong.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}
