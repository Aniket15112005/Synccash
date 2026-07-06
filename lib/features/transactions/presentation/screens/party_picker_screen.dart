// lib/features/transactions/presentation/screens/party_picker_screen.dart
//
// Full-screen party name picker.
// – Text field is pinned at the BOTTOM of the body.
// – Suggestion list fills the space ABOVE the text field, so the keyboard
//   never covers it (Flutter shrinks the body, not the list).
// – "Done" in the app bar (or keyboard "Done") returns the typed name.
// – Back arrow returns null (no change).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PartyPickerScreen extends StatefulWidget {
  /// Current value to pre-populate the text field.
  final String initialValue;

  /// ADDED (FIX, permanent): party names now arrive as a Future instead of
  /// an already-resolved List. This screen is pushed by the caller BEFORE
  /// that data has necessarily loaded — see add_transaction_screen.dart's
  /// _openPartyPicker() — so it opens instantly every time, and just shows
  /// a brief "loading suggestions…" state here if the future is still
  /// pending (e.g. a slow purchase_clients/purchase_bills stream) instead of
  /// making the whole screen wait to appear.
  final Future<List<String>> allPartyNamesFuture;

  /// Whether suggestions should be shown at all.
  /// Pass false for expense / non-wholesale categories → no suggestions,
  /// just a plain text entry screen.
  final bool canSuggest;

  const PartyPickerScreen({
    super.key,
    required this.initialValue,
    required this.allPartyNamesFuture,
    required this.canSuggest,
  });

  @override
  State<PartyPickerScreen> createState() => _PartyPickerScreenState();
}

class _PartyPickerScreenState extends State<PartyPickerScreen> {
  late final TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  List<String> _allNames = [];
  List<String> _filtered = [];
  // ADDED (FIX, permanent): true until allPartyNamesFuture resolves, so the
  // suggestion area can show a lightweight loading state instead of a
  // misleading "No matching parties" while data is still on the way.
  bool _loadingNames = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _ctrl.addListener(() => _updateFilter(_ctrl.text));
    // Request focus after first frame so keyboard opens immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    if (widget.canSuggest) {
      widget.allPartyNamesFuture.then((names) {
        if (!mounted) return;
        _allNames = names;
        _loadingNames = false;
        _updateFilter(_ctrl.text);
      });
    } else {
      _loadingNames = false;
    }
  }

  void _updateFilter(String text) {
    if (!widget.canSuggest) {
      if (_filtered.isNotEmpty) setState(() => _filtered = []);
      return;
    }
    final q = text.trim().toLowerCase();
    final next = _allNames
        .where((n) => n.toLowerCase().contains(q))
        .toList();
    setState(() => _filtered = next);
  }

  /// User tapped a suggestion tile.
  void _select(String name) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, name);
  }

  /// User tapped "Done" in app bar or keyboard action.
  void _done() {
    final text = _ctrl.text.trim();
    Navigator.pop(context, text.isEmpty ? null : text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090B),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF08090B),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: Color(0xFF6B7280)),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: const Text(
          'Party Name',
          style: TextStyle(
            color: Color(0xFFF0F1F3),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _done,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Done',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1C1F26)),
        ),
      ),
      body: Column(
        children: [
          // ── Suggestion list ──────────────────────────────────────────
          // Fills all available space between the app bar and the text
          // field. When the keyboard appears it shrinks this area, keeping
          // the list fully visible above the keyboard.
          Expanded(
            child: _buildSuggestionArea(),
          ),

          // ── Separator ────────────────────────────────────────────────
          Container(height: 1, color: const Color(0xFF1C1F26)),

          // ── Search / type field — pinned at the bottom ────────────────
          Container(
            color: const Color(0xFF111316),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _done(),
              cursorColor: const Color(0xFFF0F1F3),
              cursorWidth: 1.5,
              style: const TextStyle(
                color: Color(0xFFF0F1F3),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: widget.canSuggest
                    ? 'Type party name…'
                    : 'What was this for?',
                hintStyle: const TextStyle(
                  color: Color(0xFF3D4149),
                  fontSize: 15,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 10),
                  child: Icon(
                    Icons.person_search_rounded,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 52),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _ctrl,
                  builder: (_, val, __) => val.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              size: 16, color: Color(0xFF6B7280)),
                          onPressed: () {
                            _ctrl.clear();
                            _focusNode.requestFocus();
                          },
                        )
                      : const SizedBox.shrink(),
                ),
                filled: true,
                fillColor: const Color(0xFF18191E),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF202228)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF202228)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Color(0xFF4B5563), width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionArea() {
    if (!widget.canSuggest) {
      // Non-suggestion mode: show a gentle prompt
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_rounded, size: 36, color: Color(0xFF2A2C33)),
            SizedBox(height: 12),
            Text(
              'Type a description below',
              style: TextStyle(
                color: Color(0xFF3D4149),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // ADDED (FIX, permanent): while allPartyNamesFuture is still resolving
    // (e.g. a slow purchase_clients/purchase_bills stream), show a clear
    // "loading" state instead of the misleading "No matching parties" —
    // the screen itself is already open and usable (typing + Done both
    // work immediately), only the suggestion list is still on the way.
    if (_loadingNames && _filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF6B7280),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Loading suggestions…',
              style: TextStyle(
                color: Color(0xFF3D4149),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded,
                size: 36, color: Color(0xFF2A2C33)),
            const SizedBox(height: 12),
            Text(
              _ctrl.text.trim().isEmpty
                  ? 'Start typing to search parties'
                  : 'No matching parties',
              style: const TextStyle(
                color: Color(0xFF3D4149),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: const Color(0xFF1C1F26),
      ),
      itemBuilder: (_, i) => _PickerSuggestionTile(
        partyName: _filtered[i],
        onTap: () => _select(_filtered[i]),
      ),
    );
  }
}

// ─── Suggestion tile ──────────────────────────────────────────────────────────

class _PickerSuggestionTile extends StatefulWidget {
  final String partyName;
  final VoidCallback onTap;
  const _PickerSuggestionTile(
      {required this.partyName, required this.onTap});

  @override
  State<_PickerSuggestionTile> createState() =>
      _PickerSuggestionTileState();
}

class _PickerSuggestionTileState extends State<_PickerSuggestionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: _pressed
            ? const Color(0xFF18191E)
            : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF18191E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF252830)),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.partyName,
                style: const TextStyle(
                  color: Color(0xFFD1D9E6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.north_west_rounded,
              size: 13,
              color: Color(0xFF3D4149),
            ),
          ],
        ),
      ),
    );
  }
}
