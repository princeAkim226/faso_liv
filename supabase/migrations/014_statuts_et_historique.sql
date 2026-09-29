-- =============================================================================
-- Statuts course : En route / Sur place + historique
-- =============================================================================

-- Avance le statut (livreur) et envoie un message système dans le chat
CREATE OR REPLACE FUNCTION avancer_statut_course(
  p_course_id UUID,
  p_nouveau_statut TEXT
)
RETURNS courses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     UUID := auth.uid();
  v_course  courses;
  v_msg     TEXT;
  v_next    statut_course;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF p_nouveau_statut NOT IN ('accepte', 'recupere') THEN
    RAISE EXCEPTION 'Statut non autorisé';
  END IF;

  v_next := p_nouveau_statut::statut_course;

  SELECT * INTO v_course
  FROM courses
  WHERE id = p_course_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Course introuvable';
  END IF;

  IF v_course.livreur_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Seul le livreur assigné peut changer le statut';
  END IF;

  IF v_course.statut = 'annule' OR v_course.statut = 'livre' THEN
    RAISE EXCEPTION 'Course terminée ou annulée';
  END IF;

  -- Transitions autorisées
  IF v_next = 'accepte' THEN
    IF v_course.statut NOT IN ('propose', 'accepte') THEN
      RAISE EXCEPTION 'Passage En route impossible depuis %', v_course.statut;
    END IF;
    v_msg := '🚚 Je suis en route vers vous.';
  ELSIF v_next = 'recupere' THEN
    IF v_course.statut NOT IN ('propose', 'accepte', 'recupere') THEN
      RAISE EXCEPTION 'Passage Sur place impossible depuis %', v_course.statut;
    END IF;
    v_msg := '📍 Je suis sur place.';
  END IF;

  UPDATE courses
  SET statut = v_next
  WHERE id = p_course_id
  RETURNING * INTO v_course;

  INSERT INTO messages (course_id, sender_id, contenu)
  VALUES (p_course_id, v_uid, v_msg);

  RETURN v_course;
END;
$$;

GRANT EXECUTE ON FUNCTION avancer_statut_course(UUID, TEXT) TO authenticated;

-- Historique des courses (client ou livreur)
CREATE OR REPLACE FUNCTION mes_courses_historique()
RETURNS TABLE (
  course_id        UUID,
  statut           statut_course,
  livreur_id       UUID,
  demandeur_id     UUID,
  interlocuteur_nom TEXT,
  interlocuteur_prenom TEXT,
  interlocuteur_telephone TEXT,
  adresse_ramassage_gps TEXT,
  created_at       TIMESTAMPTZ,
  prix_total       NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id AS course_id,
    c.statut,
    c.livreur_id,
    c.demandeur_id,
    CASE
      WHEN c.demandeur_id = auth.uid() THEN COALESCE(pl.nom, '')
      ELSE COALESCE(pd.nom, '')
    END AS interlocuteur_nom,
    CASE
      WHEN c.demandeur_id = auth.uid() THEN COALESCE(pl.prenom, '')
      ELSE COALESCE(pd.prenom, '')
    END AS interlocuteur_prenom,
    CASE
      WHEN c.demandeur_id = auth.uid() THEN COALESCE(pl.telephone, '')
      ELSE COALESCE(pd.telephone, '')
    END AS interlocuteur_telephone,
    c.adresse_ramassage_gps,
    c.created_at,
    c.prix_total
  FROM courses c
  LEFT JOIN profiles pl ON pl.id = c.livreur_id
  LEFT JOIN profiles pd ON pd.id = c.demandeur_id
  WHERE auth.uid() IS NOT NULL
    AND (c.demandeur_id = auth.uid() OR c.livreur_id = auth.uid())
  ORDER BY c.created_at DESC
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION mes_courses_historique() TO authenticated;
