// Solo para pruebas de integración: reemplaza al cliente de Supabase con una "base"
// en memoria que responde por nombre de tabla o de función RPC. A diferencia de
// src/comun/pruebas/supabase-falso.ts (una sola respuesta para todo), aquí cada
// tabla y RPC tiene su propio manejador, así se puede recorrer un flujo completo
// (crear boleta → autorizar → entregar → resumen) con los servicios reales.
import { SupabaseService } from '../../src/supabase/supabase.service';

export interface RespuestaFalsa {
  data: unknown;
  error: { message: string } | null;
  count?: number | null;
}

// Cada llamada al constructor de consultas queda registrada como [método, ...argumentos].
export type Llamada = [string, ...unknown[]];

export interface ConsultaRegistrada {
  tabla: string;
  llamadas: Llamada[];
}

type ManejadorTabla = (consulta: ConsultaRegistrada) => RespuestaFalsa;
type ManejadorRpc = (parametros: Record<string, unknown>) => RespuestaFalsa;

const METODOS = [
  'select',
  'eq',
  'in',
  'ilike',
  'or',
  'gte',
  'lte',
  'order',
  'range',
  'maybeSingle',
] as const;

export function ok(data: unknown, count?: number): RespuestaFalsa {
  return { data, error: null, count };
}

export function fallo(message: string): RespuestaFalsa {
  return { data: null, error: { message } };
}

// Valor de un filtro de la consulta, por ejemplo filtro(c, 'eq', 'id') → 7.
export function filtro(consulta: ConsultaRegistrada, metodo: string, columna: string): unknown {
  const llamada = consulta.llamadas.find(([m, c]) => m === metodo && c === columna);
  return llamada?.[2];
}

export function crearBaseFalsa() {
  const tablas = new Map<string, ManejadorTabla>();
  const rpcs = new Map<string, ManejadorRpc>();
  const consultas: ConsultaRegistrada[] = [];

  // Lo que no se simuló responde con error: así una consulta inesperada hace fallar la prueba
  // en vez de pasar en silencio.
  const rpc = jest.fn((nombre: string, parametros: Record<string, unknown>) => {
    const manejador = rpcs.get(nombre);
    return Promise.resolve(manejador ? manejador(parametros) : fallo(`RPC no simulada: ${nombre}`));
  });

  const from = jest.fn((tabla: string) => {
    const registro: ConsultaRegistrada = { tabla, llamadas: [] };
    consultas.push(registro);
    const consulta: Record<string, unknown> = {};
    for (const metodo of METODOS) {
      consulta[metodo] = (...args: unknown[]) => {
        registro.llamadas.push([metodo, ...args]);
        return consulta;
      };
    }
    // Se resuelve al hacer await, sin importar cuál fue el último método encadenado.
    consulta.then = (
      resolver: (valor: RespuestaFalsa) => unknown,
      rechazar: (motivo: unknown) => unknown,
    ) =>
      Promise.resolve()
        .then(() => {
          const manejador = tablas.get(tabla);
          return manejador ? manejador(registro) : fallo(`Tabla no simulada: ${tabla}`);
        })
        .then(resolver, rechazar);
    return consulta;
  });

  const subir = jest.fn(() => Promise.resolve<RespuestaFalsa>(ok({ path: 'subida' })));
  const storage = { from: jest.fn(() => ({ upload: subir })) };

  const cliente = { rpc, from, storage };
  const supabase = {
    clienteDeUsuario: jest.fn(() => cliente),
    clienteAnonimo: jest.fn(() => cliente),
  } as unknown as SupabaseService;

  return {
    supabase,
    rpc,
    storage,
    subir,
    consultas,
    // Consultas hechas a una tabla, en orden.
    consultasA: (tabla: string) => consultas.filter((c) => c.tabla === tabla),
    tabla(nombre: string, manejador: ManejadorTabla) {
      tablas.set(nombre, manejador);
    },
    funcion(nombre: string, manejador: ManejadorRpc) {
      rpcs.set(nombre, manejador);
    },
    // Deja la base vacía entre pruebas.
    reiniciar() {
      tablas.clear();
      rpcs.clear();
      consultas.length = 0;
      rpc.mockClear();
      from.mockClear();
      subir.mockClear();
      subir.mockImplementation(() => Promise.resolve(ok({ path: 'subida' })));
      storage.from.mockClear();
    },
  };
}

export type BaseFalsa = ReturnType<typeof crearBaseFalsa>;
