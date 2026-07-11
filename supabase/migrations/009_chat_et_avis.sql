-- =============================================================================
-- Chat dès le choix du livreur + avis (étoiles)
-- =============================================================================

-- Messagerie dès qu'un livreur est assigné (plus besoin d'attendre le paiement)
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
      AND c.livreur_id IS NOT NULL
      AND (c.demandeur_id = auth.uid() OR c.livreur_id = auth.uid())
      AND c.statut NOT IN ('annule')
  );
$$;

-- Démarre une course et assigne le livreur en une seule opération
CREATE OR REPLACE FUNCTION demarrer_course_avec_livreur(
  p_livreur_id UUID,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_description TEXT DEFAULT NULL
)
RETURNS courses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_course  courses;
  v_otp     TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = v_user_id AND type_utilisateur = 'demandeur'
  ) THEN
    RAISE EXCEPTION 'Réservé aux clients';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_livreur_id AND type_utilisateur = 'livreur'
  ) THEN
    RAISE EXCEPTION 'Livreur invalide';
  END IF;

  v_otp := lpad((floor(random() * 10000))::int::text, 4, '0');

  INSERT INTO courses (
    demandeur_id,
    livreur_id,
    statut,
    prix_total,
    commission,
    adresse_ramassage_gps,
    adresse_livraison_gps,
    code_otp_validation,
    description_colis,
    point_ramassage
  ) VALUES (
    v_user_id,
    p_livreur_id,
    'propose',
    1000,
    100,
    p_lat::text || ',' || p_lng::text,
    p_lat::text || ',' || p_lng::text,
    v_otp,
    NULLIF(trim(COALESCE(p_description, '')), ''),
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
  )
  RETURNING * INTO v_course;

  RETURN v_course;
END;
$$;

GRANT EXECUTE ON FUNCTION demarrer_course_avec_livreur(
  UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT
) TO authenticated;

-- -----------------------------------------------------------------------------
-- Avis / notation étoiles
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS avis_livreurs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id   UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  auteur_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  livreur_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  note        INT NOT NULL CHECK (note >= 1 AND note <= 5),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT avis_course_unique UNIQUE (course_id)
);

CREATE INDEX IF NOT EXISTS idx_avis_livreur ON avis_livreurs(livreur_id);

ALTER TABLE avis_livreurs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auteur lit ses avis" ON avis_livreurs;
CREATE POLICY "Auteur lit ses avis"
  ON avis_livreurs FOR SELECT
  USING (auteur_id = auth.uid() OR livreur_id = auth.uid());

DROP POLICY IF EXISTS "Client note sa course" ON avis_livreurs;
CREATE POLICY "Client note sa course"
  ON avis_livreurs FOR INSERT
  WITH CHECK (auteur_id = auth.uid());

CREATE OR REPLACE FUNCTION noter_livreur(
  p_course_id UUID,
  p_note INT
)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_course  courses;
  v_profil  profiles;
  v_moyenne NUMERIC;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF p_note < 1 OR p_note > 5 THEN
    RAISE EXCEPTION 'La note doit être entre 1 et 5';
  END IF;

  SELECT * INTO v_course FROM courses WHERE id = p_course_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Course introuvable';
  END IF;

  IF v_course.demandeur_id <> v_user_id THEN
    RAISE EXCEPTION 'Seul le client peut noter le livreur';
  END IF;

  IF v_course.livreur_id IS NULL THEN
    RAISE EXCEPTION 'Aucun livreur à noter';
  END IF;

  IF EXISTS (SELECT 1 FROM avis_livreurs WHERE course_id = p_course_id) THEN
    RAISE EXCEPTION 'Vous avez déjà noté cette course';
  END IF;

  INSERT INTO avis_livreurs (course_id, auteur_id, livreur_id, note)
  VALUES (p_course_id, v_user_id, v_course.livreur_id, p_note);

  SELECT ROUND(AVG(note)::numeric, 2) INTO v_moyenne
  FROM avis_livreurs
  WHERE livreur_id = v_course.livreur_id;

  UPDATE profiles
  SET note_moyenne = COALESCE(v_moyenne, 5.0)
  WHERE id = v_course.livreur_id
  RETURNING * INTO v_profil;

  RETURN v_profil;
END;
$$;

GRANT EXECUTE ON FUNCTION noter_livreur(UUID, INT) TO authenticated;
