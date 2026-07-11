# FasoLiv

Livraison collaborative au Burkina Faso — app Flutter (clients + livreurs) avec backend Supabase.

## Fonctionnalités
- Recherche de livreurs proches (GPS)
- Compte livreur (CNIB, abonnement, en ligne)
- Messagerie client ↔ livreur
- Appels, avis / notes
- Notifications (FCM / locales)

## Démarrage
```bash
flutter pub get
flutter run
```

Build Android :
```bash
flutter build apk
```

## Backend
Voir `SUPABASE_SETUP.md` pour les migrations SQL à exécuter dans l’ordre.
