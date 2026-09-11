-- Plainer wording. The earlier text read like a job description; this is closer
-- to how someone would actually explain it to you after a service.

update ministries set
  summary = 'The first face anyone sees on a Sunday.',
  calling = 'Most people work out whether they belong here before the preaching even starts, and usually that happens at the door. If you are the sort who notices the person standing on their own, this is your gift, and it matters more than it looks.',
  scripture = 'Better one day as a doorkeeper in the house of my God.'
where slug = 'ushering';

update ministries set
  summary = 'Helping the whole room sing.',
  calling = 'This team is not a band and the service is not a concert. The job is to help everyone else sing, which means picking songs ordinary voices can reach and knowing them well enough to look up from the music. You do not need to be the best musician in the room.',
  scripture = 'Let the word of Christ live in you, singing with thankful hearts.'
where slug = 'worship';

update ministries set
  summary = 'Sound, slides, livestream, and everything nobody notices.',
  calling = 'When this team gets it right nobody says a word, and when the microphone cuts out everybody does. Scripture talks about craftsmen God filled with skill to build the tabernacle. Being good with equipment is a gift too, not just a job that needs doing.',
  scripture = 'I have filled him with skill and knowledge in every craft.'
where slug = 'tech-media';

update ministries set duties = array[
  'Get there before everyone else and pray over the room',
  'Welcome people at the door, especially anyone on their own',
  'Seat latecomers without making them feel late',
  'Count the offering with a second person present',
  'Notice who has stopped coming and tell a leader'
] where slug = 'ushering';

update ministries set duties = array[
  'Rehearse midweek, not just before the service',
  'Know the songs well enough to look up from the music',
  'Keep the keys where an ordinary voice can reach',
  'Play for the room, not for yourself',
  'Stay accountable to a leader for how you live, not only how you play'
] where slug = 'worship';

update ministries set duties = array[
  'Take a turn on sound, slides, or the livestream',
  'Come early for soundcheck and stay to pack down',
  'Grab photos and clips for the feed and the page',
  'Look after the gear and keep the cables tidy',
  'Teach someone else so you are not the only one who knows how'
] where slug = 'tech-media';
