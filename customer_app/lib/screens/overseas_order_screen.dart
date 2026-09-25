/// Shop-and-deliver — a real request form, answered by a real person.
///
/// ## What this actually is
///
/// Not shipping. A person living abroad asks us to shop for their family
/// **inside Jamaica** — we go to a local supermarket or hardware store, buy
/// what they asked for, and deliver it to their relative's door. No carrier,
/// no customs, no freight: a local errand paid for from overseas.
///
/// ## What was here before
///
/// First a `WebView` pointed at `https://tally.so/r/shipeast`, falling back to
/// `https://form.jotform.com/shipeast`. Neither is a form this project owns.
/// The screen contained **zero** Firestore writes, so even in the best case —
/// a form that loaded — nothing reached the system. In the actual case both
/// URLs fail, the customer sees "Connection Error", and a person who wanted to
/// buy groceries for family in Jamaica is told the internet is broken.
///
/// ## What it is now
///
/// A structured request. The customer describes what to buy and where to
/// deliver it; it is written to `overseasInquiries`; the admin panel has a
/// page for them where an operator works the queue and moves the status; the
/// customer sees that status move here. No price is quoted and no payment is
/// taken, because the total depends on the store and what the goods cost on
/// the day. Quoting one up front anyway would be a promise the business cannot
/// keep.
///
/// So the promise on this screen is exactly the one the business can keep:
/// tell us what to buy, and a person will come back to you with the total.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/overseas_inquiry.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_app_bar.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_card.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';

class OverseasOrderScreen extends StatefulWidget {
  const OverseasOrderScreen({super.key});

  @override
  State<OverseasOrderScreen> createState() => _OverseasOrderScreenState();
}

