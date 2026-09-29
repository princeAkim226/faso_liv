# FasoLiv — Connexion Supabase (checklist)

Projet : `https://jlwjzlrdgkcmpnhzhmju.supabase.co`

## Déjà fait dans l'app
- URL + clé publishable configurées dans `lib/core/config/supabase_config.dart`

## À faire dans le dashboard Supabase

### 1. Exécuter les migrations SQL (dans l'ordre)
SQL Editor → New query → coller et Run :

1. `supabase/migrations/001_fasolivre_schema.sql`
2. `supabase/migrations/002_profils_messagerie.sql`
3. `supabase/migrations/003_cnib_upload_guest.sql`
4. `supabase/migrations/004_cnib_sans_numero.sql`
5. `supabase/migrations/005_telephone_verifie.sql`
6. `supabase/migrations/006_fix_rls_profiles_recursion.sql`
7. `supabase/migrations/007_livreurs_proches_invites.sql`
8. `supabase/migrations/008_abonnement_mensuel.sql`
9. `supabase/migrations/009_chat_et_avis.sql`
10. `supabase/migrations/010_messagerie_fonctionnelle.sql`
11. `supabase/migrations/011_avis_visibles_livreur.sql` ← le livreur voit ses notes
12. `supabase/migrations/012_notifications_push.sql` ← notif quand le livreur est choisi
13. `supabase/migrations/013_suivi_livreur_client.sql` ← client voit le livreur sur la carte
14. `supabase/migrations/014_statuts_et_historique.sql` ← En route / Sur place + historique


### Notation
- Le client note 1–5 ★ (+ commentaire optionnel) dans le chat
- La moyenne du livreur est recalculée en base
- Le livreur reçoit une alerte « nouvel avis » et la liste dans **Mes notes**

### Notifications push (livreur choisi hors-app)

Quand un client choisit un livreur :
1. Une ligne est créée dans `notifications` (Realtime → notif locale si l’app tourne)
2. L’app appelle l’Edge Function `notify-livreur` → FCM (app tuée)

**À configurer une fois :**

1. Créer un projet Firebase (Android, package `com.example.faso_liv`)
2. Télécharger `google-services.json` → le placer dans `android/app/`
3. Firebase Console → Compte de service → générer une clé JSON (Admin SDK)
4. Déployer la fonction et le secret (FCM HTTP v1) :
   ```bash
   # PowerShell — ne jamais committer le fichier JSON
   $json = Get-Content "$env:USERPROFILE\Downloads\fasoliv-fe0f7-XXXX.json" -Raw
   supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$json"
   supabase functions deploy notify-livreur
   ```
5. Realtime : ajouter la table `notifications` à `supabase_realtime` (la migration 012 le tente déjà)

Sans Firebase, le livreur est quand même alerté **si l’app est ouverte ou en arrière-plan** (Realtime + notif locale).

> ⚠️ Le fichier `fasoliv-fe0f7-….json` est une **clé privée**. Ne le mets jamais sur GitHub.

### 2. Auth — confirmation email
Authentication → Providers → Email :
- **Désactiver** « Confirm email »  
  (sinon les comptes téléphone techniques `…@users.fasoliv.bf` restent bloqués)

### 3. Auth — SMS (optionnel pour commencer)
Authentication → Providers → Phone :
- Activer Phone + configurer Twilio / MessageBird / etc.
- Sans ça, le code démo `123456` reste utilisable

### 4. Storage
Le bucket `cnib-docs` est créé par la migration 003.  
Vérifier : Storage → `cnib-docs` existe.

### 5. Realtime (messagerie / positions)
Database → Replication (ou Publications) :
- Ajouter `messages` et `livreur_positions` à `supabase_realtime`

## Pas besoin pour l'instant
- Clé `service_role` (ne jamais la mettre dans Flutter)
- Google Maps API (liste + GPS suffisent pour le MVP)
