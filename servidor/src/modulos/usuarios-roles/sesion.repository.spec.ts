import { Logger } from '@nestjs/common';
import type { AuthError } from '@supabase/supabase-js';
import { SupabaseService } from '../../supabase/supabase.service';
import { SesionRepository } from './sesion.repository';

function repositorioCon(error: AuthError | null) {
  const supabase = {
    clienteAnonimo: () => ({
      auth: {
        signInWithPassword: jest.fn().mockResolvedValue({ data: {}, error }),
      },
    }),
  } as unknown as SupabaseService;
  return new SesionRepository(supabase);
}

describe('SesionRepository', () => {
  afterEach(() => jest.restoreAllMocks());

  it('registra el error real de Supabase Auth sin incluir la contraseña', async () => {
    const aviso = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const error = {
      code: 'auth_error_no_esperado',
      status: 500,
      message: 'Fallo al validar el usuario en Supabase',
    } as AuthError;
    const repositorio = repositorioCon(error);

    await expect(
      repositorio.iniciarSesion('ana@itson.mx', 'contrasena-secreta'),
    ).rejects.toMatchObject({ codigo: 'ERROR_AUTENTICACION' });

    const mensaje = aviso.mock.calls[0][0] as string;
    expect(mensaje).toContain('code=auth_error_no_esperado');
    expect(mensaje).toContain('status=500');
    expect(mensaje).toContain('Fallo al validar el usuario en Supabase');
    expect(mensaje).not.toContain('contrasena-secreta');
  });

  it('registra cuando Auth responde sin sesión ni usuario', async () => {
    const aviso = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
    const repositorio = repositorioCon(null);

    await expect(repositorio.iniciarSesion('ana@itson.mx', 'demo1234')).rejects.toMatchObject({
      codigo: 'ERROR_AUTENTICACION',
    });
    expect(aviso).toHaveBeenCalledWith(expect.stringContaining('sin sesión ni usuario'));
  });
});
