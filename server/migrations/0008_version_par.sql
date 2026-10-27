-- The version's par in points: the par:<points> label at merge, else the sketch's par; NULL when neither.
ALTER TABLE versions ADD COLUMN par INTEGER;
