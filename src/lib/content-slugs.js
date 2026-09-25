// The registry of every editable copy block. This is what the admin page reads
// to know what can be edited and what its default text is. Adding a new
// editable block anywhere on the site is a two-line change here plus one call
// to getContent(slug, fallback) at the render site.
//
// Group is only used for section headings in the admin UI.

export const CONTENT_BLOCKS = [
  // Footer
  { slug: 'footer.eyebrow',   group: 'Footer', label: 'Footer eyebrow',   kind: 'text',
    fallback: 'Amazing Church Philippines' },
  { slug: 'footer.statement', group: 'Footer', label: 'Footer statement', kind: 'text',
    fallback: 'We win souls and make them disciples of Jesus' },
  { slug: 'footer.copyright', group: 'Footer', label: 'Copyright suffix (year is prepended)', kind: 'text',
    fallback: 'Amazing Church Philippines' },

  // Home: Community panel
  { slug: 'home.community.eyebrow', group: 'Home', label: 'Community panel eyebrow', kind: 'text',
    fallback: 'Community' },
  { slug: 'home.community.heading', group: 'Home', label: 'Community panel heading', kind: 'text',
    fallback: 'Share what God is doing' },
  { slug: 'home.community.body',    group: 'Home', label: 'Community panel body',    kind: 'multiline',
    fallback: 'Post a testimony, start a discussion, or encourage another member with a reaction or a comment.' },
  { slug: 'home.facebook.heading',  group: 'Home', label: 'Facebook section heading', kind: 'text',
    fallback: 'From our Facebook page' },
  { slug: 'home.facebook.subtitle', group: 'Home', label: 'Facebook section subtitle', kind: 'text',
    fallback: 'Livestreams and announcements, as they post.' },
  { slug: 'home.events.heading',    group: 'Home', label: 'Upcoming events heading', kind: 'text',
    fallback: 'Upcoming events' },

  // Terms
  { slug: 'terms.updated',              group: 'Terms', label: 'Last-updated line', kind: 'text',
    fallback: 'September 2026' },
  { slug: 'terms.membership.heading',   group: 'Terms', label: 'Membership · heading', kind: 'text',
    fallback: 'Membership' },
  { slug: 'terms.membership.body',      group: 'Terms', label: 'Membership · body', kind: 'multiline',
    fallback: 'Accounts are approved by church leaders before they can post. Keep one account, use your real name, and do not share your password. We may pause an account while we look into a concern.' },
  { slug: 'terms.conduct.heading',      group: 'Terms', label: 'Conduct · heading', kind: 'text',
    fallback: 'How we treat each other' },
  { slug: 'terms.conduct.body',         group: 'Terms', label: 'Conduct · body', kind: 'multiline',
    fallback: 'Disagree openly and kindly. Harassment, slurs, threats, and sexual content are not welcome here and will be removed. Do not post other people’s private information, and do not share what is said in a pastoral conversation.' },
  { slug: 'terms.posts.heading',        group: 'Terms', label: 'What you post · heading', kind: 'text',
    fallback: 'What you post' },
  { slug: 'terms.posts.body',           group: 'Terms', label: 'What you post · body', kind: 'multiline',
    fallback: 'You keep ownership of what you write and the photos you upload. By posting, you allow the church to display that content inside the community and, for anything posted publicly, on our public pages. Post only what you have the right to share.' },
  { slug: 'terms.money.heading',        group: 'Terms', label: 'Money · heading', kind: 'text',
    fallback: 'Money and requests' },
  { slug: 'terms.money.body',           group: 'Terms', label: 'Money · body', kind: 'multiline',
    fallback: 'Do not use the feed or discussions to solicit money, sell goods, or promote a business. Giving to the church is handled through the channels announced in service, never through a link posted by another member.' },
  { slug: 'terms.moderation.heading',   group: 'Terms', label: 'Moderation · heading', kind: 'text',
    fallback: 'Moderation' },
  { slug: 'terms.moderation.body',      group: 'Terms', label: 'Moderation · body', kind: 'multiline',
    fallback: 'Moderators can hide or delete posts and comments that break these terms, and can remove accounts for repeated or serious breaches. If you think a decision was wrong, ask a leader to review it.' },
  { slug: 'terms.changes.heading',      group: 'Terms', label: 'Changes · heading', kind: 'text',
    fallback: 'Changes' },
  { slug: 'terms.changes.body',         group: 'Terms', label: 'Changes · body', kind: 'multiline',
    fallback: 'We will update these terms as the community grows, and will note the date at the top when we do.' },

  // Privacy
  { slug: 'privacy.updated',            group: 'Privacy', label: 'Last-updated line', kind: 'text',
    fallback: 'September 2026' },
  { slug: 'privacy.collect.heading',    group: 'Privacy', label: 'Collect · heading', kind: 'text',
    fallback: 'What we collect' },
  { slug: 'privacy.collect.body',       group: 'Privacy', label: 'Collect · body', kind: 'multiline',
    fallback: 'When you sign up we store your name, email address, and anything you choose to add to your profile, such as a photo. When you post, comment, or react, we store that content along with the time it was posted.' },
  { slug: 'privacy.why.heading',        group: 'Privacy', label: 'Why · heading', kind: 'text',
    fallback: 'Why we collect it' },
  { slug: 'privacy.why.body',           group: 'Privacy', label: 'Why · body', kind: 'multiline',
    fallback: 'We use it to run the community: to show your posts to other members, to notify you when someone replies, and to let church leaders approve new accounts. We do not sell member information, and we do not use it for advertising.' },
  { slug: 'privacy.visibility.heading', group: 'Privacy', label: 'Visibility · heading', kind: 'text',
    fallback: 'Who can see your posts' },
  { slug: 'privacy.visibility.body',    group: 'Privacy', label: 'Visibility · body', kind: 'multiline',
    fallback: 'The feed, discussions, and courses are visible to approved members only. Events, news, and livestreams are public. Church leaders and moderators can see all member content so they can keep the space safe.' },
  { slug: 'privacy.storage.heading',    group: 'Privacy', label: 'Storage · heading', kind: 'text',
    fallback: 'Where it is stored' },
  { slug: 'privacy.storage.body',       group: 'Privacy', label: 'Storage · body', kind: 'multiline',
    fallback: 'Member accounts and posts are stored with Supabase. Livestream video is hosted on Facebook, and viewing it is covered by Facebook policies rather than ours.' },
  { slug: 'privacy.removal.heading',    group: 'Privacy', label: 'Removal · heading', kind: 'text',
    fallback: 'Removing your information' },
  { slug: 'privacy.removal.body',       group: 'Privacy', label: 'Removal · body', kind: 'multiline',
    fallback: 'You can edit or delete your own posts at any time. To close your account and have your content removed, contact a church leader and we will action it. Some records may be kept where we are required to.' },
  { slug: 'privacy.questions.heading',  group: 'Privacy', label: 'Questions · heading', kind: 'text',
    fallback: 'Questions' },
  { slug: 'privacy.questions.body',     group: 'Privacy', label: 'Questions · body', kind: 'multiline',
    fallback: 'Speak to any of our leaders, or raise it after a Sunday service.' },
];

export const BLOCKS_BY_SLUG = Object.fromEntries(
  CONTENT_BLOCKS.map((b) => [b.slug, b])
);

export function fallbackFor(slug) {
  return BLOCKS_BY_SLUG[slug]?.fallback ?? '';
}
