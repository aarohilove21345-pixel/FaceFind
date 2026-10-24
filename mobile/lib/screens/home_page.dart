import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ad_manager.dart';
import '../models/scan_result.dart';
import '../services/facefind_api.dart';
import '../services/history_store.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _maxBytes = 10 * 1024 * 1024;
  static const Duration _pollEvery = Duration(seconds: 2);
  static const Duration _scanTimeout = Duration(minutes: 2);

  final ImagePicker _picker = ImagePicker();
  final FaceFindApi _api = FaceFindApi();

  XFile? _photo;
  int _photoBytes = 0;
  bool _consented = false;
  bool _busy = false;
  bool _cancelled = false;
  String? _statusText;
  String? _error;
  ScanState? _scan;

  @override
  void dispose() {
    _cancelled = true;
    _api.close();
    super.dispose();
  }

  Future<void> _selectPhoto() async {
    if (_busy) return;
    AdManager.instance.skipNextAppOpen();
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final String name = file.name.toLowerCase();
    final bool okType = name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
    final int size = await File(file.path).length();

    if (!mounted) return;
    if (!okType) {
      setState(() => _error = 'Unsupported file type. Please choose a JPG, PNG or WebP photo.');
      return;
    }
    if (size > _maxBytes) {
      setState(() => _error = 'This photo is larger than 10 MB. Please choose a smaller photo.');
      return;
    }
    setState(() {
      _photo = file;
      _photoBytes = size;
      _error = null;
      _scan = null;
      _statusText = null;
    });
  }

  void _clearPhoto() {
    if (_busy) return;
    setState(() {
      _photo = null;
      _photoBytes = 0;
      _scan = null;
      _error = null;
      _statusText = null;
    });
  }

  Future<bool> _askConsent() async {
    if (_consented) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Before you continue'),
        content: const Text(
          'Your photo will be uploaded to an external image-search service to '
          'look for web pages where it appears. Only upload photos of yourself '
          'or of people who have given you permission.\n\n'
          'Match scores are not proof of identity. Results may be wrong.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Agree'),
          ),
        ],
      ),
    );
    _consented = ok == true;
    return _consented;
  }

  Future<void> _processPhoto() async {
    if (_busy) return;
    final XFile? photo = _photo;
    if (photo == null) {
      setState(() => _error = 'Please select a photo first.');
      return;
    }
    if (!FaceFindApi.isConfigured) {
      setState(() => _error =
          'The app is not configured: backend URL is missing. Please install an official build.');
      return;
    }
    if (!await _askConsent() || !mounted) return;

    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _scan = null;
      _statusText = 'Uploading photo...';
    });

    try {
      ScanState scan = await _api.createScan(File(photo.path));
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _statusText = 'Scanning...';
      });

      final DateTime deadline = DateTime.now().add(_scanTimeout);
      while (!scan.isFinished) {
        await Future<void>.delayed(_pollEvery);
        if (!mounted || _cancelled) return;
        if (DateTime.now().isAfter(deadline)) {
          throw ApiException('The scan is taking too long. Please try again later.');
        }
        scan = await _api.getScan(scan.id);
        if (!mounted || _cancelled) return;
        setState(() => _scan = scan);
      }

      if (scan.isFailed) {
        throw ApiException(scan.errorMessage ?? 'The scan failed. Please try again.');
      }
      await HistoryStore.add(scan);
      if (!mounted) return;
      setState(() => _statusText = 'Scan complete');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancelScan() {
    setState(() {
      _cancelled = true;
      _busy = false;
      _statusText = 'Scan cancelled';
    });
  }

  Future<void> _openProfile(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _error = 'This profile link is not valid.');
      return;
    }
    AdManager.instance.skipNextAppOpen();
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) setState(() => _error = 'Could not open the link.');
  }

  @override
  Widget build(BuildContext context) {
    final ScanState? scan = _scan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _header(),
        const SizedBox(height: 8),
        const Text(
          'Select a photo and FaceFind will look for web pages where it appears.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        _pickerCard(),
        if (_photo != null) ...[
          const SizedBox(height: 12),
          _previewCard(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorCard(_error!),
        ],
        if (_statusText != null) ...[
          const SizedBox(height: 12),
          _statusCard(scan?.credits),
        ],
        if (scan != null && scan.isCompleted) ...[
          const SizedBox(height: 12),
          _resultsCard(scan),
        ],
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'FaceFind Version 1.0.0',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.center_focus_strong, color: Color(0xFF0A84FF), size: 36),
        SizedBox(width: 8),
        Text('FaceFind',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: child,
    );
  }

  Widget _pickerCard() {
    return _card(
      child: Column(
        children: [
          const Icon(Icons.cloud_upload_outlined,
              color: Color(0xFF0A84FF), size: 40),
          const SizedBox(height: 8),
          const Text('Select a Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _selectPhoto,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Select Photo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    final XFile photo = _photo!;
    final String mb = (_photoBytes / (1024 * 1024)).toStringAsFixed(1);
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(photo.path),
                        width: 110, height: 110, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _clearPhoto,
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black87,
                        child: Icon(Icons.close, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(photo.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('$mb MB',
                        style: const TextStyle(color: Colors.white54)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _selectPhoto,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Change Photo'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _processPhoto,
              icon: const Icon(Icons.center_focus_weak),
              label: const Text('Process Photo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  Widget _statusCard(int? credits) {
    return _card(
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3))
          else
            const Icon(Icons.info_outline, color: Color(0xFF0A84FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_statusText ?? '',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (_busy)
            TextButton(onPressed: _cancelScan, child: const Text('Cancel')),
          if (credits != null)
            Chip(
              avatar: const Icon(Icons.storage, size: 16),
              label: Text('Credits: $credits'),
            ),
        ],
      ),
    );
  }

  Widget _resultsCard(ScanState scan) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.list_alt, color: Color(0xFF0A84FF)),
              SizedBox(width: 8),
              Text('Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          if (scan.matches.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matches were found for this photo.'),
              ),
            )
          else ...[
            for (final MatchResult m in scan.matches) _matchTile(m),
            const SizedBox(height: 4),
            const Text(
              'Match scores are not proof of identity. Results may be wrong.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchTile(MatchResult m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (m.previewUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(m.previewUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person, size: 40)),
            )
          else
            const Icon(Icons.person, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.platform ?? 'Unknown platform',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (m.title != null)
                  Text(m.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70)),
                if (m.handle != null)
                  Text(m.handle!,
                      style: const TextStyle(color: Color(0xFF0A84FF))),
                if (m.score != null)
                  Text('Match score: ${m.score!.toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          if (m.profileUrl != null)
            FilledButton(
              onPressed: () => _openProfile(m.profileUrl!),
              child: const Text('Open Page'),
            ),
        ],
      ),
    );
  }
}
