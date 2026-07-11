-- Numéro CNIB texte non obligatoire : seules les photos recto/verso comptent
CREATE OR REPLACE FUNCTION assert_livreur_complet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type_utilisateur = 'livreur' THEN
    IF NEW.type_vehicule IS NULL THEN
      RAISE EXCEPTION 'Un livreur doit indiquer son type de véhicule';
    END IF;
    IF NEW.localisation_active = true
       AND (NEW.cnib_recto_url IS NULL OR NEW.cnib_verso_url IS NULL) THEN
      RAISE EXCEPTION 'Téléversez le recto et le verso de votre CNIB avant de passer en ligne';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON COLUMN profiles.cnib IS 'Numéro CNIB texte — optionnel (les photos recto/verso suffisent)';
