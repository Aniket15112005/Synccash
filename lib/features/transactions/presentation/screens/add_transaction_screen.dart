// lib/features/transactions/presentation/screens/add_transaction_screen.dart

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:synccash/features/auth/presentation/providers/auth_provider.dart';
import 'package:synccash/features/transactions/domain/entities/transaction_entity.dart';
import 'package:synccash/features/transactions/presentation/providers/transaction_provider.dart';
// ADDED: sales bill imports
import 'package:synccash/features/sales/data/models/sale_bill_model.dart';
import 'package:synccash/features/sales/domain/entities/sale_bill_entity.dart';
import 'package:synccash/features/sales/presentation/widgets/bill_no_dropdown_field.dart';
import 'package:synccash/features/sales/presentation/providers/sale_bill_provider.dart';
// ADDED: party provider for description autocomplete
import 'package:synccash/features/sales/presentation/providers/party_provider.dart';
// ADDED: dedicated party picker screen (keyboard-safe suggestion flow)
import 'package:synccash/features/transactions/presentation/screens/party_picker_screen.dart';
// ADDED: purchase bill imports (mirror of the sales bill imports above)
import 'package:synccash/features/purchases/domain/entities/purchase_bill_entity.dart';
import 'package:synccash/features/purchases/presentation/widgets/purchase_bill_no_dropdown_field.dart';
import 'package:synccash/features/purchases/presentation/providers/purchase_bill_provider.dart';
import 'package:synccash/features/purchases/presentation/providers/purchase_client_provider.dart';
import 'package:synccash/features/transactions/data/services/payment_storage_service.dart';
import 'package:synccash/features/transactions/presentation/screens/payment_receipt_generator.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:synccash/voice/voice_recorder_service.dart';
import 'package:synccash/voice/ai_command_fallback.dart';
import 'package:synccash/voice/parsed_entry.dart';

