import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/app_exceptions.dart';
import '../../core/utils/phone_auth_id.dart';
import '../../models/inscription_livreur_draft.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/cnib_storage_service.dart';
import '../../widgets/brand_widgets.dart';
import '../../widgets/cnib_upload_tile.dart';
import 'sms_otp_screen.dart';

/// Inscription réservée aux livreurs (CNIB recto + verso obligatoires).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _telephone = TextEditingController(text: '+226 ');
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _plaque = TextEditingController();
  TypeVehicule? _vehicule;
  XFile? _recto;
  XFile? _verso;
  bool _cnibManquante = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  final _cnibStorage = CnibStorageService();
  final _cnibKey = GlobalKey();

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _telephone.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _plaque.dispose();
    super.dispose();
  }

  Future<void> _pick(FaceCnib face) async {
    final source = await choisirSourcePhoto(context);
    if (source == null || !mounted) return;
    try {
      final file = await _cnibStorage.choisirImage(source: source);
      if (file == null || !mounted) return;
      setState(() {
        if (face == FaceCnib.recto) {
          _recto = file;
        } else {
          _verso = file;
        }
        if (_recto != null && _verso != null) {
          _cnibManquante = false;
        }
      });
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehicule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez votre véhicule')),
      );
      return;
    }
    if (_recto == null || _verso == null) {
      setState(() => _cnibManquante = true);
      final ctx = _cnibKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.2,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CNIB obligatoire : ajoutez le recto et le verso pour continuer',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _cnibManquante = false);

    // Enregistre le brouillon puis passe à la vérification SMS
    ref.read(inscriptionDraftProvider.notifier).state = InscriptionLivreurDraft(
      password: _password.text,
      nom: _nom.text.trim(),
      prenom: _prenom.text.trim(),
      telephone: _telephone.text.trim(),
      typeVehicule: _vehicule!,
      cnibRecto: _recto!,
      cnibVerso: _verso!,
      numeroPlaque: _plaque.text.isEmpty ? null : _plaque.text.trim(),
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SmsOtpScreen(
          telephone: _telephone.text.trim(),
          pourInscription: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chargement = ref.watch(authProvider).chargement;

    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const BrandMark(compact: true),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profil livreur',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Renseignez vos infos et votre CNIB. '
                          'Un code SMS confirmera ensuite votre compte.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _prenom,
                                decoration:
                                    const InputDecoration(labelText: 'Prénom'),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Requis'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _nom,
                                decoration:
                                    const InputDecoration(labelText: 'Nom'),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Requis'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _telephone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (v) {
                            try {
                              PhoneAuthId.normaliser(v ?? '');
                              return null;
                            } catch (_) {
                              return 'Numéro invalide (+226…)';
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        KeyedSubtree(
                          key: _cnibKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Photos CNIB ',
                                      style: GoogleFonts.dmSans(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '* obligatoire',
                                      style: GoogleFonts.dmSans(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: _cnibManquante
                                            ? AppColors.danger
                                            : AppColors.terre,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _cnibManquante
                                    ? 'Recto et verso requis pour créer le compte.'
                                    : 'Téléversez le recto et le verso de votre pièce d\'identité.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _cnibManquante
                                      ? AppColors.danger
                                      : AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  CnibUploadTile(
                                    label: 'Recto',
                                    hint: 'Face avant',
                                    fichier: _recto,
                                    erreur: _cnibManquante && _recto == null,
                                    onChoisir: () => _pick(FaceCnib.recto),
                                    onEffacer: () => setState(() {
                                      _recto = null;
                                      _cnibManquante = true;
                                    }),
                                  ),
                                  const SizedBox(width: 12),
                                  CnibUploadTile(
                                    label: 'Verso',
                                    hint: 'Face arrière',
                                    fichier: _verso,
                                    erreur: _cnibManquante && _verso == null,
                                    onChoisir: () => _pick(FaceCnib.verso),
                                    onEffacer: () => setState(() {
                                      _verso = null;
                                      _cnibManquante = true;
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Moyen de transport',
                          style:
                              GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: TypeVehicule.values.map((v) {
                            final selected = _vehicule == v;
                            return ChoiceChip(
                              label: Text(v.label),
                              selected: selected,
                              selectedColor:
                                  AppColors.savane.withValues(alpha: 0.2),
                              onSelected: (_) =>
                                  setState(() => _vehicule = v),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _plaque,
                          decoration: const InputDecoration(
                            labelText: 'Plaque (optionnel)',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? '6 caractères min.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordConfirm,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirmer le mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Confirmez le mot de passe';
                            }
                            if (v != _password.text) {
                              return 'Les mots de passe ne correspondent pas';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: chargement ? null : _submit,
                            child: chargement
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Continuer — vérifier mon numéro'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
