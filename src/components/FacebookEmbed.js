'use client';
import { useEffect } from 'react';

// Loads the Facebook JS SDK once and renders the page-plugin card.
// Uses the page URL passed via env var (NEXT_PUBLIC_FACEBOOK_PAGE_URL).
export default function FacebookEmbed({ tabs = 'timeline,events', height = 700, showLive = false }) {
  const pageUrl = process.env.NEXT_PUBLIC_FACEBOOK_PAGE_URL
    || 'https://www.facebook.com/amazingchurchphilippines';

  useEffect(() => {
    if (window.FB) { window.FB.XFBML.parse(); return; }
    const s = document.createElement('script');
    s.src = 'https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v19.0';
    s.async = true; s.defer = true; s.crossOrigin = 'anonymous';
    document.body.appendChild(s);
  }, []);

  return (
    <div className="w-full overflow-hidden rounded-xl border border-silver-light bg-white shadow-soft">
      <div id="fb-root" />
      <div
        className="fb-page"
        data-href={pageUrl}
        data-tabs={tabs}
        data-width="500"
        data-height={height}
        data-small-header="false"
        data-adapt-container-width="true"
        data-hide-cover="false"
        data-show-facepile="true"
      >
        <blockquote cite={pageUrl} className="fb-xfbml-parse-ignore p-4">
          <a href={pageUrl} target="_blank" rel="noreferrer">Amazing Church Philippines on Facebook</a>
        </blockquote>
      </div>
      {showLive && (
        <p className="text-xs text-ink/60 p-3 border-t border-silver-light">
          When the church goes live on Facebook, the stream appears automatically in the timeline above.
        </p>
      )}
    </div>
  );
}
