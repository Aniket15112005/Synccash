import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'voice_recorder_service.dart';
import 'party_voice_navigator.dart';

/// Voice navigation mic button — lets the user say something like "open
/// New Fashion party statement" to jump straight to that party's statement
/// screen, instead of scrolling/searching manually.
///
/// INTENTIONALLY WEB ONLY: enabled whenever kIsWeb is true, regardless of
/// the underlying device/OS (desktop browser, Android browser, iOS Safari
/// PWA, etc.). Returns an empty widget on native app builds (native
/// Android/iOS) — this is a deliberate restriction per product decision,
/// not a technical limitation of the underlying voice pipeline (which is
/// cross-platform).
class PartyNavMicButton extends StatefulWidget {
  /// Current list of real party names to fuzzy-match the spoken name against.
  final List<String> partyNames;

  /// Called with the matched party name once a command is understood and a
  /// match found. The caller is responsible for navigating.
  final void Function(String matchedPartyName) onPartyMatched;

  /// Called when a command was understood but no matching party was found,
  /// so the caller can show its own "not found" messaging if desired.
  final void Function(String spokenName)? onNoMatch;

  const PartyNavMicButton({
    super.key,
    required this.partyNames,
    required this.onPartyMatched,
    this.onNoMatch,
  });

  /// Whether this feature should be shown at all on the current platform.
  /// Excluded on iOS PWA — MediaRecorder is unreliable in iOS Safari /
  /// home-screen PWA, so the button is hidden there.
  static bool get isSupportedPlatform =>
      kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  @override
  State<PartyNavMicButton> createState() => _PartyNavMicButtonState();
}

class _PartyNavMicButtonState extends State<PartyNavMicButton> {
  final _recorder = VoiceRecorderService();
  bool _recording = false;
  bool _processing = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_processing) return;

    if (!_recording) {
      HapticFeedback.mediumImpact();
      // ADDED try/catch: previously an exception thrown while starting the
      // recorder (e.g. MediaRecorder setup failing on iOS PWA) propagated
      // uncaught, so the button just sat there after the permission prompt
      // with no feedback at all. Now the real error is shown.
      try {
        final started = await _recorder.start();
        if (!started) {
          if (mounted) _showError('Microphone permission denied');
          return;
        }
        if (mounted) setState(() => _recording = true);
      } catch (e) {
        if (mounted) _showError('Voice error: $e');
      }
      return;
    }

    // Second tap — stop and process.
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = false;
      _processing = true;
    });

    try {
      final recorded = await _recorder.stop();
      final apiKey = dotenv.env['GROQ_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing GROQ_API_KEY');
      }
      final spokenName = await PartyVoiceNavigator(apiKey).extractPartyName(recorded);
      if (spokenName == null) {
        if (mounted) _showError("Didn't catch a party name — try again");
        return;
      }
      final match = PartyVoiceNavigator.findBestMatch(spokenName, widget.partyNames);
      if (match == null) {
        widget.onNoMatch?.call(spokenName);
        if (widget.onNoMatch == null && mounted) {
          _showError('No party found matching "$spokenName"');
        }
        return;
      }
      widget.onPartyMatched(match);
    } catch (e) {
      if (mounted) _showError('Voice error: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFE85C5C),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!PartyNavMicButton.isSupportedPlatform) return const SizedBox.shrink();

    final Color color = _recording
        ? const Color(0xFFE85C5C)
        : (_processing ? const Color(0xFFF5A623) : const Color(0xFF6C7FE4));

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Center(
          child: _processing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(
                  _recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: color,
                  size: 18,
                ),
        ),
      ),
    );
  }
}
