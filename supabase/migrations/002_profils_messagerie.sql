-- =============================================================================
-- FasoLiv v2 — Profils livreurs enrichis + messagerie + paiement course
-- =============================================================================

-- Véhicule du livreur
DO $$ BEGIN
  CREATE TYPE type_vehicule AS ENUM ('moto', 'tricycle', 'voiture', 'velo');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE statut_paiement AS ENUM ('non_paye', 'en_attente', 'paye', 'rembourse');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- -----------------------------------------------------------------------------
-- Enrichissement profiles (renseignements de base)
-- -----------------------------------------------------------------------------
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS cnib TEXT,
  ADD COLUMN IF NOT EXISTS photo_url TEXT,
  ADD COLUMN IF NOT EXISTS ville TEXT DEFAULT 'Ouagadougou',
  ADD COLUMN IF NOT EXISTS type_vehicule type_vehicule,
  ADD COLUMN IF NOT EXISTS numero_plaque TEXT,
  ADD COLUMN IF NOT EXISTS note_moyenne NUMERIC(3, 2) DEFAULT 5.0
    CHECK (note_moyenne >= 0 AND note_moyenne <= 5),
  ADD COLUMN IF NOT EXISTS est_verifie BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS localisation_active BOOLEAN NOT NULL DEFAULT false;

-- CNIB unique si renseigné (livreurs)
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_cnib_unique
  ON profiles (cnib)
  WHERE cnib IS NOT NULL AND cnib <> '';

COMMENT ON COLUMN profiles.cnib IS 'Numéro CNIB — obligatoire pour les livreurs';
COMMENT ON COLUMN profiles.localisation_active IS 'Le livreur a activé le partage GPS temps réel';

-- CNIB obligatoire pour les livreurs
CREATE OR REPLACE FUNCTION assert_livreur_complet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type_utilisateur = 'livreur' THEN
    IF NEW.cnib IS NULL OR length(trim(NEW.cnib)) < 5 THEN
      RAISE EXCEPTION 'Un livreur doit renseigner son numéro CNIB';
    END IF;
    IF NEW.type_vehicule IS NULL THEN
      RAISE EXCEPTION 'Un livreur doit indiquer son type de véhicule';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assert_livreur_complet ON profiles;
CREATE TRIGGER trg_assert_livreur_complet
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION assert_livreur_complet();

-- -----------------------------------------------------------------------------
-- Paiement course (débloque la messagerie)
-- -----------------------------------------------------------------------------
ALTER TABLE courses
  ADD COLUMN IF NOT EXISTS statut_paiement statut_paiement NOT NULL DEFAULT 'non_paye',
  ADD COLUMN IF NOT EXISTS paye_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS description_colis TEXT;

-- -----------------------------------------------------------------------------
-- TABLE : messages (chat client ↔ livreur après paiement)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  sender_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  contenu     TEXT NOT NULL CHECK (char_length(trim(contenu)) > 0 AND char_length(contenu) <= 2000),
  lu          BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_course ON messages(course_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Lecture / écriture uniquement si participant ET course payée
CREATE OR REPLACE FUNCTION peut_messager(p_course_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM courses c
    WHERE c.id = p_course_id
      AND c.statut_paiement = 'paye'
      AND (c.demandeur_id = auth.uid() OR c.livreur_id = auth.uid())
      AND c.statut NOT IN ('annule')
  );
$$;

DROP POLICY IF EXISTS "Participants lisent les messages" ON messages;
CREATE POLICY "Participants lisent les messages"
  ON messages FOR SELECT
  USING (peut_messager(course_id));

DROP POLICY IF EXISTS "Participants envoient des messages" ON messages;
CREATE POLICY "Participants envoient des messages"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid()
    AND peut_messager(course_id)
  );

DROP POLICY IF EXISTS "Destinataire marque comme lu" ON messages;
CREATE POLICY "Destinataire marque comme lu"
  ON messages FOR UPDATE
  USING (peut_messager(course_id) AND sender_id <> auth.uid())
  WITH CHECK (lu = true);

