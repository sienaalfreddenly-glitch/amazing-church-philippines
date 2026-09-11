-- Reminder library, part one.
--
-- Each row is a finished reminder between 50 and 90 words. Written to be read
-- aloud without stumbling: short sentences, ordinary words, no church jargon
-- and no assumption about who is reading. Nothing here guesses whether you have
-- children, a job, or a diagnosis.

insert into public.reminder_templates (text, focus_tag, tone) values

('There is something you have been carrying around for a while, and it has not sorted itself out. You can bring it to God exactly as it is. You do not need to tidy it up first or find better words for it. Saying honestly that something is hard is not a failure of faith. It is how you stop carrying it on your own.',
 'Honesty with God', 'gentle'),

('You are probably harder on yourself than you would ever be with a friend in the same situation. Notice that today. God is not joining in with that voice. He sees all of you, including the parts you would rather nobody saw, and he has not walked away. Try speaking to yourself the way he speaks to you.',
 'God''s love', 'gentle'),

('Not every day has to be productive to be worth something. If today was slow, or you got less done than you meant to, that does not make it a wasted day. You were never measured by how much you produced. Rest is part of how you were made, and taking it is not laziness. Let today be enough as it was.',
 'Rest', 'gentle'),

('Fear gets bigger in the dark and smaller when you say it out loud. Whatever is worrying you, name it plainly, either to God or to somebody you trust. Most fears lose some of their size the moment they are spoken. The situation might not change tonight, but you will not be carrying it silently while it does.',
 'Courage', 'steady'),

('Waiting is hard because nothing looks like it is happening. It rarely feels like faith while you are in the middle of it. But trusting God when you cannot see any proof is exactly what trust means, and it still counts on the days it feels like nothing at all. You have not been forgotten and you are not running late.',
 'Waiting', 'steady'),

('Something you said or did is still bothering you. Put it right if you can, apologise if you should, and then let it go. Going over it again tonight will not make it better. God has already dealt with it, and punishing yourself for something he has forgiven does not help anybody. Let today be where it ends.',
 'Forgiveness', 'steady'),

('Strength is not a feeling. Most days it looks like getting on with the next ordinary thing while still tired. You do not have to feel capable in order to be capable. God gives you what today needs, usually just enough and rarely early. Look at what is actually in front of you instead of the whole week at once.',
 'Strength', 'steady'),

('Decisions are hard when you cannot see how they turn out. You are not failing just because the way ahead is unclear. Ask God, talk it over with somebody who knows you well, then choose with what you have. He can work with a decision made honestly, even one that turns out differently from how you hoped.',
 'Guidance', 'steady'),

('Try to notice one thing today that went right. It does not have to be big. A conversation that was easier than expected. Ten minutes of quiet. A meal you did not have to worry about. Naming it does not cancel out what is hard. It just stops the hard thing being the only thing you can see.',
 'Gratitude', 'gentle'),

('Getting better at anything is rarely a straight line. You have a good stretch, then a setback, and it feels like starting again from the beginning. It is not. Something that dips is still moving. Look at where you are over months rather than days, and be as patient with yourself as you would be with anyone else.',
 'Patience', 'steady'),

('Somebody will have an easier day because of something small you do. A message you send. A bit of patience you hold on to. A job you do without being asked. None of it will get noticed and it still matters. God sees the things nobody thanks you for, and those are usually the ones that hold everything together.',
 'Purpose', 'steady'),

('If you have been holding it together in front of everyone, you are allowed to stop for a minute. Admitting you are struggling is not weakness, and it will not disappoint God. He already knows. Letting one person see how you are really doing is usually where things start to get lighter.',
 'Honesty', 'gentle'),

('You have kept going at something for a long time without much to show for it. That is tiring, and nobody has said thank you. Rest properly first, then decide tomorrow. Not because giving up would be wrong, but because a decision made when you are worn out is rarely the one you would make after a good night.',
 'Perseverance', 'direct'),

('You do not need to see the whole plan before you take the next step. Most people only ever get enough light for the bit of road right in front of them. If that is where you are, you are not doing it wrong. Take the next honest step and leave the part you cannot work out with God.',
 'Trusting God''s direction', 'steady'),

