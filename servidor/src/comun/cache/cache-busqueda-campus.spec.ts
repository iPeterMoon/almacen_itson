// Pruebas de lo que es propio de la clase base. Lo demás (acierto, expiración,
// campus, invalidación) se prueba en la caché de activos y en la de trabajadores.
import { Rol } from '../tipos/usuario-autenticado';
import { CacheBusquedaPorCampus, crearCacheEnMemoria } from './cache-busqueda-campus';

const ALMACENISTA = { rol: Rol.Almacenista, campusId: 1 };

interface DtoDePrueba {
  texto: string;
}

// Todas arman la clave igual, así que dos instancias solo difieren en el prefijo.
class CacheDePrueba extends CacheBusquedaPorCampus<DtoDePrueba> {
  constructor(almacen: ReturnType<typeof crearCacheEnMemoria>, prefijo: string) {
    super(almacen, prefijo);
  }

  protected partesDeClave(dto: DtoDePrueba) {
    return [dto.texto];
  }
}

describe('CacheBusquedaPorCampus', () => {
  it('dos cachés con distinto prefijo no se mezclan aunque compartan almacén y búsqueda', async () => {
    const almacen = crearCacheEnMemoria();
    const unas = new CacheDePrueba(almacen, 'unas');
    const otras = new CacheDePrueba(almacen, 'otras');

    const deUnas = await unas.buscar(ALMACENISTA, { texto: 'juan' }, () => Promise.resolve('unas'));
    const deOtras = await otras.buscar(ALMACENISTA, { texto: 'juan' }, () =>
      Promise.resolve('otras'),
    );

    expect(deUnas).toBe('unas');
    expect(deOtras).toBe('otras');
  });
});
