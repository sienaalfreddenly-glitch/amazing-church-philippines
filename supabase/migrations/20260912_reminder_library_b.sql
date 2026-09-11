-- Reminder library, part two.
--
-- Thirty more finished reminders. Same rules as part one: 50 to 90 words, plain
-- words, correct grammar, no assumption about the reader's circumstances.
-- Written to cover situations part one did not reach, so the library spreads
-- across worry, loneliness, anger, shame, change, money, health, and the
-- ordinary middle of a week where nothing much is happening.

insert into public.reminder_templates (text, focus_tag, tone) values

('Some weeks nothing much happens. No crisis, no breakthrough, just the same round of ordinary days. Those stretches are not gaps between the real parts of your life. Most of a life is made of them, and God is as present in a quiet Tuesday as in anything dramatic. You are not waiting for your life to start.',
 'The ordinary', 'steady'),

('If your mind keeps running the same worry on a loop, that is exhaustion talking as much as anything. A tired brain is very bad at telling you the truth about how bad things are. Do one small useful thing, then stop. You can look at the whole of it again when you have slept.',
 'Worry', 'gentle'),

('Loneliness is not proof that something is wrong with you. It is information about your circumstances, not about your worth, and almost everybody feels it at some point without saying so. Reach out to one person today, even briefly and even badly. You do not have to explain yourself well to be worth talking to.',
 'Loneliness', 'gentle'),

('Anger is usually pain that has run out of patience. If you are angry today, it is worth asking quietly what is underneath it before you decide what to do. You can bring the anger to God as it is. He is not fragile, and he would rather have the honest version than a polite one.',
 'Anger', 'direct'),

('Shame and conviction are not the same thing, and it helps enormously to tell them apart. Conviction points at something you did and offers you a way to put it right. Shame points at you and offers nothing. Only one of those comes from God, and it is not the one that leaves you stuck.',
 'Shame', 'steady'),

('Change is uncomfortable even when it is good, and being unsettled by it does not mean you chose wrong. Anything new strips away the small routines that made you feel capable. That feeling passes as the routines rebuild. Give it longer than feels reasonable before you decide how it is going.',
 'Change', 'steady'),

('When money is tight, the worry follows you into every room and every conversation. God is not disappointed in you for it, and being short this month is not a verdict on your character. Tell him plainly what the gap is. Then tell one person you trust, because this particular fear gets much heavier in private.',
 'Provision', 'gentle'),

('If your body is not doing what it used to, that is a real loss and it deserves to be named as one. You are not required to be cheerful about it. God is not only available to people who feel well. He is the steady thing underneath on the days you have very little to bring.',
 'Health', 'gentle'),

('You are allowed to say no to something this week. Saying yes to everything is not generosity, it is usually fear of what people will think. The things you actually care about need room, and room only exists if something else does not get it. Choose deliberately rather than by default.',
 'Boundaries', 'direct'),

('Somebody has let you down and you are still deciding what to do about it. People will fail you, sometimes badly, and that is not evidence that God has. Let this cost you less than it wants to. You can be honest about the hurt without handing it the rest of your year.',
 'Trust', 'steady'),

('If you keep putting off a conversation, the delay is probably costing you more than the conversation would. Wait until you are calm rather than until you feel ready, because ready may never turn up. Then say the true thing kindly, and let the other person have their reaction without managing it for them.',
 'Courage', 'direct'),

('The version of you that other people see is always partial, and so is the version you see of them. Everyone is carrying something they have not mentioned. That is worth remembering both ways today: be gentler with the difficult person, and gentler with yourself for the parts nobody has noticed.',
 'Compassion', 'gentle'),

('Prayer does not require the right words or a particular posture or a good mood. If all you can manage today is a sentence in the car, that counts. God is not marking it. Being turned in his direction, even badly and even briefly, is the whole of what is being asked.',
 'Prayer', 'gentle'),

('You do not have to have a strong opinion about everything you read today. Much of what arrives on a screen is designed to make you feel urgently involved in something you cannot affect. Put some of it down. Peace is partly a matter of deciding what actually belongs to you.',
 'Peace', 'direct'),