('There is a difference between being busy and being weighed down. Busy stops when the week does. Weighed down follows you home. If that is you, work out what you are actually carrying, because it is usually more than the schedule. Bring the real thing to God, and let somebody help you with part of it.',
 'Rest', 'steady'),

('God is not far away today, and he is not disappointed in you. Those two ideas do more damage than almost anything else people believe about him. He is close, he is patient, and he is glad you are here. You do not have to earn that or even feel it for it to be true.',
 'God''s love', 'gentle'),

('Something has not turned out the way you hoped, and you are still getting used to it. Disappointment deserves a bit of time rather than being talked out of you. Sit with it honestly. God is not asking you to pretend you are fine. He is asking you to trust him with a future you did not choose.',
 'Disappointment', 'gentle'),

('Peace does not mean the problem is solved. It means you are not facing it on your own, which is a different thing and often a better one. You can still be worried tonight and still be held. Try to stop measuring your faith by how calm you feel, because that was never a fair test of it.',
 'Peace', 'steady'),

('Be careful how you talk about people today, especially the ones you find difficult. You do not have to feel warm towards somebody to speak fairly about them. Start by not repeating the story, and see how much easier the next conversation becomes. Grace nearly always starts with something that small.',
 'Grace', 'direct'),

('If you are tired in a way that sleeping does not fix, that is worth paying attention to. It usually means something needs to change rather than that you need to try harder. Ask God to show you honestly what it is. Then tell somebody, because that kind of tiredness rarely lifts while you are carrying it alone.',
 'Rest', 'direct'),

('You are not as far behind as you think. Comparing yourself to other people makes everyone else look further along, because you see their finished results and all of your own mess. God is not running you against anybody. Look at where you were a year ago rather than at where somebody else is today.',
 'Contentment', 'steady'),

('Courage is usually small and unimpressive. Sending the message. Asking the question. Turning up somewhere you would rather avoid. Nobody claps for any of it, and it still costs you something. God is with you in the small brave things just as much as the big ones, and today is probably only asking for a small one.',
 'Courage', 'steady'),

('Whatever is unresolved tonight will still be unresolved in the morning, and you will be in a much better state to face it after some sleep. Worrying is not the same as preparing, even though at two in the morning it feels like it. Put it down for now. God does not need you awake to keep working.',
 'Rest', 'gentle'),

('You have more to be grateful for than you can hold in your head at once, and most of it is so ordinary that you stopped noticing years ago. Water that runs. A door that locks. Somebody who would pick up if you rang them. None of that is guaranteed to anybody, and today you have it again.',
 'Gratitude', 'gentle'),

('When you feel like nobody has noticed you, remember that being seen by people and being known by God are not the same thing. One depends on who happens to be looking that day. The other does not change when the room is empty. You are known today, whether or not a single person says so.',
 'Being known', 'gentle'),

('If you feel like you do not belong here, that feeling is not the truth of the situation. Belonging was never something you earned by fitting in well enough or knowing the right things. It was given to you. You are already inside. You are not auditioning, and nobody is deciding whether to keep you.',
 'Belonging', 'gentle'),

('Doubt is not the opposite of faith. Almost everybody who has believed anything worth believing has been through a stretch like the one you might be in. Bring the questions with you instead of leaving them at the door. A faith that has never been asked anything difficult has not been tested yet.',
 'Doubt', 'steady'),

('Grief does not run to a timetable, and there is no point at which you are supposed to be over it. If you are carrying a loss, God is not waiting on the other side of it for you to pull yourself together. He is in it with you. You can bring him the anger as well as the sadness.',
 'Comfort', 'gentle'),

('If you have made the same mistake again, mercy is not a supply you have been slowly using up since you were young. There is genuinely more of it waiting. Get up again today, but let it be hope doing the lifting rather than shame. Shame has never once made anybody better at anything.',
 'Mercy', 'steady'),

('When something good happens unexpectedly, let it land properly instead of bracing for whatever comes next. Good things are not a trick, and enjoying one does not use up your share. You are allowed to be glad today without checking over your shoulder. Take the good thing as it is and say thank you for it.',
 'Joy', 'gentle');
