import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';
import { VariablesEntorno } from '../config/variables-entorno';
import type { Database } from './tipos-base';

// Cliente tipado con el esquema generado desde supabase/migrations.
export type ClienteSupabase = SupabaseClient<Database>;

// No hay cliente con service_role a propósito: las operaciones usan el token del usuario
// para que auth.uid() y RLS funcionen dentro de las funciones de la base.
@Injectable()
export class SupabaseService {
  private readonly url: string;
  private readonly claveAnonima: string;

  constructor(config: ConfigService<VariablesEntorno, true>) {
    this.url = config.get('SUPABASE_URL', { infer: true });
    this.claveAnonima = config.get('SUPABASE_ANON_KEY', { infer: true });
  }

  clienteDeUsuario(token: string): ClienteSupabase {
    return createClient<Database>(this.url, this.claveAnonima, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
  }

  // Solo para iniciar o renovar sesión en Supabase Auth.
  clienteAnonimo(): ClienteSupabase {
    return createClient<Database>(this.url, this.claveAnonima, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
  }
}
