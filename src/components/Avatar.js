export default function Avatar({ url, name = '', size = 40 }) {
  const initials = name.split(' ').map(n => n[0]).filter(Boolean).slice(0, 2).join('').toUpperCase() || '·';
  const style = { width: size, height: size, fontSize: size * 0.42 };
  if (url) {
    return <img src={url} alt={name} style={style} className="rounded-full object-cover border border-silver-light" />;
  }
  return (
    <div style={style} className="rounded-full bg-brand text-white font-semibold flex items-center justify-center">
      {initials}
    </div>
  );
}