GRANT EXECUTE ON FUNCTION peut_messager(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- Marquer une course comme payée (débloque le chat)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION marquer_course_payee(p_course_id UUID)
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
    RAISE EXCEPTION 'Seul le demandeur peut confirmer le paiement';
  END IF;

  IF v_course.livreur_id IS NULL THEN
    RAISE EXCEPTION 'Aucun livreur assigné';
  END IF;

  UPDATE courses
  SET
    statut_paiement = 'paye',
    paye_at = now(),
    statut = CASE
      WHEN statut IN ('disponible', 'propose') THEN 'accepte'::statut_course
      ELSE statut
    END
  WHERE id = p_course_id
  RETURNING * INTO v_course;

  RETURN v_course;
END;
$$;

GRANT EXECUTE ON FUNCTION marquer_course_payee(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- Livreurs proches — retourne le profil enrichi (sans CNIB en clair)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_livreurs_proches(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION get_livreurs_proches(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_rayon_km DOUBLE PRECISION DEFAULT 5.0,
  p_type_vehicule type_vehicule DEFAULT NULL
)
RETURNS TABLE (
  livreur_id       UUID,
  nom              TEXT,
  prenom           TEXT,
  telephone        TEXT,
  ville            TEXT,
  type_vehicule    type_vehicule,
  note_moyenne     NUMERIC,
  est_verifie      BOOLEAN,
  photo_url        TEXT,
  distance_km      DOUBLE PRECISION,
  localisation_active BOOLEAN,
  updated_at       TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    lp.livreur_id,
    p.nom,
    p.prenom,
    p.telephone,
    p.ville,
    p.type_vehicule,
    p.note_moyenne,
    p.est_verifie,
    p.photo_url,
    ROUND(
      (ST_Distance(
        lp.position,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
      ) / 1000.0)::numeric,
      2
    )::double precision AS distance_km,
    p.localisation_active,
    lp.updated_at
  FROM livreur_positions lp
  INNER JOIN profiles p ON p.id = lp.livreur_id
  WHERE
    lp.est_disponible = true
    AND p.localisation_active = true
    AND p.type_utilisateur = 'livreur'
    AND (p_type_vehicule IS NULL OR p.type_vehicule = p_type_vehicule)
    AND ST_DWithin(
      lp.position,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_rayon_km * 1000
    )
  ORDER BY distance_km ASC;
$$;

GRANT EXECUTE ON FUNCTION get_livreurs_proches(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, type_vehicule)
  TO anon, authenticated;

-- -----------------------------------------------------------------------------
-- Activer / désactiver la localisation temps réel du livreur
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_localisation_active(p_active BOOLEAN)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_profil  profiles;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  UPDATE profiles
  SET localisation_active = p_active
  WHERE id = v_user_id AND type_utilisateur = 'livreur'
  RETURNING * INTO v_profil;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservé aux livreurs';
  END IF;

  IF NOT p_active THEN
    UPDATE livreur_positions
    SET est_disponible = false
    WHERE livreur_id = v_user_id;
  END IF;

  RETURN v_profil;
END;
$$;

GRANT EXECUTE ON FUNCTION set_localisation_active(BOOLEAN) TO authenticated;

-- Met à jour aussi localisation_active quand on publie une position
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

  UPDATE profiles
  SET localisation_active = true
  WHERE id = v_user_id;

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

-- Realtime : activer dans le dashboard Supabase pour
-- public.livreur_positions et public.messages
-- ALTER PUBLICATION supabase_realtime ADD TABLE livreur_positions;
-- ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- -----------------------------------------------------------------------------
-- Trigger inscription : profil enrichi (CNIB, véhicule…)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type type_utilisateur;
BEGIN
  v_type := COALESCE(
    (NEW.raw_user_meta_data->>'type_utilisateur')::type_utilisateur,
    'demandeur'
  );

  INSERT INTO public.profiles (
    id, nom, prenom, telephone, type_utilisateur,
    cnib, ville, type_vehicule, numero_plaque
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nom', ''),
    COALESCE(NEW.raw_user_meta_data->>'prenom', ''),
    COALESCE(NEW.raw_user_meta_data->>'telephone', NEW.phone, ''),
    v_type,
    NULLIF(NEW.raw_user_meta_data->>'cnib', ''),
    COALESCE(NEW.raw_user_meta_data->>'ville', 'Ouagadougou'),
    NULLIF(NEW.raw_user_meta_data->>'type_vehicule', '')::type_vehicule,
    NULLIF(NEW.raw_user_meta_data->>'numero_plaque', '')
  );
  RETURN NEW;
END;
$$;
