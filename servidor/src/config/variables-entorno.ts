import { plainToInstance, Transform } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUrl,
  Max,
  Min,
  validateSync,
} from 'class-validator';

export enum Entorno {
  Desarrollo = 'development',
  Produccion = 'production',
  Prueba = 'test',
}

export class VariablesEntorno {
  @IsEnum(Entorno)
  NODE_ENV: Entorno = Entorno.Desarrollo;

  @Transform(({ value }) => (value === undefined ? 3000 : Number(value)))
  @IsInt()
  @Min(1)
  @Max(65535)
  PUERTO: number = 3000;

  @IsUrl({ require_tld: false, require_protocol: true })
  SUPABASE_URL: string;

  // Clave anon, nunca la service_role: el servidor actúa con el token del usuario.
  @IsString()
  @IsNotEmpty()
  SUPABASE_ANON_KEY: string;

  // Separados por coma.
  @IsOptional()
  @IsString()
  CORS_ORIGENES?: string;
}

export function validarVariablesEntorno(config: Record<string, unknown>): VariablesEntorno {
  const variables = plainToInstance(VariablesEntorno, config, { exposeDefaultValues: true });
  const errores = validateSync(variables, { skipMissingProperties: false });
  if (errores.length > 0) {
    const detalle = errores
      .map((e) => `${e.property}: ${Object.values(e.constraints ?? {}).join(', ')}`)
      .join('; ');
    throw new Error(`Variables de entorno inválidas -> ${detalle}`);
  }
  return variables;
}
