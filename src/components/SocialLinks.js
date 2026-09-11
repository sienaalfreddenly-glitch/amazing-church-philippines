import { IconFacebook, IconInstagram, IconPhone } from '@/components/Icons';

/**
 * A member's social and contact links.
 *
 * Renders nothing at all when a profile has none set, so callers can drop it in
 * without guarding first. The phone number appears only when the member has
 * opted in via show_contact.
 */
export default function SocialLinks({ profile, size = 18, className = '' }) {
  if (!profile) return null;

  const links = [];

  if (profile.facebook_url) {
    links.push({ href: profile.facebook_url, Icon: IconFacebook, label: 'Facebook', external: true });
  }
  if (profile.instagram_url) {
    links.push({ href: profile.instagram_url, Icon: IconInstagram, label: 'Instagram', external: true });
  }
  if (profile.show_contact && profile.contact_number) {
    links.push({
      // tel: strips spaces so the dialler gets a clean number.
      href: `tel:${profile.contact_number.replace(/[^\d+]/g, '')}`,
      Icon: IconPhone,
      label: profile.contact_number,
      external: false,
    });
  }

  if (!links.length) return null;

  return (
    <ul className={`flex flex-wrap items-center gap-x-4 gap-y-2 ${className}`}>
      {links.map(({ href, Icon, label, external }) => (
        <li key={href}>
          <a
            href={href}
            {...(external ? { target: '_blank', rel: 'noreferrer noopener' } : {})}
            className="inline-flex items-center gap-1.5 rounded-md text-sm text-ink/60 transition-colors hover:text-brand"
          >
            <Icon size={size} />
            {/* Icon-only for the networks, but a phone number is worth reading. */}
            <span className={external ? 'sr-only' : 'nums'}>{label}</span>
          </a>
        </li>
      ))}
    </ul>
  );
}
