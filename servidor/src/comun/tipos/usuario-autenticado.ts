// Debe coincidir con el check de public.usuarios.rol.
export enum Rol {
  Almacenista = 'ALMACENISTA',
  Supervisor = 'SUPERVISOR',
  SupervisorJefe = 'SUPERVISOR_JEFE',
  Admin = 'ADMIN',
}

export interface UsuarioAutenticado {
  id: string;
  nombre: string;
  rol: Rol;
  campusId: number;
  token: string;
}

export interface PeticionConUsuario {
  headers: Record<string, string | string[] | undefined>;
  usuario?: UsuarioAutenticado;
}