class _OverseasOrderScreenState extends State<OverseasOrderScreen> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _origin = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientAddress = TextEditingController();
  final _description = TextEditingController();
  final _store = TextEditingController();
  final _budget = TextEditingController();
  final _notes = TextEditingController();

  String _parish = '';
  String _category = '';
  bool _submitting = false;

  /// Populated only after a successful write, and shown instead of the form.
  /// A confirmation that appears before the write lands is the original defect.
  String? _submittedId;

  /// Empty until the customer taps submit. Errors that appear while somebody is
  /// still typing the first field read as nagging, not help.
  Map<String, String> _errors = const {};

  static const LinearGradient _oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E9488), Color(0xFF0B6E66)],
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    // Pre-filled from the signed-in account. Most people want to be reached on
    // the details they already gave us, and retyping them is friction with no
    // purpose — but both stay editable, because the person paying is not
    // always the person to call about the request.
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) _email.text = user!.email!;
    if (user?.phoneNumber != null) _phone.text = user!.phoneNumber!;
  }

  @override
  void dispose() {
    for (final c in [
      _email,
      _phone,
      _origin,
      _recipientName,
      _recipientPhone,
      _recipientAddress,
      _description,
      _store,
      _budget,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  OverseasInquiryDraft get _draft => OverseasInquiryDraft(
        contactEmail: _email.text,
        contactPhone: _phone.text,
        originCountry: _origin.text,
        recipientName: _recipientName.text,
        recipientPhone: _recipientPhone.text,
        recipientAddress: _recipientAddress.text,
        recipientParish: _parish,
        itemCategory: _category,
        itemDescription: _description.text,
        requestedStore: _store.text,
        budgetRaw: _budget.text,
        notes: _notes.text,
      );

  Future<void> _submit() async {
    final draft = _draft;
    final errors = draft.errors();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      SeToast.error(context, 'Check the highlighted fields');
      return;
    }

    setState(() {
      _errors = const {};
      _submitting = true;
    });
    try {
      final id = await FirestoreService.submitOverseasInquiry(draft);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submittedId = id;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // Telling somebody "we'll be in touch" after a failed write is precisely
      // what this screen was rebuilt to stop. Fail out loud.
      SeToast.error(context, 'Could not send that request. Please try again.');
    }
  }

  void _startAnother() {
    setState(() {
      _submittedId = null;
      _errors = const {};
      _recipientName.clear();
      _recipientPhone.clear();
      _recipientAddress.clear();
      _description.clear();
      _budget.clear();
      _notes.clear();
      _parish = '';
      _category = '';
      // Contact details and origin are deliberately kept: the same person is
      // sending the next parcel from the same place.
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          const SeGradientHeader(
            title: 'Send to Family in Jamaica',
            subtitle: 'We shop locally & deliver to them',
            gradient: _oceanGradient,
            trailing: Icon(SeIcons.packages, size: 24, color: Colors.white),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _explainer(),
                  const SizedBox(height: 14),
                  if (_submittedId != null)
                    _confirmation(_submittedId!)
                  else
                    _form(),
                  if (uid != null) ...[
                    const SizedBox(height: 14),
                    _myInquiries(uid),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _explainer() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SeColors.oceanTint,
          borderRadius: SeRadius.all(SeRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SeIcons.info, size: 20, color: SeColors.ocean500),
                const SizedBox(width: 8),
                Text('How this works',
                    style: SeType.title.copyWith(color: SeColors.ocean500)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Living abroad? Tell us what to buy and who to deliver it to in '
              'Jamaica. We shop at a local supermarket or hardware store and '
              'drop it to your family. The total depends on the store and the '
              'day’s prices, so a member of the team will confirm it with you '
              'first — nothing is charged until you agree to it.',
              style: SeType.bodyS.copyWith(color: const Color(0xFF0B6E66)),
            ),
          ],
        ),
      );

  Widget _form() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your request', style: SeType.h3),
            const SizedBox(height: 4),
            Text(
              'Everything here is something we need before we can shop for you.',
              style: SeType.bodyS.copyWith(color: SeColors.ink500),
            ),

            _sectionLabel('Where we reach you'),
            SeTextField(
              controller: _email,
              label: 'Your email',
              hint: 'you@example.com',
              icon: SeIcons.envelope,
              keyboardType: TextInputType.emailAddress,
              errorText: _errors['contactEmail'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _phone,
              label: 'Your phone',
              hint: '+1 555 123 4567',
              icon: SeIcons.phone,
              keyboardType: TextInputType.phone,
              errorText: _errors['contactPhone'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _origin,
              label: 'Where you’re based',
              hint: 'City and country, e.g. Brooklyn, USA',
              icon: SeIcons.location,
              errorText: _errors['originCountry'],
            ),

            _sectionLabel('Who receives it in Jamaica'),
            SeTextField(
              controller: _recipientName,
              label: 'Recipient name',
              hint: 'Full name',
              icon: SeIcons.user,
              errorText: _errors['recipientName'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _recipientPhone,
              label: 'Recipient phone',
              hint: '876 000 0000',
              icon: SeIcons.phone,
              keyboardType: TextInputType.phone,
              errorText: _errors['recipientPhone'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _recipientAddress,
              label: 'Delivery address',
              hint: 'Street, town, any landmark',
              icon: SeIcons.location,
              keyboardType: TextInputType.streetAddress,
              minLines: 2,
              maxLines: 3,
              errorText: _errors['recipientAddress'],
            ),
            const SizedBox(height: 14),
            _pickerField(
              label: 'Parish',
              value: _parish,
              hint: 'Choose a parish',
              icon: SeIcons.locationLine,
              options: JamaicaParish.all,
              error: _errors['recipientParish'],
              onPick: (v) => setState(() => _parish = v),
            ),

            _sectionLabel('What to buy'),
            _pickerField(
              label: 'Category',
              value: _category,
              hint: 'Choose a category',
              icon: SeIcons.packages,
              options: OverseasItemCategory.all,
              error: _errors['itemCategory'],
              onPick: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _description,
              label: 'Shopping list',
              hint: 'One item per line, e.g.\n3 tins of ackee\n2 packs of rice\n1 box of milk',
              icon: SeIcons.note,
              minLines: 3,
              maxLines: 6,
              errorText: _errors['itemDescription'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _store,
              label: 'Preferred store (optional)',
              hint: 'e.g. PriceSmart, or “any supermarket”',
              icon: SeIcons.storefront,
              errorText: _errors['requestedStore'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _budget,
              label: 'Approximate budget (optional)',
              hint: 'e.g. J\$10,000 or US\$70',
              icon: SeIcons.scales,
              errorText: _errors['budgetRaw'],
            ),
            const SizedBox(height: 14),
            SeTextField(
              controller: _notes,
              label: 'Anything else (optional)',
              hint: 'Timing, fragile items, questions',
              icon: SeIcons.chat,
              minLines: 2,
              maxLines: 4,
              errorText: _errors['notes'],
            ),

            const SizedBox(height: 12),
            // Said before submitting, so a customer knows what to expect. We
            // buy ordinary retail goods; alcohol, tobacco, prescription drugs
            // and anything a store won't sell us are the exceptions, and it is
            // kinder to say so here than on the phone afterwards.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(SeIcons.info, size: 16, color: SeColors.ocean500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'We shop for everyday supermarket and hardware goods. '
                    'Alcohol, tobacco, prescription medicine and anything a '
                    'store cannot legally sell us are the exceptions — we’ll '
                    'tell you if something on your list is a problem.',
                    style: SeType.bodyS.copyWith(color: SeColors.ink500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SeButton(
              label: _submitting ? 'Sending…' : 'Send Request',
              icon: SeIcons.send,
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      );

  Widget _confirmation(String id) {
    final ref = id.length <= 6 ? id.toUpperCase() : id.substring(0, 6).toUpperCase();
    return SeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: SeColors.successTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(SeIcons.checkCircle,
                    size: 22, color: SeColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Request sent', style: SeType.title),
                    const SizedBox(height: 2),
                    Text(
                      'Reference #$ref. We will reply to '
                      '${_email.text.trim()} with the total.',
                      style: SeType.bodyS.copyWith(color: SeColors.ink500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SeButton(
            label: 'Send Another Request',
            icon: SeIcons.plus,
            variant: SeButtonVariant.secondary,
            onPressed: _startAnother,
          ),
        ],
      ),
    );
  }

  /// The customer's own enquiries and where each one has got to.
  ///
  /// This is the half that makes the admin page mean something: an operator
  /// moving a status is only useful if the person waiting can see it move.
  Widget _myInquiries(String uid) => StreamBuilder<List<OverseasInquiry>>(
        stream: FirestoreService.myOverseasInquiriesStream(uid),
        builder: (context, snap) {
          final list = snap.data ?? const <OverseasInquiry>[];
          if (list.isEmpty) return const SizedBox.shrink();
          return SeCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your requests', style: SeType.h3),
                const SizedBox(height: 10),
                for (final inquiry in list) _inquiryRow(inquiry),
              ],
            ),
          );
        },
      );

  Widget _inquiryRow(OverseasInquiry inquiry) {
    final open = OverseasStatus.isOpen(inquiry.status);
    // SD-4: declined / cancelled / expired all read as "did not happen";
    // `completed` is the one terminal state that is good news.
    final failed = OverseasStatus.isUnsuccessful(inquiry.status);
    final tint = failed
        ? SeColors.dangerTint
        : (open ? SeColors.oceanTint : SeColors.successTint);
    final ink = failed
        ? SeColors.danger
        : (open ? SeColors.ocean500 : SeColors.success);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${inquiry.shortId} · ${inquiry.itemCategory}',
                  style: SeType.title.copyWith(fontSize: 14),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: SeRadius.all(SeRadius.sm),
                ),
                child: Text(
                  OverseasStatus.label(inquiry.status),
                  style: SeType.label.copyWith(color: ink, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'To ${inquiry.recipientName}'
            '${inquiry.recipientParish.isEmpty ? '' : ', ${inquiry.recipientParish}'}',
            style: SeType.bodyS.copyWith(color: SeColors.ink500),
          ),
          const SizedBox(height: 2),
          Text(
            OverseasStatus.explain(inquiry.status),
            style: SeType.bodyS.copyWith(color: SeColors.ink400, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Building blocks ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Text(text.toUpperCase(),
            style: SeType.eyebrow.copyWith(color: SeColors.ink400)),
      );

  /// A read-only field that opens a sheet of choices.
  ///
  /// A dropdown, not a text box: parish and category are joined against fixed
  /// lists on the admin side, and free text there means an operator sorting a
  /// queue by destination misses "St Thomas", "st. thomas" and "StThomas".
  Widget _pickerField({
    required String label,
    required String value,
    required String hint,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String> onPick,
    String? error,
  }) {
    final chosen = value.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SeType.label.copyWith(color: SeColors.ink700)),
        const SizedBox(height: 7),
        InkWell(
          borderRadius: SeRadius.inputRadius,
          onTap: () => _openPicker(label, options, value, onPick),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: SeColors.surface50,
              borderRadius: SeRadius.inputRadius,
              border: Border.all(
                color: error != null ? SeColors.danger : SeColors.ink200,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: SeColors.ink400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chosen ? value : hint,
                    style: SeType.body.copyWith(
                      color: chosen ? SeColors.ink900 : SeColors.ink400,
                    ),
                  ),
                ),
                const Icon(SeIcons.caretDown, size: 20, color: SeColors.ink400),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error,
                style: SeType.bodyS.copyWith(color: SeColors.danger)),
          ),
      ],
    );
  }

  void _openPicker(
    String title,
    List<String> options,
    String current,
    ValueChanged<String> onPick,
  ) {
    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          top: 4,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: 8),
            Text(title, style: SeType.h3),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: options.map((option) {
                    final selected = option == current;
                    return InkWell(
                      onTap: () {
                        onPick(option);
                        Navigator.pop(ctx);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          children: [
                            Icon(
                              selected ? SeIcons.checkCircle : SeIcons.radioOff,
                              size: 20,
                              color: selected
                                  ? SeColors.ocean500
                                  : SeColors.ink300,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(option, style: SeType.body),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