class _C {
  static const bg       = Color(0xFF08090B);
  static const surface  = Color(0xFF111316);
  static const surface2 = Color(0xFF18191E);
  static const border   = Color(0xFF202228);
  static const border2  = Color(0xFF2A2C33);
  static const textPri  = Color(0xFFF0F1F3);
  static const textSec  = Color(0xFF6B7280);
  static const textMut  = Color(0xFF3D4149);
  static const income   = Color(0xFF22C55E);
  static const expense  = Color(0xFFF43F5E);
}

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionEntity? existingTransaction;
  final String?            initialCategory;
  final bool               categoryLocked;
  const AddTransactionScreen({
    super.key,
    this.existingTransaction,
    this.initialCategory,
    this.categoryLocked = false,
  });

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen>
    with SingleTickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl   = TextEditingController();

  PlatformFile? _paymentAttachment;
  Uint8List? _paymentReceiptBytes;
  String? _paymentReceiptName;
  PaymentReceiptData? _paymentReceiptData;
  bool _removePaymentAttachment = false;
  bool _removePaymentReceipt = false;

  String   _type         = 'expense';
  String   _category     = 'Retail';
  bool     _submitting   = false;
  DateTime _selectedDate = DateTime.now();

  // ADDED: tracks the bill selected from the dropdown
  SaleBillEntity? _selectedBill;
  bool _isObPayment = false; // ADDED: tracks if OB payment is selected

  // ADDED: true while fetching the existing linked bill on edit open
  bool _loadingBill = false;

  // ADDED: purchase-side mirror of the sale bill selection state
  PurchaseBillEntity? _selectedPurchaseBill;
  bool _isPurchaseObPayment = false;
  bool _loadingPurchaseBill = false;

  // ADDED: true once party name is confirmed (selected from picker or pre-filled when editing)
  bool _partyConfirmed = false;

  // ADDED (FIX, permanent): guards against a double-tap opening two pickers
  // in the same frame. The real freeze bug is now gone at the root — see
  // _openPartyPicker() below, which no longer waits on ANY provider before
  // navigating — so this is just a cheap safety net, not load-bearing.
  bool _openingPartyPicker = false;

  // ADDED: voice command state
  final _voiceRecorder = VoiceRecorderService();
  bool _voiceRecording = false;
  bool _voiceProcessing = false;

  late final AnimationController _btnCtrl;
  late final Animation<double>   _btnScale;

  static String _normalizeCategory(String cat) {
    final lower = cat.toLowerCase();
    if (lower == 'upi') return 'UPI';
    if (lower == 'cb') return 'CB';
    return lower[0].toUpperCase() + lower.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _btnScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut),
    );

    // Pre-fill if editing
    final tx = widget.existingTransaction;
    if (tx != null) {
      _type          = tx.type;
      _category      = _normalizeCategory(tx.category);
      _selectedDate  = tx.createdAt;
      _amountCtrl.text = tx.amount.toStringAsFixed(0);
      _descCtrl.text   = tx.description;

      // ADDED: load the existing linked bill so it appears pre-selected in the
      // dropdown and the user can change it without first clearing the link.
      if (tx.linkedSaleBillId != null && tx.linkedSaleBillId!.isNotEmpty) {
        _loadExistingBill(tx.cashbookId, tx.linkedSaleBillId!);
      }
      // ADDED: load the existing linked purchase bill (mirror of above).
      // Gated behind _purchaseFeatureEnabled so this is only fetched when the
      // purchase feature is enabled.
      if (_purchaseFeatureEnabled &&
          tx.linkedPurchaseBillId != null && tx.linkedPurchaseBillId!.isNotEmpty) {
        _loadExistingPurchaseBill(tx.cashbookId, tx.linkedPurchaseBillId!);
      }
      // Editing: description is already a confirmed party name
      _partyConfirmed = tx.description.isNotEmpty;
    } else if (widget.initialCategory != null) {
      _category = widget.initialCategory!;
    }

    // ADDED: rebuild when description changes so BillNoDropdownField updates
    _descCtrl.addListener(_onDescChanged);

    // FIX (instant party suggestions): Riverpod StreamProviders are lazy —
    // they don't start until the first ref.watch/read. If the user taps the
    // party name field before the first build() has watched partiesProvider,
    // _resolveAllPartyNames() has to wait for the stream to emit, causing
    // the "loading suggestions…" spinner to show for 1-3 s. Reading the
    // providers here kicks off the Firestore streams immediately on screen
    // open, so data is almost always cached by the time the user taps.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(partiesProvider);
      ref.read(allSaleBillsProvider);
    });
  }

  // ADDED: fetches the SaleBillEntity for the existing linkedSaleBillId so
  // it can be shown pre-selected in the dropdown when editing a transaction.
  Future<void> _loadExistingBill(String cashbookId, String billId) async {
    if (!mounted) return;
    setState(() => _loadingBill = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cashbooks')
          .doc(cashbookId)
          .collection('sale_bills')
          .doc(billId)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _selectedBill = SaleBillModel.fromFirestore(doc);
        });
      }
    } catch (_) {
      // silently ignore — dropdown will just be unselected
    } finally {
      if (mounted) setState(() => _loadingBill = false);
    }
  }

  // ADDED: fetches the PurchaseBillEntity for the existing linkedPurchaseBillId
  // so it can be shown pre-selected in the dropdown when editing a transaction.
  Future<void> _loadExistingPurchaseBill(String cashbookId, String billId) async {
    if (!mounted) return;
    setState(() => _loadingPurchaseBill = true);
    try {
      final bill = await loadPurchaseBillDirect(cashbookId, billId);
      if (mounted && bill != null) {
        setState(() => _selectedPurchaseBill = bill);
      }
    } catch (_) {
      // silently ignore — dropdown will just be unselected
    } finally {
      if (mounted) setState(() => _loadingPurchaseBill = false);
    }
  }

  // ADDED
  void _onDescChanged() {
    _partyConfirmed = false;
    _selectedBill = null;
    _isObPayment = false;
    _selectedPurchaseBill = null;
    _isPurchaseObPayment = false;
    setState(() {});
  }

  // ADDED: opens the dedicated PartyPickerScreen and back-fills the description
  // field with whatever name the user confirmed there.
  //
  // FIX (permanent, root cause): the previous fixes (re-entrancy guard,
  // shorter timeout, spinner) only made a slow/erroring purchase stream
  // LESS BAD — they didn't remove the wait itself, so the field could still
  // pause for up to ~3-6s before the picker opened. The actual bug was that
  // _openPartyPicker() awaited party/bill/purchase-client/purchase-bill data
  // BEFORE calling Navigator.push at all. That ordering is now reversed:
  // the picker screen is pushed immediately (a real Flutter Navigator.push
  // is synchronous — the route is on screen before this function's next
  // line runs), and the four data sources are resolved in the background as
  // a Future that PartyPickerScreen itself awaits internally to populate
  // suggestions once ready. A tap now opens the picker in the same frame no
  // matter how slow or broken purchase_clients/purchase_bills are; the
  // worst case is now "suggestions pop in a moment late", never "tap does
  // nothing".
  Future<void> _openPartyPicker() async {
    // Still a cheap guard against a double-tap landing in the same frame
    // before the new route has visually covered the button.
    if (_openingPartyPicker) return;
    _openingPartyPicker = true;

    final canSuggest = _descriptionPickerEnabled;
    final isPurchasePicker = _purchaseDescriptionSuggestionsEnabled;
    final namesFuture = isPurchasePicker
        ? _resolvePurchaseClientNames()
        : canSuggest
            ? _resolveAllPartyNames()
            : Future.value(const <String>[]);

    final navigateFuture = Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PartyPickerScreen(
          initialValue:        _descCtrl.text,
          allPartyNamesFuture: namesFuture,
          canSuggest:          canSuggest,
          title:               isPurchasePicker ? 'Purchase Client' : 'Party Name',
          inputHint:           isPurchasePicker
              ? 'Type purchase client or description…'
              : 'Type party name…',
          entityLabel:          isPurchasePicker ? 'client' : 'party',
        ),
      ),
    );

    // The route above is already pushed by this point (Navigator.push
    // enqueues the transition synchronously); clear the guard so it can
    // never block a legitimate later tap.
    _openingPartyPicker = false;

    final result = await navigateFuture;

    if (result != null && mounted) {
      _descCtrl.removeListener(_onDescChanged);
      _descCtrl.text  = result;
      _partyConfirmed = result.isNotEmpty;
      if (result.isEmpty) {
        _selectedBill = null;
        _isObPayment  = false;
      }
      _descCtrl.addListener(_onDescChanged);
      setState(() {});
    }
  }

  // All four sources — sale parties, sale bills, purchase clients, purchase bills —
  // are always merged into one unified list regardless of category or type.
  // Each source is resolved independently so a failure or empty stream in one
  // can never wipe out data from the others.
  Future<List<String>> _resolveAllPartyNames() async {
    final partiesFuture = _resolveAsync(
      cached: ref.read(partiesProvider).asData?.value,
      load: () => ref.read(partiesProvider.future),
    );
    final billsFuture = _resolveAsync(
      cached: ref.read(allSaleBillsProvider).asData?.value,
      load: () => ref.read(allSaleBillsProvider.future),
    );

    // ADDED: Android has no purchase feature, so purchaseClientsProvider /
    // allPurchaseBillsProvider are never read there at all — not even a
    // background read. That's the whole fix: those two Firestore streams
    // are simply never opened on Android.
    if (!_purchaseFeatureEnabled) {
      final savedParties = await partiesFuture;
      final allBills     = await billsFuture;
      return <String>{
        ...savedParties.map((p) => p.partyName),
        ...allBills.map((b) => b.partyName.trim()),
      }.toList()..sort();
    }
    final purchaseClientsFuture = _resolveAsync(
      cached: ref.read(purchaseClientsProvider).asData?.value,
      load: () => ref.read(purchaseClientsProvider.future),
    );
    final purchaseBillsFuture = _resolveAsync(
      cached: ref.read(allPurchaseBillsProvider).asData?.value,
      load: () => ref.read(allPurchaseBillsProvider.future),
    );

    final savedParties       = await partiesFuture;
    final allBills           = await billsFuture;
    final purchaseClients    = await purchaseClientsFuture;
    final allPurchaseBills   = await purchaseBillsFuture;

    return <String>{
      ...savedParties.map((p) => p.partyName),
      ...allBills.map((b) => b.partyName.trim()),
      ...purchaseClients.map((c) => c.clientName),
      ...allPurchaseBills.map((b) => b.clientName.trim()),
    }.toList()..sort();
  }

  // Expense entries must only suggest purchase clients. Reusing the broader
  // income-party union here could accidentally link an expense to a sales
  // customer with the same name.
  Future<List<String>> _resolvePurchaseClientNames() async {
    final clientsFuture = _resolveAsync(
      cached: ref.read(purchaseClientsProvider).asData?.value,
      load: () => ref.read(purchaseClientsProvider.future),
    );
    final billsFuture = _resolveAsync(
      cached: ref.read(allPurchaseBillsProvider).asData?.value,
      load: () => ref.read(allPurchaseBillsProvider.future),
    );

    final clients = await clientsFuture;
    final bills = await billsFuture;
    return <String>{
      ...clients.map((c) => c.clientName.trim()),
      ...bills.map((b) => b.clientName.trim()),
    }.where((name) => name.isNotEmpty).toList()..sort();
  }

  // ADDED: resolves a single StreamProvider's data independently — returns
  // the cached value immediately if already loaded, otherwise awaits the
  // stream's first emission with a timeout, and only falls back to an empty
  // list if that genuinely fails/errors/times out. Kept separate per-source
  // (rather than combined via Future.wait) so one source failing — e.g.
  // allSaleBillsProvider's Stream.empty() when the cashbook id isn't ready
  // yet — can never wipe out a different source's already-successful data.
  Future<List<T>> _resolveAsync<T>({
    required List<T>? cached,
    required Future<List<T>> Function() load,
  }) async {
    if (cached != null) return cached;
    try {
      // ADDED (FIX): shortened from 6s to 3s. A slow/erroring purchase
      // collection (e.g. Firestore rules not yet deployed for
      // purchase_clients/purchase_bills) was making the description field
      // look frozen for up to 6 seconds before falling back to an empty
      // list — now capped at 3s per source, with all four sources still
      // resolving in parallel.
      return await load().timeout(const Duration(seconds: 3));
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    // ADDED: remove listener before disposing
    _descCtrl.removeListener(_onDescChanged);
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _btnCtrl.dispose();
    _voiceRecorder.dispose(); // ADDED
    super.dispose();
  }

  // ADDED: voice command handler — records audio, sends to Groq (Whisper
  // transcription + Llama structured extraction), then pre-fills the form fields.
  Future<void> _onVoiceMicTap() async {
    if (!_voiceRecording) {
      // ADDED try/catch: previously an exception thrown while starting the
      // recorder (e.g. MediaRecorder setup failing on iOS PWA) propagated
      // uncaught, so the button just sat there after the permission prompt
      // with no feedback at all. Now the real error is shown.
      try {
        final started = await _voiceRecorder.start();
        if (started) {
          HapticFeedback.selectionClick();
          setState(() => _voiceRecording = true);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice error: ${e.toString()}')),
          );
        }
      }
      return;
    }

    setState(() {
      _voiceRecording = false;
      _voiceProcessing = true;
    });

    try {
      final recorded = await _voiceRecorder.stop();
      final apiKey = dotenv.env['GROQ_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing GROQ_API_KEY');
      }
      final result = await AiCommandFallback(apiKey).parseAudio(recorded);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't understand, please try again or type manually"),
          ),
        );
        return;
      }

      final parsed = ParsedEntry.fromJson(result);
      if (!parsed.isUsable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't detect amount/type, please try again"),
          ),
        );
        return;
      }

      // ADDED: build the same "all known party names" set the suggestion
      // list uses, so we can auto-confirm an exact match spoken by voice
      // instead of forcing a manual tap on the suggestion list.
      final savedParties = ref.read(partiesProvider).asData?.value ?? [];
      final allBills = ref.read(allSaleBillsProvider).asData?.value ?? [];
      final allPartyNames = <String>{
        ...savedParties.map((p) => p.partyName),
        ...allBills.map((b) => b.partyName.trim()),
      };

      // Pre-fill existing form fields with the parsed voice entry — user still
      // reviews and taps the existing Save/Record button, nothing auto-saves.
      setState(() {
        if (parsed.amount != null) {
          _amountCtrl.text = parsed.amount!.toStringAsFixed(0);
        }
        if (parsed.type == 'income' || parsed.type == 'expense') {
          _type = parsed.type!;
        }
        if (parsed.partyName != null && parsed.partyName!.trim().isNotEmpty) {
          final spokenName = parsed.partyName!.trim();
          // Temporarily detach the listener so setting text doesn't reset
          // _partyConfirmed before we've had a chance to check for a match.
          _descCtrl.removeListener(_onDescChanged);
          _descCtrl.text = spokenName;
          final exactMatch = allPartyNames.firstWhere(
            (name) => name.toLowerCase() == spokenName.toLowerCase(),
            orElse: () => '',
          );
          if (exactMatch.isNotEmpty) {
            _descCtrl.text = exactMatch; // use the saved casing/spelling
            _partyConfirmed = true;
          } else {
            _partyConfirmed = false;
          }
          _descCtrl.addListener(_onDescChanged);
        }
        // ADDED: apply spoken category (Retail/Wholesale/Bank/UPI/CB).
        if (parsed.category != null && parsed.category!.trim().isNotEmpty) {
          const validCategories = {'Retail', 'Wholesale', 'Bank', 'UPI', 'CB'};
          final normalized = _normalizeCategory(parsed.category!.trim());
          if (validCategories.contains(normalized) && normalized != _category) {
            _category = normalized;
            if (normalized != 'Wholesale' && normalized != 'Bank' && normalized != 'UPI') {
              _selectedBill = null;
              _isObPayment = false;
            }
          }
        }
        // ADDED: apply spoken date (e.g. "yesterday", "5 July")
        if (parsed.date != null) {
          final d = parsed.date!;
          final now = DateTime.now();
          final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
          _selectedDate = isToday ? now : DateTime(d.year, d.month, d.day, 12, 0, 0);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Heard: "${parsed.transcript ?? ''}"')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _voiceProcessing = false);
    }
  }

  // Purchase clients and bills are available only on iOS and web/PWA.
  bool get _purchaseFeatureEnabled =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;

  // Party-name suggestions are only useful for income entries that can be
  // matched to a customer/client. Other transaction descriptions stay as a
  // normal free-text field.
  bool get _descriptionSuggestionsEnabled =>
      _type == 'income' &&
      (_category == 'Wholesale' ||
          _category == 'Bank' ||
          _category == 'CB' ||
          _category == 'UPI');

  // Every expense can optionally be tied to a purchase client. The picker
  // still allows arbitrary text, so existing free-text expense entries keep
  // working exactly as before when no client is selected.
  bool get _purchaseDescriptionSuggestionsEnabled =>
      _purchaseFeatureEnabled && _type == 'expense';

  bool get _descriptionPickerEnabled =>
      _descriptionSuggestionsEnabled || _purchaseDescriptionSuggestionsEnabled;

  bool _isKnownPurchaseClient(WidgetRef ref) {
    if (!_purchaseFeatureEnabled) return false;
    final name = _descCtrl.text.trim().toLowerCase();
    if (name.isEmpty) return false;
    final clients = ref.read(purchaseClientsProvider).asData?.value ?? [];
    final bills = ref.read(allPurchaseBillsProvider).asData?.value ?? [];
    return clients.any((c) => c.clientName.trim().toLowerCase() == name) ||
        bills.any((b) => b.clientName.trim().toLowerCase() == name);
  }

  Color get _accentColor => _type == 'income' ? _C.income : _C.expense;

  void _switchType(String type) {
    if (_type == type) return;
    HapticFeedback.selectionClick();
    setState(() {
      _type = type;
      _partyConfirmed = false;
      // Clear bill link and OB flag when switching away from income —
      // bills and OB payments only apply to income entries.
      if (type != 'income') {
        _selectedBill = null;
        _isObPayment  = false;
      }
      // ADDED: clear purchase bill link and OB flag when switching away from expense
      if (type != 'expense') {
        _selectedPurchaseBill = null;
        _isPurchaseObPayment = false;
      }
    });
  }

  void _switchCategory(String cat) {
    if (_category == cat) return;
    HapticFeedback.selectionClick();
    setState(() {
      _category = cat;
      // Clear sale bill when switching away from Wholesale/Bank/UPI.
      if (cat != 'Wholesale' && cat != 'Bank' && cat != 'UPI') {
        _selectedBill = null;
        _isObPayment = false;
      }
      // Purchase payments are valid for every expense category. Only clear
      // purchase state when this is an income entry.
      if (_type != 'expense') {
        _selectedPurchaseBill = null;
        _isPurchaseObPayment = false;
      }
    });
  }

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _accentColor,
              onPrimary: Colors.black,
              surface: const Color(0xFF161922),
              onSurface: _C.textPri,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF111316),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        final now = DateTime.now();
        if (picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day) {
          _selectedDate = now;
        } else {
          _selectedDate = DateTime(
              picked.year, picked.month, picked.day, 12, 0, 0);
        }
      });
    }
  }

  Future<void> _pickPaymentAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that file')),
      );
      return;
    }
    if (file.bytes!.lengthInBytes > 15 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a file smaller than 15 MB')),
      );
      return;
    }
    setState(() {
      _paymentAttachment = file;
      _removePaymentAttachment = false;
    });
  }

  Future<void> _createPaymentReceipt() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the payment amount first')),
      );
      return;
    }

    final draft = await showDialog<PaymentReceiptData>(
      context: context,
      builder: (_) => _PaymentReceiptDialog(
        amount: amount,
        paymentDate: _selectedDate,
        paidTo: _descCtrl.text.trim(),
        billNumber: _selectedPurchaseBill?.billNumber ?? '',
        paidBy: 'NEELKANTH GARMENTS',
      ),
    );
    if (!mounted || draft == null) return;

    final bytes = await buildPaymentReceiptPdf(draft);
    if (!mounted) return;
    setState(() {
      _paymentReceiptData = draft;
      _paymentReceiptBytes = bytes;
      _paymentReceiptName =
          '${draft.receiptNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.pdf';
      _removePaymentReceipt = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).value;
    if (user == null) return;

    await _btnCtrl.forward();
    await _btnCtrl.reverse();

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);

    try {
      final existing = widget.existingTransaction;
      String? paymentAttachmentUrl = existing?.paymentAttachmentUrl;
      String? paymentAttachmentName = existing?.paymentAttachmentName;
      String? paymentAttachmentType = existing?.paymentAttachmentType;
      String? paymentReceiptUrl = existing?.paymentReceiptUrl;
      String? paymentReceiptName = existing?.paymentReceiptName;
      final storage = PaymentStorageService();

      // A bill/OB can already be selected in the direct purchase-bill stream
      // while purchaseClientsProvider is still loading. Use the actual target
      // selection as the source of truth so a generated/uploaded receipt is
      // never silently dropped.
      final hasPurchasePaymentTarget =
          _selectedPurchaseBill != null ||
          _isPurchaseObPayment ||
          _isKnownPurchaseClient(ref);

      if (_removePaymentAttachment) {
        paymentAttachmentUrl = null;
        paymentAttachmentName = null;
        paymentAttachmentType = null;
      }
      if (_removePaymentReceipt) {
        paymentReceiptUrl = null;
        paymentReceiptName = null;
      }

      if (_purchaseFeatureEnabled &&
          _type == 'expense' &&
          hasPurchasePaymentTarget) {
        final uploadKey = existing?.transactionId.isNotEmpty == true
            ? existing!.transactionId
            : '${user.uid}_${DateTime.now().microsecondsSinceEpoch}';
        if (_paymentAttachment?.bytes != null) {
          final extension = (_paymentAttachment!.extension ?? '').toLowerCase();
          paymentAttachmentUrl = await storage.uploadPaymentFile(
            bytes: _paymentAttachment!.bytes!,
            cashbookId: existing?.cashbookId ?? user.currentCashbookId!,
            transactionKey: uploadKey,
            fileName: _paymentAttachment!.name,
            contentType: extension == 'pdf'
                ? 'application/pdf'
                : 'image/${extension == 'jpg' ? 'jpeg' : extension}',
            folder: 'purchase_payment_attachments',
          );
          paymentAttachmentName = _paymentAttachment!.name;
          paymentAttachmentType = extension == 'pdf' ? 'pdf' : 'image';
        }
        if (_paymentReceiptBytes != null) {
          paymentReceiptUrl = await storage.uploadPaymentFile(
            bytes: _paymentReceiptBytes!,
            cashbookId: existing?.cashbookId ?? user.currentCashbookId!,
            transactionKey: uploadKey,
            fileName: _paymentReceiptName ?? 'payment_receipt.pdf',
            contentType: 'application/pdf',
            folder: 'purchase_payment_receipts',
          );
          paymentReceiptName = _paymentReceiptName;
        }
      }

      final tx = TransactionEntity(
        transactionId: existing?.transactionId ?? '',
        cashbookId:    existing?.cashbookId ?? user.currentCashbookId!,
        createdBy:     existing?.createdBy ?? user.uid,
        creatorName:   existing?.creatorName ?? user.displayName ?? '',
        createdAt:     _selectedDate,
        amount:        double.parse(_amountCtrl.text.trim()),
        type:          _type,
        category:      _category.toLowerCase(),
        description:   _descCtrl.text.trim(),
        lastEditedBy:  user.uid,
        linkedSaleBillId: _selectedBill?.saleBillId, // ADDED
        linkedPurchaseBillId: _selectedPurchaseBill?.purchaseBillId, // ADDED
        paymentAttachmentUrl: paymentAttachmentUrl,
        paymentAttachmentName: paymentAttachmentName,
        paymentAttachmentType: paymentAttachmentType,
        paymentReceiptUrl: paymentReceiptUrl,
        paymentReceiptName: paymentReceiptName,
      );

      if (existing != null) {
        await ref.read(transactionRepositoryProvider).updateTransaction(
          tx,
          previous: existing,
        );

        // Remove replaced/cleared files only after the Firestore edit succeeds.
        // This avoids deleting the old document if the transaction update is
        // rejected or temporarily offline.
        if (existing.paymentAttachmentUrl != paymentAttachmentUrl) {
          await storage.deletePaymentFile(existing.paymentAttachmentUrl);
        }
        if (existing.paymentReceiptUrl != paymentReceiptUrl) {
          await storage.deletePaymentFile(existing.paymentReceiptUrl);
        }
      } else if (_category == 'CB' &&
          !(_purchaseFeatureEnabled &&
              _type == 'expense' &&
              (_selectedPurchaseBill != null ||
                  _isPurchaseObPayment ||
                  _isKnownPurchaseClient(ref)))) {
        await ref.read(transactionRepositoryProvider).addTransaction(tx);
      } else if (_type == 'income' && _selectedBill != null) {
        await ref.read(saleBillActionsProvider.notifier).recordPaymentWithOverflow(
          cashbookId:     tx.cashbookId,
          selectedBillId: _selectedBill!.saleBillId,
          partyName:      _selectedBill!.partyName,
          totalAmount:    tx.amount,
          description:    tx.description,
          category:       tx.category,
          createdBy:      tx.createdBy,
          createdByName:  tx.creatorName,
          createdAt:      tx.createdAt,
        );
      } else if (_type == 'income' && _isObPayment) {
        await ref.read(saleBillActionsProvider.notifier).recordObPaymentWithOverflow(
          cashbookId:    tx.cashbookId,
          partyName:     _descCtrl.text.trim(),
          totalAmount:   tx.amount,
          description:   tx.description,
          category:      tx.category,
          createdBy:     tx.createdBy,
          createdByName: tx.creatorName,
          createdAt:     tx.createdAt,
        );
      } else if (_purchaseFeatureEnabled && _type == 'expense' && _selectedPurchaseBill != null) {
        // ADDED: purchase-side mirror of the sales bill payment branch above.
        // Gated behind _purchaseFeatureEnabled to keep purchase routing
        // contained in this feature.
        await ref.read(purchaseBillActionsProvider.notifier).recordPaymentWithOverflow(
          cashbookId:     tx.cashbookId,
          selectedBillId: _selectedPurchaseBill!.purchaseBillId,
          clientName:     _selectedPurchaseBill!.clientName,
          totalAmount:    tx.amount,
          keepPaymentOnSelectedBill: true,
          description:    tx.description,
          category:       tx.category,
          createdBy:      tx.createdBy,
          createdByName:  tx.creatorName,
          createdAt:      tx.createdAt,
          paymentAttachmentUrl: paymentAttachmentUrl,
          paymentAttachmentName: paymentAttachmentName,
          paymentAttachmentType: paymentAttachmentType,
          paymentReceiptUrl: paymentReceiptUrl,
          paymentReceiptName: paymentReceiptName,
        );
      } else if (_purchaseFeatureEnabled && _type == 'expense' && _isPurchaseObPayment) {
        // ADDED: purchase-side mirror of the sales OB payment branch above.
        await ref.read(purchaseBillActionsProvider.notifier).recordObPaymentWithOverflow(
          cashbookId:    tx.cashbookId,
          clientName:    _descCtrl.text.trim(),
          totalAmount:   tx.amount,
          description:   tx.description,
          category:      tx.category,
          createdBy:     tx.createdBy,
          createdByName: tx.creatorName,
          createdAt:     tx.createdAt,
          paymentAttachmentUrl: paymentAttachmentUrl,
          paymentAttachmentName: paymentAttachmentName,
          paymentAttachmentType: paymentAttachmentType,
          paymentReceiptUrl: paymentReceiptUrl,
          paymentReceiptName: paymentReceiptName,
        );
      } else if (_purchaseFeatureEnabled &&
          _type == 'expense' &&
          _partyConfirmed &&
          (_category == 'Wholesale' || _category == 'Bank' || _category == 'UPI') &&
          // Gate: only auto-route when the confirmed party is a known purchase client.
          // purchaseClientsProvider is pre-warmed in build(), so this is a sync read.
          // Only reached when the purchase feature is enabled.
          (ref.read(purchaseClientsProvider).asData?.value ?? []).any(
            (c) => c.clientName.trim().toLowerCase() ==
                _descCtrl.text.trim().toLowerCase(),
          )) {
        // Auto-route: user selected a purchase client but did NOT explicitly
        // pick a bill or OB. Priority:
        //   1. OB pending → credit OB first, overflow FIFO into bills.
        //   2. OB settled, bills pending → FIFO across pending bills.
        //   3. Nothing pending → plain unlinked expense.
        await ref.read(purchaseBillActionsProvider.notifier).recordAutoPayment(
          cashbookId:    tx.cashbookId,
          clientName:    _descCtrl.text.trim(),
          totalAmount:   tx.amount,
          description:   tx.description,
          category:      tx.category,
          createdBy:     tx.createdBy,
          createdByName: tx.creatorName,
          createdAt:     tx.createdAt,
          paymentAttachmentUrl: paymentAttachmentUrl,
          paymentAttachmentName: paymentAttachmentName,
          paymentAttachmentType: paymentAttachmentType,
          paymentReceiptUrl: paymentReceiptUrl,
          paymentReceiptName: paymentReceiptName,
        );
      } else {
        await ref.read(transactionRepositoryProvider).addTransaction(tx);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: _C.expense,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingTransaction != null;
    final bool showBank = kIsWeb || defaultTargetPlatform != TargetPlatform.android;
    // Pre-warm all party sources so data is cached before the picker opens.
    ref.watch(partiesProvider);
    ref.watch(allSaleBillsProvider);
    // ADDED: Android has no purchase feature — never watch (never open) the
    // purchase-clients/purchase-bills Firestore streams there at all.
    if (_purchaseFeatureEnabled) {
      ref.watch(purchaseClientsProvider);
      ref.watch(allPurchaseBillsProvider);
    }
    final hasPurchasePaymentTarget =
        _selectedPurchaseBill != null ||
        _isPurchaseObPayment ||
        _isKnownPurchaseClient(ref);
    final showPurchasePaymentOptions = _purchaseFeatureEnabled &&
        _type == 'expense' &&
        hasPurchasePaymentTarget;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          RepaintBoundary(child: _AmbientGlow(accent: _accentColor)),
          SafeArea(
            child: Column(
              children: [
                _AppBar(
                  onBack: () => Navigator.pop(context),
                  isEditing: isEditing,
                )
                    .animate()
                    .fadeIn(duration: 240.ms)
                    .slideY(begin: -0.06, end: 0, curve: Curves.easeOut),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TypeToggle(type: _type, onSwitch: _switchType)
                              .animate()
                              .fadeIn(delay: 60.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 28),
                          const _FieldLabel('Amount (INR)'),
                          const SizedBox(height: 8),
                          _AmountField(controller: _amountCtrl, accent: _accentColor)
                              .animate()
                              .fadeIn(delay: 110.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          const _FieldLabel('Category'),
                          const SizedBox(height: 8),
                          if (widget.categoryLocked && !isEditing)
                            Builder(builder: (context) {
                              final isUpi       = _category == 'UPI';
                              final isCb        = _category == 'CB';
                              final bgColor     = isUpi ? const Color(0xFF1A0E35) : isCb ? const Color(0xFF1A1200) : const Color(0xFF0E2A1F);
                              final borderColor = isUpi ? const Color(0xFF3D1D8A) : isCb ? const Color(0xFF3D2800) : const Color(0xFF1B4D35);
                              final accentColor = isUpi ? const Color(0xFFA78BFA) : isCb ? const Color(0xFFFBBF24) : const Color(0xFF34D399);
                              final icon        = isUpi ? Icons.currency_rupee_rounded : Icons.account_balance_rounded;
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 14, color: accentColor),
                                    const SizedBox(width: 8),
                                    Text(
                                      _category,
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(delay: 160.ms, duration: 280.ms);
                            })
                          else
                            _CategoryToggle(selected: _category, onSwitch: _switchCategory, showBank: showBank)
                                .animate()
                                .fadeIn(delay: 160.ms, duration: 280.ms)
                                .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 24),
                          const _FieldLabel('Description'),
                          const SizedBox(height: 8),

                          // Income party categories and all supported expense
                          // entries use the picker. It still accepts free text
                          // when no saved party/client is chosen.
                          (_descriptionPickerEnabled
                                  ? _DescTapField(
                                      value: _descCtrl.text,
                                      onTap: _openPartyPicker,
                                      loading: _openingPartyPicker,
                                    )
                                  : _DescriptionTextField(
                                      controller: _descCtrl,
                                    ))
                              .animate()
                              .fadeIn(delay: 210.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),

                          // ADDED: Bill dropdown — only visible once a party name has been confirmed.
                          if (_type == 'income' && _partyConfirmed && (_category == 'Wholesale' || _category == 'Bank' || _category == 'UPI')) ...[
                            if (_loadingBill)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Loading linked bill…',
                                      style: TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              BillNoDropdownField(
                                partyName: _descCtrl.text,
                                selectedBill: _selectedBill,
                                onBillSelected: (bill) =>
                                    setState(() { _selectedBill = bill; _isObPayment = false; }),
                                isObSelected: _isObPayment,
                                onObSelected: () =>
                                    setState(() { _isObPayment = true; _selectedBill = null; }),
                              ),
                          ],

                          // Purchase bill dropdown — every supported expense
                          // category, once a client/name has been confirmed.
                          if (_purchaseFeatureEnabled &&
                              _type == 'expense' &&
                              _partyConfirmed) ...[
                            if (_loadingPurchaseBill)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Loading linked bill…',
                                      style: TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              PurchaseBillNoDropdownField(
                                clientName: _descCtrl.text,
                                selectedBill: _selectedPurchaseBill,
                                onBillSelected: (bill) =>
                                    setState(() { _selectedPurchaseBill = bill; _isPurchaseObPayment = false; }),
                                isObSelected: _isPurchaseObPayment,
                                onObSelected: () =>
                                    setState(() { _isPurchaseObPayment = true; _selectedPurchaseBill = null; }),
                              ),
                          ],
                          if (showPurchasePaymentOptions) ...[
                            const SizedBox(height: 16),
                            const _FieldLabel('Purchase payment documents'),
                            const SizedBox(height: 8),
                            _PurchasePaymentOptions(
                              attachment: _paymentAttachment,
                              receiptData: _paymentReceiptData,
                              existingAttachmentName:
                                  widget.existingTransaction?.paymentAttachmentName,
                              existingAttachmentType:
                                  widget.existingTransaction?.paymentAttachmentType,
                              hasExistingAttachment:
                                  !_removePaymentAttachment &&
                                      (widget.existingTransaction?.paymentAttachmentUrl ?? '')
                                          .isNotEmpty,
                              existingReceiptName:
                                  widget.existingTransaction?.paymentReceiptName,
                              hasExistingReceipt:
                                  !_removePaymentReceipt &&
                                      (widget.existingTransaction?.paymentReceiptUrl ?? '')
                                          .isNotEmpty,
                              onAttach: _pickPaymentAttachment,
                              onCreateReceipt: _createPaymentReceipt,
                              onRemoveAttachment: () =>
                                  setState(() {
                                    _paymentAttachment = null;
                                    _removePaymentAttachment = true;
                                  }),
                              onRemoveReceipt: () => setState(() {
                                _paymentReceiptBytes = null;
                                _paymentReceiptName = null;
                                _paymentReceiptData = null;
                                _removePaymentReceipt = true;
                              }),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const _FieldLabel('Date'),
                          const SizedBox(height: 8),
                          _DatePickerField(
                            selectedDate: _selectedDate,
                            accent: _accentColor,
                            onTap: _pickDate,
                          )
                              .animate()
                              .fadeIn(delay: 245.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 20),
                          // Voice mic — hidden on iOS PWA (MediaRecorder
                          // is unreliable in iOS Safari / home-screen PWA).
                          if (!(kIsWeb && defaultTargetPlatform == TargetPlatform.iOS))
                            _VoiceMicButton(
                              recording:  _voiceRecording,
                              processing: _voiceProcessing,
                              accent:     _accentColor,
                              onTap:      _onVoiceMicTap,
                            )
                                .animate()
                                .fadeIn(delay: 260.ms, duration: 280.ms)
                                .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                          const SizedBox(height: 16),
                          ScaleTransition(
                            scale: _btnScale,
                            child: _SubmitButton(
                              type:       _type,
                              accent:     _accentColor,
                              submitting: _submitting,
                              isEditing:  isEditing,
                              onTap:      _submit,
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 280.ms, duration: 280.ms)
                              .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchasePaymentOptions extends StatelessWidget {
  final PlatformFile? attachment;
  final PaymentReceiptData? receiptData;
  final String? existingAttachmentName;
  final String? existingAttachmentType;
  final bool hasExistingAttachment;
  final String? existingReceiptName;
  final bool hasExistingReceipt;
  final VoidCallback onAttach;
  final VoidCallback onCreateReceipt;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onRemoveReceipt;

  const _PurchasePaymentOptions({
    required this.attachment,
    required this.receiptData,
    this.existingAttachmentName,
    this.existingAttachmentType,
    this.hasExistingAttachment = false,
    this.existingReceiptName,
    this.hasExistingReceipt = false,
    required this.onAttach,
    required this.onCreateReceipt,
    required this.onRemoveAttachment,
    required this.onRemoveReceipt,
  });

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      VoidCallback? onRemove,
    }) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: _C.expense, size: 21),
          title: Text(title,
              style: const TextStyle(
                  color: _C.textPri,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _C.textSec, fontSize: 11)),
          trailing: onRemove == null
              ? const Icon(Icons.chevron_right_rounded, color: _C.textSec)
              : IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded,
                      color: _C.textSec, size: 18),
                ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        ),
      );
    }

    return Column(
      children: [
        tile(
          icon: attachment != null
              ? (attachment!.extension?.toLowerCase() == 'pdf'
                  ? Icons.picture_as_pdf_rounded
                  : Icons.image_rounded)
              : hasExistingAttachment
                  ? (existingAttachmentType == 'pdf'
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded)
                  : Icons.attach_file_rounded,
          title: attachment != null || hasExistingAttachment
              ? 'Payment proof attached'
              : 'Attach payment proof',
          subtitle: attachment?.name ??
              (hasExistingAttachment
                  ? (existingAttachmentName ?? 'Saved payment proof')
                  : 'Upload an image or PDF from your phone'),
          onTap: onAttach,
          onRemove: attachment != null || hasExistingAttachment
              ? onRemoveAttachment
              : null,
        ),
        tile(
          icon: receiptData != null || hasExistingReceipt
              ? Icons.check_circle_outline_rounded
              : Icons.receipt_long_rounded,
          title: receiptData != null || hasExistingReceipt
              ? 'Payment receipt attached'
              : 'Create payment receipt',
          subtitle: receiptData != null
              ? '${receiptData!.receiptNumber} • Tap to edit'
              : hasExistingReceipt
                  ? (existingReceiptName ?? 'Saved receipt PDF')
                  : 'Add payment details and generate a PDF',
          onTap: onCreateReceipt,
          onRemove: receiptData != null || hasExistingReceipt
              ? onRemoveReceipt
              : null,
        ),
      ],
    );
  }
}

