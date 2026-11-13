// Solo para pruebas: imita el constructor de consultas de PostgREST. Cada método de
// filtro devuelve la misma consulta y registra la llamada; la consulta se resuelve
// (con await) con la respuesta indicada, sin importar qué método fue el último.
import { SupabaseService } from '../../supabase/supabase.service';

export interface RespuestaFalsa {
  data: unknown;
  error: { message: string } | null;
  count?: number | null;
}

const METODOS = ['select', 'eq', 'in', 'ilike', 'or', 'order', 'range'] as const;
type Metodo = (typeof METODOS)[number];

export type ConsultaFalsa = Record<Metodo, jest.Mock> & PromiseLike<RespuestaFalsa>;

export function crearSupabaseFalso(respuesta: RespuestaFalsa) {
  const consulta = {} as ConsultaFalsa;
  for (const metodo of METODOS) consulta[metodo] = jest.fn().mockReturnValue(consulta);
  consulta.then = (resolver, rechazar) => Promise.resolve(respuesta).then(resolver, rechazar);

  const from = jest.fn().mockReturnValue(consulta);
  const clienteDeUsuario = jest.fn(() => ({ from }));
  const supabase = { clienteDeUsuario } as unknown as SupabaseService;
  return { supabase, consulta, from, clienteDeUsuario };
}
