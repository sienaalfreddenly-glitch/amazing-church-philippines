export default function Avatar({ url, name = '', size = 40, fit = 'cover' }) {
  const initials = name.split(' ').map(n => n[0]).filter(Boolean).slice(0, 2).join('').toUpperCase() || '·';
  const style = { width: size, height: size, fontSize: size * 0.42 };
  if (url) {
    // fit="contain" keeps the whole image visible inside the circle (used for
    // the church logo, which is wider than tall and gets its text sliced off
    // by the default object-cover face crop).
    const cls = fit === 'contain'
      ? 'rounded-full object-contain bg-white border border-silver-light p-0.5'
      : 'rounded-full object-cover border border-silver-light';
    return <img src={url} alt={name} style={style} className={cls} />;
  }
  return (
    <div style={style} className="rounded-full bg-brand text-white font-semibold flex items-center justify-center">
      {initials}
    </div>
  );
}
