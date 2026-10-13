import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabaseClient';

/** Lee la tabla pública `config` y devuelve un mapa clave -> número. */
export function useConfig() {
  return useQuery({
    queryKey: ['config'],
    staleTime: 5 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase.from('config').select('key, value');
      if (error) throw error;
      const map = new Map<string, number>();
      for (const row of data) {
        const n = Number(typeof row.value === 'string' ? row.value : JSON.stringify(row.value));
        if (Number.isFinite(n)) map.set(row.key, n);
      }
      return map;
    },
  });
}
