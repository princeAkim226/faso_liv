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

## API d’interconnexion Sôôma

Service Node dans `api/` (base PostgreSQL dédiée `faso_liv`, utilisateur `faso_liv_app`).

| URL | Rôle |
|-----|------|
| https://fasoliv.raaga-bf.com | API courses |
| https://dl.fasoliv.raaga-bf.com | Page + APK + `version.json` |

Auth restaurants : en-tête `X-Sooma-Key` (valeur dans Coolify, variable `SOOMA_API_KEY`, projet FasoLiv). Ne pas la committer.

```bash
curl -s https://fasoliv.raaga-bf.com/health

curl -s -X POST https://fasoliv.raaga-bf.com/v1/jobs \
  -H "content-type: application/json" \
  -H "X-Sooma-Key: $SOOMA_API_KEY" \
  -d "{\"externalId\":\"cmd-1\",\"restaurant\":{\"name\":\"Sôôma\",\"phone\":\"+22600000000\",\"address\":\"Ouaga\",\"lat\":12.37,\"lng\":-1.52},\"client\":{\"name\":\"Awa\",\"phone\":\"+22670000000\",\"address\":\"Patte d'oie\",\"lat\":12.39,\"lng\":-1.49},\"feeXof\":1500,\"callbackUrl\":\"https://sooma.raaga-bf.com/api/fasoliv/webhook\"}"
```

`GET /v1/jobs/:jobId` et `GET /v1/jobs/:jobId/track` (trajectoire + `etaMinutes`, ~25 km/h en ville).

Webhooks vers `callbackUrl` : `driver_assigned`, `arrived_restaurant`, `driver_departed`, `location_update` (au plus toutes les 8 s), `delivered`, `failed`, `cancelled`.

Statuts : `searching | assigned | picked_up | in_transit | delivered | cancelled | failed`.

Côté app livreur : icône restaurant → accepter, Arrivé resto, Colis pris, En route, Livré, GPS toutes les 8 s pendant une course active.

Déploiement Coolify : projet séparé **FasoLiv**, Dockerfile `api/Dockerfile`, port 3000. Les bases `postgres`, `sooma`, `syras`, `merveille` et Voltify ne sont pas utilisées.
