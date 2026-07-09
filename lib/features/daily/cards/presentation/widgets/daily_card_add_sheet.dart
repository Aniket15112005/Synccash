// lib/features/daily/cards/presentation/widgets/daily_card_add_sheet.dart
//
// Bottom sheet used to create a new Daily Card. Name is required; number and
// bank name are optional. Writes only to the isolated daily_card repository.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/daily/cards/domain/entities/daily_card_entity.dart';
import 'package:synccash/features/daily/cards/presentation/providers/daily_card_provider.dart';
import 'package:synccash/features/daily/cards/presentation/widgets/daily_credit_card_widget.dart';

const _kAccent = Color(0xFF8B5CF6);
const _kText = Color(0xFF1C1C1A);
const _kTextSub = Color(0xFF8A8882);
const _kField = Color(0xFFF5F4F1);
const _kFieldBorder = Color(0xFFF0EFED);

Future<void> showAddDailyCardSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddDailyCardSheet(),
  );
}

class _AddDailyCardSheet extends ConsumerStatefulWidget {
  const _AddDailyCardSheet();

  @override
  ConsumerState<_AddDailyCardSheet> createState() =>
      _AddDailyCardSheetState();
}

class _AddDailyCardSheetState extends ConsumerState<_AddDailyCardSheet> {
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  int _colorIndex = 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Card name is required');
      return;
    }

    final user = ref.read(authProvider).value;
    final cashbookId = user?.currentCashbookId;
    if (user == null || cashbookId == null) {
      setState(() => _error = 'No active cashbook found');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final card = DailyCardEntity(
        cardId: '',
        cashbookId: cashbookId,
        name: name,
        number: _numberCtrl.text.trim().isEmpty
            ? null
            : _numberCtrl.text.trim(),
        bankName:
            _bankCtrl.text.trim().isEmpty ? null : _bankCtrl.text.trim(),
        colorIndex: _colorIndex,
        createdBy: user.uid,
        creatorName: user.displayName.isEmpty ? 'Partner' : user.displayName,
        createdAt: DateTime.now(),
      );
      await ref.read(dailyCardRepositoryProvider).addCard(card);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Error saving: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFE8E7E4),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kTextSub.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('New Card',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                      letterSpacing: -0.3)),
              const SizedBox(height: 18),
              DailyCreditCardWidget(
                name: _nameCtrl.text.trim().isEmpty
                    ? 'Card holder'
                    : _nameCtrl.text.trim(),
                number: _numberCtrl.text.trim(),
                bankName: _bankCtrl.text.trim(),
                colorIndex: _colorIndex,
              ),
              const SizedBox(height: 20),
              _Field(
                label: 'NAME',
                controller: _nameCtrl,
                hint: 'e.g. Personal Visa',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _Field(
                label: 'CARD NUMBER (OPTIONAL)',
                controller: _numberCtrl,
                hint: '•••• •••• •••• 6050',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              _Field(
                label: 'BANK NAME (OPTIONAL)',
                controller: _bankCtrl,
                hint: 'e.g. HDFC Bank',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              const Text('COLOUR',
                  style: TextStyle(
                      color: _kTextSub,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      letterSpacing: 0.9)),
              const SizedBox(height: 10),
              Row(
                children: List.generate(kDailyCardGradients.length, (i) {
                  final selected = _colorIndex == i;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _colorIndex = i);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: kDailyCardGradients[i],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: selected ? _kAccent : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!,
                    style: const TextStyle(color: Color(0xFFDC2626))),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Card',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _kTextSub,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 0.9)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _kField,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kFieldBorder),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(color: _kText, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: _kTextSub.withValues(alpha: 0.6)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
