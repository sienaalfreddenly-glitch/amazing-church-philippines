-- Verses a visitor may be shown.
--
-- Curated rather than exhaustive, and deliberately so. These are references
-- widely read as speaking about being loved, accepted, welcomed or not
-- condemned. Tagging is an editorial judgement about theme, not a claim that
-- every verse here carries identical theological weight, and the list is meant
-- to be extended.
--
-- Matching is by reference, so a verse only gets tagged once it exists in
-- daily_verses. Running this again after a fuller import picks up whatever was
-- missing, which is why it is written as an idempotent insert from a values
-- list rather than as fixed ids.
--
-- TO EXTEND: add rows below and re-run. To add a new topic, insert it into
-- verse_topic_kinds first and set visitor_safe according to whether a stranger
-- to the church should meet that idea before anything else.

insert into public.verse_topics (verse_id, topic)
select v.id, t.topic
from (values
  -- Loved
  ('John 3:16', 'love'), ('Romans 5:8', 'love'), ('1 John 4:9', 'love'),
  ('1 John 4:10', 'love'), ('1 John 4:19', 'love'), ('Jeremiah 31:3', 'love'),
  ('Zephaniah 3:17', 'love'), ('Psalms 136:1', 'love'), ('Ephesians 2:4', 'love'),
  ('Romans 8:38', 'love'), ('Romans 8:39', 'love'), ('John 15:9', 'love'),
  ('Deuteronomy 7:9', 'love'), ('Isaiah 54:10', 'love'), ('Lamentations 3:22', 'love'),
  ('Psalms 103:11', 'love'), ('Titus 3:4', 'love'), ('John 13:1', 'love'),

  -- Accepted and welcomed
  ('Romans 15:7', 'acceptance'), ('John 6:37', 'welcome'), ('Matthew 11:28', 'welcome'),
  ('Luke 15:20', 'welcome'), ('Isaiah 1:18', 'acceptance'), ('Revelation 22:17', 'welcome'),
  ('Ephesians 1:6', 'acceptance'), ('Hebrews 4:16', 'welcome'), ('Psalms 27:10', 'welcome'),
  ('Isaiah 55:1', 'welcome'), ('Matthew 9:13', 'acceptance'), ('Luke 19:10', 'welcome'),

  -- Adopted and belonging
  ('John 1:12', 'adoption'), ('Romans 8:15', 'adoption'), ('Romans 8:16', 'adoption'),
  ('Galatians 4:5', 'adoption'), ('Galatians 4:7', 'adoption'), ('Ephesians 1:5', 'adoption'),
  ('1 John 3:1', 'adoption'), ('Ephesians 2:19', 'belonging'), ('1 Peter 2:9', 'belonging'),
  ('1 Peter 2:10', 'belonging'), ('Isaiah 43:1', 'belonging'), ('John 10:14', 'belonging'),
  ('Psalms 100:3', 'belonging'), ('1 Corinthians 12:27', 'belonging'),

  -- Valued and cherished
  ('Psalms 139:13', 'worth'), ('Psalms 139:14', 'worth'), ('Matthew 10:31', 'worth'),
  ('Luke 12:7', 'worth'), ('Isaiah 43:4', 'cherished'), ('Matthew 6:26', 'worth'),
  ('Ephesians 2:10', 'worth'), ('Psalms 8:5', 'worth'), ('Isaiah 49:16', 'cherished'),
  ('Deuteronomy 14:2', 'cherished'), ('Song of Solomon 4:7', 'cherished'),

  -- Grace and mercy
  ('Ephesians 2:8', 'grace'), ('Ephesians 2:9', 'grace'), ('Titus 3:5', 'grace'),
  ('2 Corinthians 12:9', 'grace'), ('Hebrews 4:15', 'mercy'), ('Lamentations 3:23', 'mercy'),
  ('Psalms 51:1', 'mercy'), ('Micah 7:18', 'mercy'), ('Luke 6:36', 'mercy'),
  ('Psalms 103:8', 'mercy'), ('Joel 2:13', 'mercy'), ('Exodus 34:6', 'mercy'),

  -- No condemnation
  ('Romans 8:1', 'no-condemnation'), ('John 8:11', 'no-condemnation'),
  ('Psalms 103:12', 'no-condemnation'), ('Isaiah 43:25', 'no-condemnation'),
  ('Micah 7:19', 'no-condemnation'), ('1 John 1:9', 'no-condemnation'),
  ('Colossians 2:14', 'no-condemnation'), ('Hebrews 8:12', 'no-condemnation'),
  ('John 3:17', 'no-condemnation'), ('Romans 8:34', 'no-condemnation'),

  -- Reconciled
  ('2 Corinthians 5:18', 'reconciliation'), ('2 Corinthians 5:19', 'reconciliation'),
  ('Colossians 1:20', 'reconciliation'), ('Colossians 1:22', 'reconciliation'),
  ('Romans 5:10', 'reconciliation'), ('Ephesians 2:13', 'reconciliation'),
  ('Ephesians 2:14', 'reconciliation'),

  -- Identity
  ('2 Corinthians 5:17', 'identity'), ('Galatians 2:20', 'identity'),
  ('Colossians 3:3', 'identity'), ('1 Peter 2:5', 'identity'),
  ('Philippians 3:20', 'identity'), ('John 15:15', 'identity')
) as t(reference, topic)
join public.daily_verses v on v.reference = t.reference
on conflict do nothing;
