export const StatusDot = ({ online }) => {
  return (
    <span
      className={`inline-flex h-2.5 w-2.5 rounded-full ${
        online ? 'bg-emerald-500 shadow-[0_0_0_4px_rgba(16,185,129,0.18)]' : 'bg-slate-300'
      }`}
      aria-label={online ? 'Online' : 'Offline'}
      title={online ? 'Online' : 'Offline'}
    />
  );
};
