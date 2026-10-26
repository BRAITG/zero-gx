-- The version's thumbnail sketch: the text of levels/<id>/v<N>.sketch.json at merge; NULL when the version has none.
ALTER TABLE versions ADD COLUMN sketch TEXT;
