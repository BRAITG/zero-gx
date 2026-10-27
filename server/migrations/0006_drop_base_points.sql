-- The score formula no longer adds a constant 1000, so stored scores drop by it too; the floor stays at 100.
UPDATE scores SET points = MAX(100, points - 1000);

-- Every ranking total included that base once per level. The scheduled run rebuilds the table from the scores, so clear it instead of guessing the totals.
DELETE FROM player_ranking;
