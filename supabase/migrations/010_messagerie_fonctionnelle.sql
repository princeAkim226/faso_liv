-- =============================================================================
-- Messagerie fonctionnelle (Realtime + envoi fiable + listes)
-- =============================================================================

-- S'assurer que le chat est ouvert dès qu'un livreur est assigné
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

GRANT EXECUTE ON FUNCTION peut_messager(UUID) TO authenticated;

-- Envoi via RPC (évite les pièges RLS INSERT + SELECT)
CREATE OR REPLACE FUNCTION envoyer_message(
  p_course_id UUID,
  p_contenu TEXT
)
RETURNS messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_msg     messages;
  v_texte   TEXT := trim(COALESCE(p_contenu, ''));
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  IF char_length(v_texte) = 0 THEN
    RAISE EXCEPTION 'Message vide';
  END IF;

  IF char_length(v_texte) > 2000 THEN
    RAISE EXCEPTION 'Message trop long (max 2000)';
  END IF;

  IF NOT peut_messager(p_course_id) THEN
    RAISE EXCEPTION 'Messagerie non autorisée pour cette course';
  END IF;

  INSERT INTO messages (course_id, sender_id, contenu)
  VALUES (p_course_id, v_user_id, v_texte)
  RETURNING * INTO v_msg;

  RETURN v_msg;
END;
$$;

GRANT EXECUTE ON FUNCTION envoyer_message(UUID, TEXT) TO authenticated;

-- Liste des courses avec messagerie pour l'utilisateur connecté
CREATE OR REPLACE FUNCTION mes_conversations()
RETURNS TABLE (
  course_id        UUID,
  statut           statut_course,
  livreur_id       UUID,
  demandeur_id     UUID,
  interlocuteur_nom TEXT,
  interlocuteur_prenom TEXT,
  interlocuteur_telephone TEXT,
  dernier_message  TEXT,
  dernier_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ
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
      WHEN c.demandeur_id = auth.uid() THEN pl.nom
      ELSE pd.nom
    END AS interlocuteur_nom,
    CASE
      WHEN c.demandeur_id = auth.uid() THEN pl.prenom
      ELSE pd.prenom
    END AS interlocuteur_prenom,
    CASE
      WHEN c.demandeur_id = auth.uid() THEN pl.telephone
      ELSE pd.telephone
    END AS interlocuteur_telephone,
    (
      SELECT m.contenu
      FROM messages m
      WHERE m.course_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ) AS dernier_message,
    (
      SELECT m.created_at
      FROM messages m
      WHERE m.course_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ) AS dernier_at,
    c.created_at
  FROM courses c
  LEFT JOIN profiles pl ON pl.id = c.livreur_id
  LEFT JOIN profiles pd ON pd.id = c.demandeur_id
  WHERE c.livreur_id IS NOT NULL
    AND c.statut <> 'annule'
    AND (c.demandeur_id = auth.uid() OR c.livreur_id = auth.uid())
  ORDER BY COALESCE(
    (
      SELECT m.created_at
      FROM messages m
      WHERE m.course_id = c.id
      ORDER BY m.created_at DESC
      LIMIT 1
    ),
    c.created_at
  ) DESC;
$$;

GRANT EXECUTE ON FUNCTION mes_conversations() TO authenticated;

-- Realtime pour le chat (ignorer si déjà ajouté)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;
