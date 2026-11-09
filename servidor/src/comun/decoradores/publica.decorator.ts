import { SetMetadata } from '@nestjs/common';

export const ES_PUBLICA = 'esPublica';

export const Publica = () => SetMetadata(ES_PUBLICA, true);
