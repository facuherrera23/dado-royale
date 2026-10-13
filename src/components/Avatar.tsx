interface Props {
  username: string;
  avatarUrl?: string | null;
  size?: 'sm' | 'md' | 'lg';
}

/** Avatar: emoji elegido o inicial del username. */
export function Avatar({ username, avatarUrl, size = 'md' }: Props) {
  const sizeClass =
    size === 'sm' ? 'h-8 w-8 text-sm' : size === 'lg' ? 'h-16 w-16 text-3xl' : 'h-9 w-9 text-base';
  return (
    <span
      role="img"
      aria-label={`Avatar de ${username}`}
      className={`flex items-center justify-center rounded-full bg-casino-gold/20 font-bold text-casino-gold ${sizeClass}`}
    >
      {avatarUrl ?? username[0].toUpperCase()}
    </span>
  );
}
