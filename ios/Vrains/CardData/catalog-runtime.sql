CREATE TABLE IF NOT EXISTS catalog_state (key TEXT PRIMARY KEY,value TEXT NOT NULL);
DROP VIEW IF EXISTS app_cards;
CREATE VIEW app_cards AS
SELECT c.cid,CAST(NULLIF(c.passcode,'') AS INTEGER) AS passcode,
 COALESCE((SELECT name FROM card_localizations WHERE cid=c.cid AND locale='zh-Hans' AND source='official-db'),
 (SELECT NULLIF(trim(name),'') FROM card_localizations WHERE cid=c.cid AND locale='zh-Hans' AND source='ygocdb'),
 (SELECT name FROM card_aliases WHERE cid=c.cid AND source IN ('sc_name','nwbbs_n','jp_name') ORDER BY CASE source WHEN 'sc_name' THEN 0 WHEN 'nwbbs_n' THEN 1 ELSE 2 END LIMIT 1),
 (SELECT name FROM card_localizations WHERE cid=c.cid ORDER BY CASE locale WHEN 'ja' THEN 0 ELSE 1 END LIMIT 1),'') AS name,
 COALESCE((SELECT description FROM card_localizations WHERE cid=c.cid AND description!='' ORDER BY CASE WHEN locale='zh-Hans' AND source='official-db' THEN 0 WHEN source='ygocdb' THEN 1 WHEN locale='ja' THEN 2 ELSE 3 END LIMIT 1),'') AS description,
 COALESCE((SELECT pendulum_description FROM card_localizations WHERE cid=c.cid AND pendulum_description!='' ORDER BY CASE WHEN locale='zh-Hans' AND source='official-db' THEN 0 WHEN source='ygocdb' THEN 1 WHEN locale='ja' THEN 2 ELSE 3 END LIMIT 1),'') AS pendulum_description,
 COALESCE((SELECT type_text FROM card_localizations WHERE cid=c.cid AND type_text!='' ORDER BY CASE WHEN source='ygocdb' THEN 0 ELSE 1 END LIMIT 1),'') AS type_text,
 c.type_bits,CAST(c.race_code AS INTEGER) AS race,CAST(c.attribute_code AS INTEGER) AS attribute,c.level_value AS level,c.level_kind,c.atk,c.defense,c.scale_left AS left_scale,c.scale_right AS right_scale,c.link_markers,c.availability_bits AS ot,NULL AS setcode,
 COALESCE((SELECT series_text FROM card_localizations WHERE cid=c.cid AND series_text!='' LIMIT 1),'') AS series_text FROM cards c;
-- Verified full pack membership does not invent card numbers for printings.
CREATE TABLE IF NOT EXISTS pack_members (
 locale TEXT NOT NULL,pid TEXT NOT NULL,cid INTEGER NOT NULL REFERENCES cards,
 rarity_id TEXT NOT NULL REFERENCES rarities,position INTEGER NOT NULL,
 PRIMARY KEY(locale,pid,cid,rarity_id),FOREIGN KEY(locale,pid) REFERENCES packs
);
CREATE VIEW IF NOT EXISTS app_pack_members AS
 SELECT locale,pid,cid,rarity_id,position FROM pack_members
 UNION ALL
 SELECT p.locale,p.pid,p.cid,p.rarity_id,p.position FROM printings p
 WHERE NOT EXISTS(SELECT 1 FROM pack_members m WHERE m.locale=p.locale AND m.pid=p.pid);

DROP VIEW IF EXISTS app_releases;
CREATE VIEW app_releases AS
 SELECT cid,CASE locale WHEN 'ja' THEN 'jp' WHEN 'cn' THEN 'sc' ELSE locale END AS language,release_date AS date,pack_name AS pack FROM (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY cid,locale ORDER BY release_date IS NULL,release_date,priority) AS rn FROM (
 SELECT p.cid,p.locale,k.release_date,k.name AS pack_name,0 AS priority FROM app_pack_members p JOIN packs k ON k.locale=p.locale AND k.pid=p.pid WHERE NULLIF(k.release_date,'') IS NOT NULL AND (p.locale='ja' OR k.release_date<=date('now','localtime'))
 UNION ALL SELECT cid,locale,release_date,pack_name,1 FROM card_releases WHERE NULLIF(release_date,'') IS NOT NULL AND (locale='ja' OR release_date<=date('now','localtime')))) WHERE rn=1;
CREATE VIEW IF NOT EXISTS app_limits AS
 SELECT e.cid,e.format,e.copies FROM banlist_entries e WHERE e.effective_date=(SELECT max(effective_date) FROM banlists b WHERE b.format=e.format AND completeness='complete' AND effective_date<=date('now','localtime'));
CREATE INDEX IF NOT EXISTS printings_rarity ON printings(rarity_id,cid);
CREATE INDEX IF NOT EXISTS localizations_locale ON card_localizations(locale,cid);
