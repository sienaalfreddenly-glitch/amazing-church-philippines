-- Reminder templates, and the curated verse list visitors may see.

-- ---------------------------------------------------------------------------
-- Templates
--
-- A template is an opening move and a shape, not a sentence with a hole in it.
-- The generator composes a template with the verse to produce a reminder, and
-- the composed text is then checked for duplicates before it is stored. Shallow
-- templates that merely restate the verse are deliberately avoided.
-- ---------------------------------------------------------------------------

create table if not exists public.reminder_templates (
  id         uuid primary key default gen_random_uuid(),
  opening    text not null,
  body       text not null,
  closing    text not null,
  focus_tag  text not null,
  tone       text not null default 'steady' check (tone in ('steady', 'gentle', 'direct')),
  status     text not null default 'active' check (status in ('active', 'retired')),
  created_at timestamptz not null default now(),

  -- Role-specific language is rejected at the door rather than in review. If a
  -- template assumes the reader is a parent or an employee, the assumption is
  -- wrong for most readers and the message stops landing.
  constraint template_no_roles check (
    (opening || ' ' || body || ' ' || closing) !~*
    '\m(parent|parents|mother|father|mum|dad|student|students|employee|employees|husband|wife|spouse|teenager|child of yours|your kids|your children|your job|your boss)\M'
  ),
  constraint template_no_em_dash check ((opening || body || closing) !~ '[—–]'),
  constraint template_no_emoji   check ((opening || body || closing) ~ '^[\x00-\x7F''’"“”]*$')
);

create unique index if not exists reminder_templates_uniq
  on public.reminder_templates (md5(lower(opening || body || closing)));

alter table public.daily_reminders
  drop constraint if exists daily_reminders_template_fk;
alter table public.daily_reminders
  add constraint daily_reminders_template_fk
  foreign key (template_id) references public.reminder_templates(id) on delete set null;

