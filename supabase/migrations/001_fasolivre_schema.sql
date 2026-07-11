-- =============================================================================
-- FasoLiv — Schéma Supabase (PostgreSQL + PostGIS)
-- Application de livraison collaborative — Burkina Faso
-- =============================================================================

-- Extension géographique (distance Haversine / ST_DWithin)
CREATE EXTENSION IF NOT EXISTS postgis;

-- -----------------------------------------------------------------------------
-- ENUMS
-- -----------------------------------------------------------------------------
CREATE TYPE type_utilisateur AS ENUM ('demandeur', 'livreur');

CREATE TYPE statut_course AS ENUM (
  'disponible',
  'propose',
  'accepte',
  'recupere',
  'livre',
  'annule'
);

CREATE TYPE type_transaction AS ENUM ('recharge', 'commission', 'gain');

CREATE TYPE statut_transaction AS ENUM (
  'en_attente',
  'reussi',
  'echec',
  'annule'
);

-- -----------------------------------------------------------------------------
-- TABLE : profiles
-- Profil lié à auth.users (1:1)
-- -----------------------------------------------------------------------------
CREATE TABLE profiles (
  id                UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nom               TEXT NOT NULL,
  prenom            TEXT NOT NULL,
  telephone         TEXT NOT NULL UNIQUE,
  type_utilisateur  type_utilisateur NOT NULL,
  solde_portefeuille NUMERIC(12, 2) NOT NULL DEFAULT 0
    CHECK (solde_portefeuille >= 0),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_type ON profiles(type_utilisateur);
CREATE INDEX idx_profiles_telephone ON profiles(telephone);

-- -----------------------------------------------------------------------------
-- TABLE : livreur_positions
-- Position temps réel du livreur (géométrie Point, SRID 4326 = WGS84)
-- -----------------------------------------------------------------------------
CREATE TABLE livreur_positions (
  livreur_id  UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  position    GEOGRAPHY(POINT, 4326) NOT NULL,
  est_disponible BOOLEAN NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Vérifie que seul un profil 'livreur' peut publier une position
CREATE OR REPLACE FUNCTION assert_est_livreur()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = NEW.livreur_id AND p.type_utilisateur = 'livreur'
  ) THEN
    RAISE EXCEPTION 'Seul un compte livreur peut publier une position';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_livreur_positions_assert_livreur
  BEFORE INSERT OR UPDATE ON livreur_positions
  FOR EACH ROW EXECUTE FUNCTION assert_est_livreur();

CREATE INDEX idx_livreur_positions_geo
  ON livreur_positions USING GIST (position);

CREATE INDEX idx_livreur_positions_disponible
  ON livreur_positions (est_disponible)
  WHERE est_disponible = true;

-- -----------------------------------------------------------------------------
-- TABLE : courses
-- -----------------------------------------------------------------------------
CREATE TABLE courses (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  demandeur_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  livreur_id            UUID REFERENCES profiles(id) ON DELETE SET NULL,
  statut                statut_course NOT NULL DEFAULT 'disponible',
  prix_total            NUMERIC(12, 2) NOT NULL CHECK (prix_total >= 0),
  commission            NUMERIC(12, 2) NOT NULL CHECK (commission >= 0),
  adresse_ramassage_gps TEXT NOT NULL,
  adresse_livraison_gps TEXT NOT NULL,
  -- Point géographique optionnel pour le ramassage (filtre livreurs)
  point_ramassage       GEOGRAPHY(POINT, 4326),
  code_otp_validation   TEXT NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT courses_otp_4_chiffres CHECK (code_otp_validation ~ '^\d{4}$'),
  CONSTRAINT courses_livreur_requis_si_accepte CHECK (
    (statut IN ('disponible') AND livreur_id IS NULL)
    OR (statut <> 'disponible')
  )
);

CREATE INDEX idx_courses_demandeur ON courses(demandeur_id);
CREATE INDEX idx_courses_livreur ON courses(livreur_id);
CREATE INDEX idx_courses_statut ON courses(statut);
CREATE INDEX idx_courses_point_ramassage ON courses USING GIST (point_ramassage);

-- -----------------------------------------------------------------------------
-- TABLE : transactions
-- Historique portefeuille / Mobile Money
-- -----------------------------------------------------------------------------
CREATE TABLE transactions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  montant               NUMERIC(12, 2) NOT NULL CHECK (montant > 0),
  type                  type_transaction NOT NULL,
  reference_mobile_money TEXT,
  statut                statut_transaction NOT NULL DEFAULT 'en_attente',
  course_id             UUID REFERENCES courses(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_transactions_user ON transactions(user_id);
CREATE INDEX idx_transactions_statut ON transactions(statut);
CREATE INDEX idx_transactions_reference ON transactions(reference_mobile_money);

-- -----------------------------------------------------------------------------
-- TRIGGER : mise à jour automatique de updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_courses_updated_at
  BEFORE UPDATE ON courses
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_livreur_positions_updated_at
  BEFORE UPDATE ON livreur_positions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------------------------------------------------------
-- TRIGGER : création automatique du profil à l'inscription
-- (métadonnées attendues dans raw_user_meta_data)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, nom, prenom, telephone, type_utilisateur)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nom', ''),
    COALESCE(NEW.raw_user_meta_data->>'prenom', ''),
    COALESCE(NEW.raw_user_meta_data->>'telephone', NEW.phone, ''),
    COALESCE(
      (NEW.raw_user_meta_data->>'type_utilisateur')::type_utilisateur,
      'demandeur'
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- -----------------------------------------------------------------------------
-- FONCTION : livreurs proches (rayon en kilomètres)
-- Utilise ST_DWithin sur GEOGRAPHY (distance en mètres)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_livreurs_proches(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_rayon_km DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
  livreur_id   UUID,
  nom          TEXT,
  prenom       TEXT,
  telephone    TEXT,
  distance_km  DOUBLE PRECISION,
  updated_at   TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT
    lp.livreur_id,
    p.nom,
    p.prenom,
    p.telephone,
    ROUND(
      (ST_Distance(
        lp.position,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0)::numeric,
      2
    )::double precision AS distance_km,
    lp.updated_at
  FROM livreur_positions lp
  INNER JOIN profiles p ON p.id = lp.livreur_id
  WHERE
    lp.est_disponible = true
    AND p.type_utilisateur = 'livreur'
    AND ST_DWithin(
      lp.position,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_rayon_km * 1000  -- mètres
    )
  ORDER BY distance_km ASC;
$$;

-- Exemple d'appel :
-- SELECT * FROM get_livreurs_proches(12.3714, -1.5197, 5);  -- Ouagadougou, 5 km

-- -----------------------------------------------------------------------------
-- FONCTION : publier / mettre à jour la position GPS du livreur connecté
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION upsert_livreur_position(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_disponible BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = v_user_id AND type_utilisateur = 'livreur'
  ) THEN
    RAISE EXCEPTION 'Réservé aux livreurs';
  END IF;

  INSERT INTO livreur_positions (livreur_id, position, est_disponible, updated_at)
  VALUES (
    v_user_id,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_disponible,
    now()
  )
  ON CONFLICT (livreur_id) DO UPDATE
  SET
    position = EXCLUDED.position,
    est_disponible = EXCLUDED.est_disponible,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_livreur_position(DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- FONCTION SÉCURISÉE : accepter une course (vérifie le solde commission)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION accepter_course(p_course_id UUID)
RETURNS courses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_course  courses;
  v_solde   NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO v_course FROM courses WHERE id = p_course_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Course introuvable';
  END IF;

  IF v_course.statut NOT IN ('disponible', 'propose') THEN
    RAISE EXCEPTION 'Cette course n''est plus disponible (statut: %)', v_course.statut;
  END IF;

  IF v_course.livreur_id IS NOT NULL AND v_course.livreur_id <> v_user_id THEN
    RAISE EXCEPTION 'Cette course est déjà proposée à un autre livreur';
  END IF;

  SELECT solde_portefeuille INTO v_solde
  FROM profiles WHERE id = v_user_id FOR UPDATE;

  IF v_solde IS NULL THEN
    RAISE EXCEPTION 'Profil livreur introuvable';
  END IF;

  IF v_solde < v_course.commission THEN
    RAISE EXCEPTION 'SOLDE_INSUFFISANT: solde % < commission %', v_solde, v_course.commission
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE courses
  SET
    livreur_id = v_user_id,
    statut = 'accepte'
  WHERE id = p_course_id
  RETURNING * INTO v_course;

  RETURN v_course;
END;
$$;

-- -----------------------------------------------------------------------------
-- FONCTION SÉCURISÉE : proposer un livreur (côté demandeur)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION proposer_livreur(
  p_course_id UUID,
  p_livreur_id UUID
)
RETURNS courses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_course  courses;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO v_course FROM courses WHERE id = p_course_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Course introuvable';
  END IF;

  IF v_course.demandeur_id <> v_user_id THEN
    RAISE EXCEPTION 'Seul le demandeur peut proposer un livreur';
  END IF;

  IF v_course.statut <> 'disponible' THEN
    RAISE EXCEPTION 'La course n''est plus en statut disponible';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_livreur_id AND type_utilisateur = 'livreur'
  ) THEN
    RAISE EXCEPTION 'Livreur invalide';
  END IF;

  UPDATE courses
  SET
    livreur_id = p_livreur_id,
    statut = 'propose'
  WHERE id = p_course_id
  RETURNING * INTO v_course;

  RETURN v_course;
END;
$$;

-- -----------------------------------------------------------------------------
-- FONCTION SÉCURISÉE : valider la livraison par OTP
-- Débite la commission du portefeuille livreur + enregistre la transaction
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION valider_livraison_otp(
  p_course_id UUID,
  p_code_otp  TEXT
)
RETURNS courses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_course  courses;
  v_solde   NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO v_course FROM courses WHERE id = p_course_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Course introuvable';
  END IF;

  IF v_course.livreur_id <> v_user_id THEN
    RAISE EXCEPTION 'Vous n''êtes pas le livreur assigné à cette course';
  END IF;

  IF v_course.statut NOT IN ('accepte', 'recupere') THEN
    RAISE EXCEPTION 'Statut de course invalide pour validation: %', v_course.statut;
  END IF;

  IF v_course.code_otp_validation <> p_code_otp THEN
    RAISE EXCEPTION 'CODE_OTP_INVALIDE'
      USING ERRCODE = 'P0002';
  END IF;

  -- Débit commission (verrouillage du solde)
  SELECT solde_portefeuille INTO v_solde
  FROM profiles WHERE id = v_user_id FOR UPDATE;

  IF v_solde < v_course.commission THEN
    RAISE EXCEPTION 'SOLDE_INSUFFISANT: impossible de débiter la commission';
  END IF;

  PERFORM set_config('app.bypass_solde_guard', 'on', true);
  UPDATE profiles
  SET solde_portefeuille = solde_portefeuille - v_course.commission
  WHERE id = v_user_id;

  INSERT INTO transactions (user_id, montant, type, statut, course_id)
  VALUES (v_user_id, v_course.commission, 'commission', 'reussi', p_course_id);

  UPDATE courses
  SET statut = 'livre'
  WHERE id = p_course_id
  RETURNING * INTO v_course;

  -- Le livreur redevient disponible
  UPDATE livreur_positions
  SET est_disponible = true
  WHERE livreur_id = v_user_id;

  RETURN v_course;
END;
$$;

-- -----------------------------------------------------------------------------
-- FONCTION SÉCURISÉE : créditer le portefeuille après recharge Mobile Money
-- À appeler depuis un webhook Edge Function (service_role), pas depuis le client
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crediter_portefeuille(
  p_user_id UUID,
  p_montant NUMERIC,
  p_reference TEXT
)
RETURNS transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx transactions;
BEGIN
  IF p_montant <= 0 THEN
    RAISE EXCEPTION 'Montant invalide';
  END IF;

  -- Évite les doubles crédits sur la même référence
  IF EXISTS (
    SELECT 1 FROM transactions
    WHERE reference_mobile_money = p_reference
      AND statut = 'reussi'
  ) THEN
    RAISE EXCEPTION 'Référence déjà traitée';
  END IF;

  PERFORM set_config('app.bypass_solde_guard', 'on', true);
  UPDATE profiles
  SET solde_portefeuille = solde_portefeuille + p_montant
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Utilisateur introuvable';
  END IF;

  INSERT INTO transactions (
    user_id, montant, type, reference_mobile_money, statut
  )
  VALUES (p_user_id, p_montant, 'recharge', p_reference, 'reussi')
  RETURNING * INTO v_tx;

  RETURN v_tx;
END;
$$;

-- -----------------------------------------------------------------------------
-- RLS (Row Level Security)
-- -----------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE livreur_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Helper pour éviter la récursion RLS (profiles → profiles)
CREATE OR REPLACE FUNCTION public.est_demandeur()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND type_utilisateur = 'demandeur'
  );
$$;

GRANT EXECUTE ON FUNCTION public.est_demandeur() TO authenticated, anon;

-- profiles
CREATE POLICY "Lecture de son propre profil"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Les demandeurs voient les profils livreurs"
  ON profiles FOR SELECT
  USING (
    type_utilisateur = 'livreur'
    AND public.est_demandeur()
  );

CREATE POLICY "Insertion de son propre profil"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Mise à jour de son propre profil"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Empêche la modification client du solde (réservé aux fonctions SECURITY DEFINER)
CREATE OR REPLACE FUNCTION protege_solde_portefeuille()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.solde_portefeuille IS DISTINCT FROM OLD.solde_portefeuille
     AND current_setting('role', true) <> 'service_role' THEN
    -- Autorise uniquement si appelé depuis une fonction SECURITY DEFINER
    -- (session_user reste le rôle DB ; on compare via txid / context app)
    IF NOT (
      current_setting('app.bypass_solde_guard', true) = 'on'
    ) THEN
      RAISE EXCEPTION 'Modification directe du solde interdite';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protege_solde
  BEFORE UPDATE OF solde_portefeuille ON profiles
  FOR EACH ROW EXECUTE FUNCTION protege_solde_portefeuille();

-- livreur_positions
CREATE POLICY "Livreur gère sa position"
  ON livreur_positions FOR ALL
  USING (auth.uid() = livreur_id)
  WITH CHECK (auth.uid() = livreur_id);

CREATE POLICY "Demandeurs lisent les positions disponibles"
  ON livreur_positions FOR SELECT
  USING (
    est_disponible = true
    AND public.est_demandeur()
  );

-- courses
CREATE POLICY "Demandeur voit ses courses"
  ON courses FOR SELECT
  USING (auth.uid() = demandeur_id);

CREATE POLICY "Livreur voit ses courses assignées"
  ON courses FOR SELECT
  USING (auth.uid() = livreur_id);

CREATE POLICY "Livreur voit les courses disponibles"
  ON courses FOR SELECT
  USING (statut = 'disponible');

CREATE POLICY "Demandeur crée une course"
  ON courses FOR INSERT
  WITH CHECK (auth.uid() = demandeur_id);

CREATE POLICY "Demandeur met à jour ses courses"
  ON courses FOR UPDATE
  USING (auth.uid() = demandeur_id);

CREATE POLICY "Livreur met à jour ses courses assignées"
  ON courses FOR UPDATE
  USING (auth.uid() = livreur_id);

-- transactions
CREATE POLICY "Utilisateur voit ses transactions"
  ON transactions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Utilisateur crée une transaction en_attente (recharge)"
  ON transactions FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND type = 'recharge'
    AND statut = 'en_attente'
  );

-- -----------------------------------------------------------------------------
-- Droits d'exécution des fonctions RPC
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION get_livreurs_proches(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION)
  TO authenticated;

GRANT EXECUTE ON FUNCTION accepter_course(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION proposer_livreur(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION valider_livraison_otp(UUID, TEXT) TO authenticated;

-- crediter_portefeuille : réservé au service_role (Edge Function / webhook)
REVOKE ALL ON FUNCTION crediter_portefeuille(UUID, NUMERIC, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION crediter_portefeuille(UUID, NUMERIC, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION crediter_portefeuille(UUID, NUMERIC, TEXT) TO service_role;
