import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/phone_auth_id.dart';
import '../../core/utils/session_prefs.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/brand_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _telephone = TextEditingController(text: '+226 ');
  final _password = TextEditingController();
  bool _obscure = true;
  bool _resterConnecte = true;

  @override
  void initState() {
    super.initState();
    _chargerPrefs();
  }

  Future<void> _chargerPrefs() async {
    final tel = await SessionPrefs.lireTelephone();
    final rester = await SessionPrefs.resterConnecte();
    if (!mounted) return;
    setState(() {
      _resterConnecte = rester;
      if (tel != null && tel.isNotEmpty) {
        _telephone.text = tel;
      }
    });
  }

  @override
  void dispose() {
    _telephone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await SessionPrefs.setResterConnecte(_resterConnecte);
    await SessionPrefs.sauverTelephone(_telephone.text);
    final ok = await ref.read(authProvider.notifier).connexion(
          telephone: _telephone.text,
          password: _password.text,
        );
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(authProvider).erreur;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'Échec de connexion'),
          backgroundColor: AppColors.danger,
        ),
      );
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chargement = ref.watch(authProvider).chargement;

    return Scaffold(
      body: FasoBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const BrandMark(compact: true),
                  const SizedBox(height: 28),
                  const Text(
                    'Connexion livreur',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Téléphone et mot de passe. La session reste active '
                    'pour vous reconnecter sans ressaisir.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 6) ? '6 caractères min.' : null,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _resterConnecte,
                    onChanged: (v) =>
                        setState(() => _resterConnecte = v ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Rester connecté',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Rouvrir l\'app sans ressaisir le mot de passe',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                          : const Text('Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
