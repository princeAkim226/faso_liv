-- =============================================================================
-- Notation réelle : le livreur voit ses avis (+ non lus)
-- =============================================================================

ALTER TABLE avis_livreurs
  ADD COLUMN IF NOT EXISTS lu_par_livreur BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS commentaire TEXT;

COMMENT ON COLUMN avis_livreurs.lu_par_livreur IS
  'false = le livreur n''a pas encore vu cet avis';

-- Recalcule + marque non lu à chaque nouvelle note
CREATE OR REPLACE FUNCTION noter_livreur(
  p_course_id UUID,
  p_note INT,
  p_commentaire TEXT DEFAULT NULL
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

  INSERT INTO avis_livreurs (
    course_id, auteur_id, livreur_id, note, commentaire, lu_par_livreur
  ) VALUES (
    p_course_id,
    v_user_id,
    v_course.livreur_id,
    p_note,
    NULLIF(trim(COALESCE(p_commentaire, '')), ''),
    false
  );

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

-- Retirer l'ancienne signature à 2 args si elle existe (évite conflit)
DROP FUNCTION IF EXISTS noter_livreur(UUID, INT);

GRANT EXECUTE ON FUNCTION noter_livreur(UUID, INT, TEXT) TO authenticated;

-- Liste des avis reçus par le livreur connecté
CREATE OR REPLACE FUNCTION mes_avis_recus()
RETURNS TABLE (
  avis_id          UUID,
  course_id        UUID,
  note             INT,
  commentaire      TEXT,
  lu_par_livreur   BOOLEAN,
  created_at       TIMESTAMPTZ,
  client_prenom    TEXT,
  client_nom       TEXT,
  client_telephone TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    a.id AS avis_id,
    a.course_id,
    a.note,
    a.commentaire,
    a.lu_par_livreur,
    a.created_at,
    p.prenom AS client_prenom,
    p.nom AS client_nom,
    p.telephone AS client_telephone
  FROM avis_livreurs a
  INNER JOIN profiles p ON p.id = a.auteur_id
  WHERE a.livreur_id = auth.uid()
  ORDER BY a.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION mes_avis_recus() TO authenticated;

CREATE OR REPLACE FUNCTION nombre_avis_non_lus()
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INT
  FROM avis_livreurs
  WHERE livreur_id = auth.uid()
    AND lu_par_livreur = false;
$$;

GRANT EXECUTE ON FUNCTION nombre_avis_non_lus() TO authenticated;

CREATE OR REPLACE FUNCTION marquer_avis_comme_lus()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE avis_livreurs
  SET lu_par_livreur = true
  WHERE livreur_id = auth.uid()
    AND lu_par_livreur = false;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION marquer_avis_comme_lus() TO authenticated;

-- Realtime avis (optionnel)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.avis_livreurs;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;
