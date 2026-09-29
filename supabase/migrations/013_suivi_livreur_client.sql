-- =============================================================================
-- Position livreur visible pour le client d'une course active
-- =============================================================================

CREATE OR REPLACE FUNCTION position_livreur_pour_course(p_course_id UUID)
RETURNS TABLE (
  livreur_id UUID,
  lat        DOUBLE PRECISION,
  lng        DOUBLE PRECISION,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_livreur UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT c.livreur_id INTO v_livreur
  FROM courses c
  WHERE c.id = p_course_id
    AND c.livreur_id IS NOT NULL
    AND (c.demandeur_id = v_uid OR c.livreur_id = v_uid)
    AND c.statut NOT IN ('annule');

  IF v_livreur IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    lp.livreur_id,
    ST_Y(lp.position::geometry) AS lat,
    ST_X(lp.position::geometry) AS lng,
    lp.updated_at
  FROM livreur_positions lp
  WHERE lp.livreur_id = v_livreur;
END;
$$;

GRANT EXECUTE ON FUNCTION position_livreur_pour_course(UUID) TO authenticated;