('If you are dreading something specific this week, it is worth remembering that God is already there. Not waiting at the end of it, but in the room itself, before you arrive. You can be nervous and still go. Nerves are not a sign you are outside his will; they are a sign it matters.',
 'Courage', 'steady'),

('Being needed and being loved are not the same thing, though it is easy to confuse them when you are useful to a lot of people. If everything you do stopped tomorrow, you would still be exactly as valuable. Rest on that today rather than on how much you managed to get through.',
 'Worth', 'gentle'),

('Forgiving somebody does not mean deciding that what they did was fine. It means putting down a debt you were never going to collect anyway. That can take a long time and you may have to decide it more than once. Start from where you honestly are rather than where you think you should be.',
 'Forgiveness', 'steady'),

('Hope is not the same as optimism about how things will turn out. Optimism is a guess about circumstances. Hope is trust in the character of the one holding them. You do not have to feel hopeful to have hope, which is useful, because feelings are not reliable on a difficult week.',
 'Hope', 'steady'),

('If you have been comparing your life to what other people put online, stop for a moment and remember what you are actually looking at. Edited highlights, chosen carefully, with everything ordinary removed. Nobody lives there. Your unedited Tuesday is not losing to it.',
 'Contentment', 'direct'),

('When you have nothing left to give, that is not a failure of faith or of character. Everybody runs out. God is not only interested in you when you are useful. Turning up empty is still turning up, and there is no minimum you have to bring before you are welcome.',
 'Grace', 'gentle'),

('There is somebody you have been meaning to thank and have not got round to. Do it today, briefly, without making it a big occasion. Gratitude said out loud does something that gratitude felt privately does not, both for them and for you. It will take two minutes.',
 'Gratitude', 'direct'),

('If a decision has been sitting on you for weeks, notice that not deciding is also a decision, and usually a worse one. You will rarely have all the information you want. Ask God, take advice, and then choose. A decision made honestly can be worked with, even if it turns out imperfectly.',
 'Guidance', 'direct'),

('You are not responsible for how everybody else feels. Caring about people is right, and carrying their reactions as though you caused them is something else, and it will wear you down. Do the loving thing and then let go of the outcome. That part was never yours to manage.',
 'Boundaries', 'steady'),

('Some prayers are answered slowly enough that you only notice years later. That does not mean nothing happened at the time. If you are still waiting on something you asked for long ago, you have not been ignored. Keep asking, and keep living in the meantime rather than holding your breath.',
 'Waiting', 'steady'),

('When you cannot feel anything much, faith is not gone. Feelings come and go with sleep and light and how the week has treated you. What you believe does not run on them. Keep doing the ordinary things you would do anyway, and let the feeling come back in its own time.',
 'Faith', 'steady'),

('If you feel like you are pretending to be more together than you are, almost everybody around you feels the same. The pretending is exhausting and it keeps people at a distance you did not intend. Let one person see the real version this week and notice how much lighter it gets.',
 'Honesty', 'gentle'),

('Rest is not the reward you get after everything is finished, because it will never all be finished. It is part of the work, built into how the week is meant to run. Take some today rather than saving it for a quieter time that is not coming on its own.',
 'Rest', 'direct'),

('You have survived every difficult day so far, including the ones you were sure you would not manage. That is not luck and it is not only your own strength. Look back at one of them today and let it change how you look at the thing in front of you now.',
 'Perseverance', 'steady'),

('When you are surrounded by people and still feel alone, that is one of the strangest kinds of loneliness and one of the most common. It usually means the conversations have stayed shallow rather than that nobody cares. Say one true thing to somebody today and see what happens.',
 'Loneliness', 'gentle'),

('If today went well, let that be enough without immediately turning it into pressure to repeat it. A good day is a gift rather than a new standard you now have to meet. Say thank you for it, sleep properly, and let tomorrow be its own thing.',
 'Joy', 'gentle');
