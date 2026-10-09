import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../nfc/card_reader.dart';
import '../nfc/models.dart';
import '../nfc/report.dart';
import 'result_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.reader = const CardReader()});

  final CardReader reader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  NFCAvailability? _availability;
  bool _scanning = false;
  String? _error;
  CardReadResult? _result;
  final List<CardReadResult> _history = [];
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
    // Re-check when returning from Settings after switching NFC on.
    _lifecycle = AppLifecycleListener(onResume: _checkAvailability);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (_scanning) widget.reader.cancel();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    NFCAvailability availability;
    try {
      availability = await widget.reader.availability();
    } catch (_) {
      availability = NFCAvailability.not_supported;
    }
    if (mounted) setState(() => _availability = availability);
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final result = await widget.reader.readCard();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _result = result;
        _history.insert(0, result);
        if (_history.length > 20) _history.removeLast();
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeNfcError(e));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _cancelScan() async {
    await widget.reader.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  void _copyReport() {
    final r = _result;
    if (r == null) return;
    Clipboard.setData(ClipboardData(text: buildTextReport(r)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full report copied')));
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in _history)
              ListTile(
                leading: const Icon(Icons.contactless),
                title: Text(r.title),
                subtitle: Text(
                  '${_uid(r) ?? 'No UID'}  •  ${TimeOfDay.fromDateTime(r.readAt).format(context)}',
                ),
                selected: identical(r, _result),
                onTap: () {
                  setState(() => _result = r);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String? _uid(CardReadResult r) {
    for (final s in r.sections) {
      for (final f in s.fields) {
        if (f.label == 'UID (hex)') return f.value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final available = _availability == NFCAvailability.available;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Card Reader'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(tooltip: 'Scan history', icon: const Icon(Icons.history), onPressed: _showHistory),
          if (_result != null)
            IconButton(tooltip: 'Copy full report', icon: const Icon(Icons.copy_all), onPressed: _copyReport),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildBody(),
      ),
      floatingActionButton: available && !_scanning
          ? FloatingActionButton.extended(
              onPressed: _scan,
              icon: const Icon(Icons.contactless),
              label: Text(_result == null ? 'Scan card' : 'Scan another'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_availability == null) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
    }
    if (_availability == NFCAvailability.not_supported) {
      return const _Message(
        key: ValueKey('unsupported'),
        icon: Icons.portable_wifi_off,
        title: 'NFC not supported',
        body: 'This device has no NFC reader, so it cannot read cards.',
      );
    }
    if (_availability == NFCAvailability.disabled) {
      return _Message(
        key: const ValueKey('disabled'),
        icon: Icons.nfc,
        title: 'NFC is turned off',
        body: 'Turn on NFC in your phone settings (usually under Connected devices '
            'or Connections), then come back to this app.',
        action: OutlinedButton(onPressed: _checkAvailability, child: const Text('Check again')),
      );
    }
    if (_scanning) {
      return _Message(
        key: const ValueKey('scanning'),
        icon: Icons.contactless,
        pulse: true,
        title: 'Hold a card near your phone',
        body: 'Place the card flat against the back of the phone, near the camera, '
            'and keep it still until reading finishes.',
        action: TextButton(onPressed: _cancelScan, child: const Text('Cancel')),
      );
    }
    return Column(
      key: ValueKey(_result?.readAt ?? 'idle'),
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            leading: const Icon(Icons.error_outline),
            actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('Dismiss'))],
          ),
        Expanded(
          child: _result != null
              ? ResultView(result: _result!)
              : const _Message(
                  icon: Icons.contactless_outlined,
                  title: 'Ready to scan',
                  body: 'Tap "Scan card", then hold an NFC tag, sticker, key fob, '
                      'transit or access card against your phone.\n\n'
                      'Works with 13.56 MHz cards (MIFARE, NTAG, DESFire, FeliCa, ISO 15693). '
                      'Older 125 kHz RFID cards cannot be read by phones.',
                ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.pulse = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = Icon(icon, size: 96, color: theme.colorScheme.primary);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pulse ? _Pulse(child: iconWidget) : iconWidget,
            const SizedBox(height: 24),
            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(begin: 0.9, end: 1.1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    child: widget.child,
  );
}