class _PaymentReceiptDialog extends StatefulWidget {
  final double amount;
  final DateTime paymentDate;
  final String paidTo;
  final String billNumber;
  final String paidBy;

  const _PaymentReceiptDialog({
    required this.amount,
    required this.paymentDate,
    required this.paidTo,
    required this.billNumber,
    required this.paidBy,
  });

  @override
  State<_PaymentReceiptDialog> createState() => _PaymentReceiptDialogState();
}

class _PaymentReceiptDialogState extends State<_PaymentReceiptDialog> {
  late final TextEditingController _receiptCtrl;
  late final TextEditingController _paidByCtrl;
  late final TextEditingController _paidToCtrl;
  late final TextEditingController _billCtrl;
  late final TextEditingController _methodCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _receiptCtrl = TextEditingController(
        text: 'REC-${DateFormat('yyyyMMddHHmmss').format(DateTime.now())}');
    _paidByCtrl = TextEditingController(text: widget.paidBy);
    _paidToCtrl = TextEditingController(text: widget.paidTo);
    _billCtrl = TextEditingController(text: widget.billNumber);
    _methodCtrl = TextEditingController(text: 'Cash');
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _receiptCtrl.dispose();
    _paidByCtrl.dispose();
    _paidToCtrl.dispose();
    _billCtrl.dispose();
    _methodCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.textSec, fontSize: 13),
      filled: true,
      fillColor: _C.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _C.expense),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: lines,
        style: const TextStyle(color: _C.textPri, fontSize: 13),
        decoration: _decoration(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Create payment receipt',
          style: TextStyle(color: _C.textPri, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('INR ${widget.amount.toStringAsFixed(2)} • '
                '${DateFormat('dd MMM yyyy').format(widget.paymentDate)}',
                style: const TextStyle(color: _C.income, fontSize: 13)),
            const SizedBox(height: 16),
            _field('Receipt number', _receiptCtrl),
            _field('Paid by', _paidByCtrl),
            _field('Paid to', _paidToCtrl),
            _field('Purchase bill number (optional)', _billCtrl),
            _field('Payment method', _methodCtrl),
            _field('Notes (optional)', _notesCtrl, lines: 3),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: _C.textSec)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _C.expense,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (_paidToCtrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              PaymentReceiptData(
                receiptNumber: _receiptCtrl.text.trim().isEmpty
                    ? 'PAYMENT'
                    : _receiptCtrl.text.trim(),
                paidBy: _paidByCtrl.text.trim(),
                paidTo: _paidToCtrl.text.trim(),
                billNumber: _billCtrl.text.trim(),
                amount: widget.amount,
                paymentDate: widget.paymentDate,
                paymentMethod: _methodCtrl.text.trim(),
                notes: _notesCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Generate PDF'),
        ),
      ],
    );
  }
}

