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

  /// Whether suggestions should be shown at all. When false, this remains a
  /// plain text entry screen; when true, the user can choose a saved name or
  /// confirm a new one.
  final bool canSuggest;
  final String title;
  final String inputHint;
  final String entityLabel;

  const PartyPickerScreen({
    super.key,
    required this.initialValue,
    required this.allPartyNamesFuture,
    required this.canSuggest,
    this.title = 'Party Name',
    this.inputHint = 'Type party name…',
    this.entityLabel = 'party',
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

  // FIX: true when the user has typed a name that is not already in the list.
  // The "Create new party" tile is shown so they can tap OK instead of having
  // to reach up to the "Done" button in the app bar.
  bool get _showCreateNew {
    if (!widget.canSuggest) return false;
    final typed = _ctrl.text.trim();
    if (typed.isEmpty) return false;
    return !_allNames.any((n) => n.toLowerCase() == typed.toLowerCase());
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
        title: Text(
          widget.title,
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
                    ? widget.inputHint
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
      // FIX: when the typed name doesn't match any saved party, show a
      // "Create new party" tile prominently so the user doesn't have to
      // reach up to the "Done" button — they can tap OK right in the list.
      if (_showCreateNew) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _CreateNewPartyTile(
            name: _ctrl.text.trim(),
            entityLabel: widget.entityLabel,
            onTap: () => Navigator.pop(context, _ctrl.text.trim()),
          ),
        );
      }
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

    // When there ARE matches but the typed text is not an exact match,
    // append a "Create new party" tile at the bottom of the list.
    final showCreate = _showCreateNew;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      itemCount: _filtered.length + (showCreate ? 1 : 0),
      separatorBuilder: (_, __) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: const Color(0xFF1C1F26),
      ),
      itemBuilder: (_, i) {
        if (showCreate && i == _filtered.length) {
          return _CreateNewPartyTile(
            name: _ctrl.text.trim(),
            entityLabel: widget.entityLabel,
            onTap: () => Navigator.pop(context, _ctrl.text.trim()),
          );
        }
        return _PickerSuggestionTile(
          partyName: _filtered[i],
          onTap: () => _select(_filtered[i]),
        );
      },
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

// ─── Create-new-party tile ────────────────────────────────────────────────────
// FIX: shown when the user's typed text doesn't match any existing party.
// Tapping it is equivalent to tapping "Done" — pops the picker with the
// typed name so the caller can proceed to create the bill with that name.

class _CreateNewPartyTile extends StatefulWidget {
  final String name;
  final String entityLabel;
  final VoidCallback onTap;
  const _CreateNewPartyTile({
    required this.name,
    required this.onTap,
    this.entityLabel = 'party',
  });

  @override
  State<_CreateNewPartyTile> createState() => _CreateNewPartyTileState();
}

class _CreateNewPartyTileState extends State<_CreateNewPartyTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFF1A2235)
              : const Color(0xFF0F1520).withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed
                ? const Color(0xFF3B82F6).withOpacity(0.5)
                : const Color(0xFF1E2840),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2840),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.4)),
              ),
              child: const Icon(
                Icons.person_add_outlined,
                size: 16,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      color: Color(0xFFD1D9E6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'New ${widget.entityLabel} — tap to use this name',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