insert into public.reminder_templates (opening, body, closing, focus_tag, tone) values
('When you feel unseen,', 'it is worth remembering that being noticed by people and being known by God are not the same thing. One depends on who happens to be looking. The other does not change on a quiet day.', 'You are known today whether or not anyone says so.', 'Being known', 'gentle'),
('In seasons of waiting,', 'the absence of visible progress is not the absence of God working. Waiting rarely feels like faith while you are inside it, and it counts anyway.', 'You have not been forgotten, and you are not behind.', 'Hope while waiting', 'steady'),
('If you are carrying something heavy,', 'you do not have to find the right words for it before you bring it to God. Honesty about what is hard is not a failure of faith. It is the start of putting it down.', 'Say it plainly today, however unfinished it sounds.', 'Peace under pressure', 'gentle'),
('When life feels heavy,', 'the instruction is rarely to push harder. Rest is part of how you were made to work, and taking it is obedience rather than laziness.', 'Let today be enough as it actually was.', 'Rest', 'gentle'),
('When things are better than expected,', 'notice it out loud rather than waiting for the next problem. Gratitude is not a denial of what is hard. It stops the hard thing being the only thing in view.', 'Name one good thing before the day closes.', 'Gratitude', 'steady'),
('If you do not know what to do next,', 'you are not failing because the way ahead is unclear. Most people only ever get enough light for the part of the road immediately in front of them.', 'Take the next honest step and leave the rest with God.', 'Trusting God''s direction', 'steady'),
('When you are tempted to give up,', 'rest properly first and decide afterwards. Exhaustion is a poor advisor, and a decision made at the end of a long stretch is rarely the one you would make rested.', 'Decide tomorrow, not tonight.', 'Perseverance', 'direct'),
('When fear arrives,', 'say the thing out loud, either to God or to one person you trust. Most fears lose some of their size the moment they are spoken and stop being carried alone.', 'The situation may not change tonight. You still do not face it by yourself.', 'Courage', 'steady'),
('If you are being hard on yourself,', 'notice that you would not speak this way to anyone else in your position. God is not adding his voice to that criticism.', 'Try hearing yourself the way he hears you.', 'God''s love', 'gentle'),
('When something did not go as you hoped,', 'disappointment deserves a little time rather than being argued away. Sitting with it honestly is not a lack of trust.', 'You are allowed to grieve the version of the future you did not choose.', 'Disappointment', 'gentle'),
('When you feel far from God,', 'distance is usually felt rather than actual. Feelings are real information about you and poor information about where he is.', 'He has not moved, even on the days you cannot tell.', 'God''s nearness', 'steady'),
('If today felt wasted,', 'output is not the measure. A slow day is not a failed one, and you were never valued by how much you produced.', 'Today counted, whether or not it looked like it.', 'Worth', 'gentle'),
('When you are worn out,', 'the tiredness that sleep does not fix usually means something needs to change rather than that you need to try harder.', 'Ask for honesty about what it is, then tell somebody.', 'Rest', 'direct'),
('When regret keeps circling,', 'turning it over again tonight will not improve it. Put right what can be put right, then let it be finished.', 'What God has dealt with does not need you to keep punishing it.', 'Forgiveness', 'steady'),
('When you compare yourself to others,', 'remember you are seeing their finished parts and all of your own working out. That comparison was never fair to you.', 'Measure against where you were, not against where they are.', 'Contentment', 'steady'),
('If you are the one everybody leans on,', 'being capable is not the same as being fine. Needing help does not disqualify you from giving it.', 'Ask somebody for something this week.', 'Honesty', 'direct'),
('When the day ahead looks like too much,', 'you are not asked to carry the whole week at once. Strength tends to arrive as enough for today and rarely in advance.', 'Look only at what is actually in front of you.', 'Strength', 'steady'),
('When you cannot pray properly,', 'God is not waiting for eloquence. Being present and still breathing is a real form of holding on.', 'Silence in his direction still counts.', 'Prayer', 'gentle'),
('When you feel like you do not belong,', 'belonging here was never something you earned by fitting in well enough. It was given.', 'You are already inside, not auditioning.', 'Belonging', 'gentle'),
('If you are anxious about what you cannot control,', 'most of what you are turning over is not yours to carry, and some of it will not happen.', 'Hand it over for the night and pick up only what is yours tomorrow.', 'Peace under pressure', 'steady'),
('When somebody has hurt you,', 'forgiving does not mean deciding that what happened was acceptable. It means stopping carrying a debt that costs you more than it costs them.', 'Start where you actually are, not where you think you should be.', 'Forgiveness', 'steady'),
('When you are grieving,', 'there is no point at which you are meant to be over it, and no schedule you are behind on.', 'God is not waiting on the far side of this. He is in it with you.', 'Comfort', 'gentle'),
('When doubt turns up,', 'questions are not the opposite of faith. Most people who have believed anything worth believing went through this.', 'Bring the doubt with you rather than leaving it at the door.', 'Doubt', 'steady'),
('When you have been faithful with no result,', 'work that looks like nothing for a long time often turns out to have mattered enormously.', 'Do not judge the harvest by what you can see today.', 'Perseverance', 'steady'),
('When you feel small,', 'scale is not how God decides what matters. The things nobody thanks you for are usually the ones that hold everything together.', 'What you did today was seen.', 'Worth', 'gentle'),
('If you are dreading something,', 'he is already in the room you are dreading, and he got there before you did.', 'You are walking in, not walking in alone.', 'Courage', 'steady'),
('When you are lonely,', 'loneliness is not evidence that you are unwanted. It is information about your circumstances, not about your value.', 'Reach out once today, even briefly.', 'Loneliness', 'gentle'),
('When you have made the same mistake again,', 'mercy is not a supply you have been drawing down since childhood. There is genuinely more waiting.', 'Get up again, without shame doing the driving.', 'Grace', 'steady'),
('When you feel behind,', 'God is not running you against anybody. The pace you are managing is the pace you are meant to be at today.', 'Look at a year ago rather than at somebody else now.', 'Patience', 'gentle'),
('When joy turns up unexpectedly,', 'let it land properly instead of bracing for what comes next. Good things are not a setup.', 'Receive it without flinching.', 'Joy', 'gentle'),
('When you are confused about a decision,', 'clarity usually arrives as a slow narrowing rather than a bright idea. Ruling things out is guidance too.', 'The boring sensible option is often the one that holds.', 'Wisdom', 'steady'),
('If you have stopped hoping,', 'hope is not optimism about outcomes. It is trusting the character of the one holding the outcome.', 'You do not have to feel hopeful to be held.', 'Hope while waiting', 'steady'),
('When you want to hide,', 'the instinct to cover up is old and human, and it has never once been necessary with him.', 'He already knows, and he has not left.', 'Grace', 'gentle'),
('When your work goes unnoticed,', 'faithfulness mostly looks like doing a dull task honestly when nobody checks.', 'It counted, and it was seen.', 'Purpose', 'steady'),
('When you are tempted to keep score,', 'measuring who owes whom will exhaust you long before it settles anything.', 'Put the ledger down.', 'Forgiveness', 'direct'),
('When peace feels impossible,', 'peace here does not mean the situation resolved. It means you are not facing it alone, which is different and often better.', 'You may still be worried tonight and still be held.', 'Peace under pressure', 'steady'),
('When you are starting something new,', 'the disorientation is normal and it does pass. Not knowing your way around yet is not incompetence.', 'He is already in the new place, in people you have not met.', 'Courage', 'steady'),
('When you feel like a burden,', 'the people who love you would rather carry something with you than find out later you did it alone.', 'Let somebody in this week.', 'Belonging', 'gentle'),
('When you cannot see the point,', 'the stretch that felt wasted is often exactly what makes you someone others can talk to later.', 'Nothing here is discarded.', 'Purpose', 'steady'),
('When you are angry,', 'anger is usually pain that has run out of patience. Bring the anger too; he can take all of it.', 'Say the true thing rather than the polite one.', 'Honesty', 'direct'),
('When you have been let down,', 'people will fail you, sometimes badly, and that is not evidence that God has.', 'Let this cost you less than it wants to.', 'Trust', 'steady'),
('When gratitude feels forced,', 'you are not required to feel thankful for what is hard. Notice something ordinary that went right instead.', 'Water that runs. A door that locks. Somebody who would answer.', 'Gratitude', 'gentle'),
('When the night is long,', 'whatever is unresolved now will still be unresolved in the morning, and you will be better equipped having slept.', 'Worrying is not the same as preparing.', 'Rest', 'gentle'),
('When you feel unforgivable,', 'the size of what you have done has never been the deciding factor. It was never a negotiation you were losing.', 'Come back. That is the whole invitation.', 'Grace', 'gentle'),
('When you have to say a hard thing,', 'wait until you are calm rather than until you feel ready, because ready may not arrive.', 'Then say the true thing kindly.', 'Wisdom', 'direct'),
('When everything feels uncertain,', 'certainty was never what you were promised. Presence was.', 'You can walk without a map if you are not walking alone.', 'Trust', 'steady'),
('When you feel replaceable,', 'you are not a role that somebody else could fill equally well. You are not interchangeable to him.', 'That is true today, whatever your week looked like.', 'Worth', 'gentle'),
('When shame speaks up,', 'notice the difference between conviction, which points at a thing you did, and shame, which points at you.', 'Only one of those is from God.', 'Grace', 'steady'),
('When you have nothing to bring,', 'he is not only available to the capable and the upbeat. Turning up empty is still turning up.', 'Bring the nothing. It is enough.', 'God''s love', 'gentle'),
('When the good news feels far away,', 'it is not less true on the days you cannot feel it. Truth does not run on your mood.', 'Hold on loosely today and let it hold you.', 'Faith', 'steady')
on conflict do nothing;