// ─── Date picker field ────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  final DateTime selectedDate;
  final Color accent;
  final VoidCallback onTap;

  const _DatePickerField({
    required this.selectedDate,
    required this.accent,
    required this.onTap,
  });

  bool get _isToday {
    final now = DateTime.now();
    return selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final label = _isToday
        ? 'Today'
        : DateFormat('dd MMM yyyy').format(selectedDate);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _C.textPri,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    DateFormat('EEEE').format(selectedDate),
                    style: const TextStyle(
                      color: _C.textSec,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _C.textSec.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ambient glow ─────────────────────────────────────────────────────────────

class _AmbientGlow extends StatelessWidget {
  final Color accent;
  const _AmbientGlow({required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.2,
          colors: [accent.withValues(alpha: 0.07), _C.bg.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}

// ─── App bar ──────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool isEditing;

  const _AppBar({
    required this.onBack,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _IconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
          const SizedBox(width: 14),
          Text(
            isEditing ? 'Edit Entry' : 'New Entry',
            style: const TextStyle(
              color: _C.textPri,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Icon(icon, size: 15, color: _C.textSec),
      ),
    );
  }
}

// ─── Type toggle ──────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final String type;
  final void Function(String) onSwitch;
  const _TypeToggle({required this.type, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          _TypeChip(
            label: 'Income', icon: Icons.south_rounded,
            active: type == 'income', activeColor: _C.income,
            onTap: () => onSwitch('income'),
          ),
          const SizedBox(width: 4),
          _TypeChip(
            label: 'Expense', icon: Icons.north_rounded,
            active: type == 'expense', activeColor: _C.expense,
            onTap: () => onSwitch('expense'),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label, required this.icon, required this.active,
    required this.activeColor, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? activeColor.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: active ? activeColor.withValues(alpha: 0.18) : _C.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 14,
                    color: active ? activeColor : _C.textSec),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  color: active ? activeColor : _C.textSec,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Amount field ─────────────────────────────────────────────────────────────

class _AmountField extends StatefulWidget {
  final TextEditingController controller;
  final Color accent;
  const _AmountField({required this.controller, required this.accent});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? widget.accent.withValues(alpha: 0.5) : _C.border,
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [BoxShadow(
                color: widget.accent.withValues(alpha: 0.08),
                blurRadius: 12, spreadRadius: 0)]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        cursorColor: widget.accent,
        cursorWidth: 1.5,
        style: const TextStyle(
          color: _C.textPri, fontSize: 28,
          fontWeight: FontWeight.w700, letterSpacing: -0.8,
        ),
        decoration: InputDecoration(
          hintText: '0.00',
          hintStyle: const TextStyle(
            color: _C.textMut, fontSize: 28,
            fontWeight: FontWeight.w700, letterSpacing: -0.8,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: _focused ? widget.accent : _C.textSec,
                fontSize: 20, fontWeight: FontWeight.w600,
              ),
              child: const Text('₹'),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: InputBorder.none,
          errorBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          errorStyle: const TextStyle(fontSize: 11, color: _C.expense, height: 0.1),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Enter an amount';
          if (double.tryParse(v.trim()) == null) return 'Invalid number';
          if (double.parse(v.trim()) <= 0) return 'Amount must be greater than 0';
          return null;
        },
      ),
    );
  }
}

// ─── Category toggle ──────────────────────────────────────────────────────────

class _CategoryToggle extends StatelessWidget {
  final String selected;
  final void Function(String) onSwitch;
  final bool showBank;
  const _CategoryToggle({required this.selected, required this.onSwitch, this.showBank = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: ['Retail', 'Wholesale', if (showBank) 'Bank', 'UPI', if (showBank) 'CB'].map((cat) {
          final active = selected == cat;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSwitch(cat),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active ? _C.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? _C.border2 : Colors.transparent,
                  ),
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: active ? _C.textPri : _C.textSec,
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                    child: Text(cat),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DescriptionTextField extends StatelessWidget {
  final TextEditingController controller;

  const _DescriptionTextField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: 1,
      maxLines: 3,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      cursorColor: _C.textPri,
      cursorWidth: 1.5,
      style: const TextStyle(
        color: _C.textPri,
        fontSize: 14,
        height: 1.5,
      ),
      decoration: InputDecoration(
        hintText: 'What was this for?',
        hintStyle: const TextStyle(
          color: _C.textMut,
          fontSize: 14,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 16, right: 12),
          child: Icon(Icons.notes_rounded, size: 17, color: _C.textMut),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 45, minHeight: 52),
        filled: true,
        fillColor: _C.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _C.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _C.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _C.border2),
        ),
      ),
    );
  }
}

// ─── Description tap field ─────────────────────────────────────────────────────
// CHANGED: replaced the inline text field with a tappable display that
// navigates to PartyPickerScreen. This keeps the suggestion list fully
// visible regardless of keyboard height.

class _DescTapField extends StatelessWidget {
  final String value;
  final VoidCallback onTap;
  // ADDED (FIX): when true, shows a small spinner instead of the chevron so
  // the field visibly reacts to a tap while it resolves party/bill data,
  // instead of appearing frozen/unresponsive for up to a few seconds.
  final bool loading;
  const _DescTapField({
    required this.value,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.notes_rounded,
              size: 17,
              color: hasValue ? _C.textSec : _C.textMut,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? value : 'What was this for?',
                style: TextStyle(
                  color: hasValue ? _C.textPri : _C.textMut,
                  fontSize: 14,
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF6B7280),
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _C.textMut,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Voice mic button ─────────────────────────────────────────────────────────
// ADDED: speak-to-fill entry point. Tap once to start recording, tap again to
// stop and send to Groq for transcription + parsing. Purely fills the form
// above — the existing Submit button still does the actual save.

class _VoiceMicButton extends StatelessWidget {
  final bool recording;
  final bool processing;
  final Color accent;
  final VoidCallback onTap;

  const _VoiceMicButton({
    required this.recording,
    required this.processing,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: processing ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 52,
        decoration: BoxDecoration(
          color: recording ? accent.withValues(alpha: 0.14) : const Color(0xFF14161B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: recording ? accent.withValues(alpha: 0.55) : const Color(0xFF23262D),
          ),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: processing
                ? Row(
                    key: const ValueKey('processing'),
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _C.textSec),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Listening to voice…',
                        style: TextStyle(color: _C.textSec, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                : Row(
                    key: ValueKey<bool>(recording),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                        size: 18,
                        color: recording ? accent : _C.textSec,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        recording ? 'Tap to stop & save' : 'Speak to add entry',
                        style: TextStyle(
                          color: recording ? accent : _C.textSec,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Submit button ────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final String type;
  final Color accent;
  final bool submitting;
  final bool isEditing;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.type,
    required this.accent,
    required this.submitting,
    required this.onTap,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: submitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        height: 56,
        decoration: BoxDecoration(
          color: submitting ? _C.border2 : accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: submitting
              ? null
              : [BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: submitting
                ? const SizedBox(
                    key: ValueKey('loader'),
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _C.textSec),
                  )
                : Row(
                    key: ValueKey<String>('$type$isEditing'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isEditing
                            ? Icons.check_rounded
                            : (type == 'income'
                                ? Icons.south_rounded
                                : Icons.north_rounded),
                        size: 16,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditing
                            ? 'Save Changes'
                            : (type == 'income'
                                ? 'Record Income'
                                : 'Record Expense'),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Field label ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _C.textSec,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}
