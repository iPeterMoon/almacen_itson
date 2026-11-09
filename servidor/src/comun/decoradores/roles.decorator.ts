import { SetMetadata } from '@nestjs/common';
import { Rol } from '../tipos/usuario-autenticado';

export const ROLES = 'roles';

// Solo es un primer filtro; los permisos reales los aplican las funciones y RLS de la base.
export const Roles = (...roles: Rol[]) => SetMetadata(ROLES, roles);
