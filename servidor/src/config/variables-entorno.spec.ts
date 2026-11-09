import { validarVariablesEntorno } from './variables-entorno';

describe('validarVariablesEntorno', () => {
  const validas = {
    SUPABASE_URL: 'https://proyecto.supabase.co',
    SUPABASE_ANON_KEY: 'clave',
  };

  it('acepta la configuración mínima y aplica valores por defecto', () => {
    const variables = validarVariablesEntorno(validas);
    expect(variables.PUERTO).toBe(3000);
    expect(variables.NODE_ENV).toBe('development');
  });

  it('convierte PUERTO a número', () => {
    expect(validarVariablesEntorno({ ...validas, PUERTO: '8080' }).PUERTO).toBe(8080);
  });

  it('falla al arrancar si falta una variable obligatoria', () => {
    expect(() => validarVariablesEntorno({ SUPABASE_URL: validas.SUPABASE_URL })).toThrow(
      /SUPABASE_ANON_KEY/,
    );
  });
});
