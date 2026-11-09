// Va en setupFiles porque AppModule valida el entorno al importarse.
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://proyecto-prueba.supabase.co';
process.env.SUPABASE_ANON_KEY = 'clave-de-prueba';
