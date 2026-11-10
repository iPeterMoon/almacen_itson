export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      activos: {
        Row: {
          actualizado_en: string | null;
          codigo: string;
          creado_en: string;
          creado_por: string;
          estado: string;
          id: number;
          marca: string | null;
          modelo: string;
          nombre: string;
          numero_serie: string;
          ubicacion_id: number;
          valor: number | null;
        };
        Insert: {
          actualizado_en?: string | null;
          codigo: string;
          creado_en?: string;
          creado_por?: string;
          estado?: string;
          id?: never;
          marca?: string | null;
          modelo: string;
          nombre: string;
          numero_serie: string;
          ubicacion_id: number;
          valor?: number | null;
        };
        Update: {
          actualizado_en?: string | null;
          codigo?: string;
          creado_en?: string;
          creado_por?: string;
          estado?: string;
          id?: never;
          marca?: string | null;
          modelo?: string;
          nombre?: string;
          numero_serie?: string;
          ubicacion_id?: number;
          valor?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: 'activos_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activos_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'ubicaciones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'activos_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['ubicacion_id'];
          },
        ];
      };
      ajustes_inventario: {
        Row: {
          cantidad_anterior: number;
          cantidad_nueva: number;
          creado_en: string;
          creado_por: string;
          diferencia: number | null;
          folio: string;
          id: number;
          motivo: string;
          producto_id: number;
          ubicacion_id: number;
        };
        Insert: {
          cantidad_anterior: number;
          cantidad_nueva: number;
          creado_en?: string;
          creado_por?: string;
          diferencia?: number | null;
          folio: string;
          id?: never;
          motivo: string;
          producto_id: number;
          ubicacion_id: number;
        };
        Update: {
          cantidad_anterior?: number;
          cantidad_nueva?: number;
          creado_en?: string;
          creado_por?: string;
          diferencia?: number | null;
          folio?: string;
          id?: never;
          motivo?: string;
          producto_id?: number;
          ubicacion_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'ajustes_inventario_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'ajustes_inventario_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'ajustes_inventario_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'ubicaciones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'ajustes_inventario_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['ubicacion_id'];
          },
        ];
      };
      almacenes: {
        Row: {
          activo: boolean;
          campus_id: number;
          id: number;
          nombre: string;
        };
        Insert: {
          activo?: boolean;
          campus_id: number;
          id?: never;
          nombre: string;
        };
        Update: {
          activo?: boolean;
          campus_id?: number;
          id?: never;
          nombre?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'almacenes_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
        ];
      };
      autorizaciones: {
        Row: {
          boleta_id: number;
          comentario: string | null;
          estado: string;
          id: number;
          resuelto_en: string | null;
          resuelto_por: string | null;
          solicitado_en: string;
          solicitado_por: string;
          supervisor_id: string;
        };
        Insert: {
          boleta_id: number;
          comentario?: string | null;
          estado?: string;
          id?: never;
          resuelto_en?: string | null;
          resuelto_por?: string | null;
          solicitado_en?: string;
          solicitado_por?: string;
          supervisor_id: string;
        };
        Update: {
          boleta_id?: number;
          comentario?: string | null;
          estado?: string;
          id?: never;
          resuelto_en?: string | null;
          resuelto_por?: string | null;
          solicitado_en?: string;
          solicitado_por?: string;
          supervisor_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'autorizaciones_boleta_id_fkey';
            columns: ['boleta_id'];
            isOneToOne: true;
            referencedRelation: 'boletas';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'autorizaciones_resuelto_por_fkey';
            columns: ['resuelto_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'autorizaciones_solicitado_por_fkey';
            columns: ['solicitado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'autorizaciones_supervisor_id_fkey';
            columns: ['supervisor_id'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      boletas: {
        Row: {
          autorizo_nombre: string | null;
          campus_id: number;
          creado_en: string;
          creado_por: string;
          entregado_en: string | null;
          entregado_por: string | null;
          estado: string;
          firma_entrega_path: string | null;
          firma_recibe_path: string | null;
          folio: string;
          id: number;
          numero_solicitud: string | null;
          solicitante_nombre: string;
          solicitante_unidad: string | null;
          trabajador_id: number | null;
          zona_id: number | null;
        };
        Insert: {
          autorizo_nombre?: string | null;
          campus_id: number;
          creado_en?: string;
          creado_por?: string;
          entregado_en?: string | null;
          entregado_por?: string | null;
          estado: string;
          firma_entrega_path?: string | null;
          firma_recibe_path?: string | null;
          folio: string;
          id?: never;
          numero_solicitud?: string | null;
          solicitante_nombre: string;
          solicitante_unidad?: string | null;
          trabajador_id?: number | null;
          zona_id?: number | null;
        };
        Update: {
          autorizo_nombre?: string | null;
          campus_id?: number;
          creado_en?: string;
          creado_por?: string;
          entregado_en?: string | null;
          entregado_por?: string | null;
          estado?: string;
          firma_entrega_path?: string | null;
          firma_recibe_path?: string | null;
          folio?: string;
          id?: never;
          numero_solicitud?: string | null;
          solicitante_nombre?: string;
          solicitante_unidad?: string | null;
          trabajador_id?: number | null;
          zona_id?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: 'boletas_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_entregado_por_fkey';
            columns: ['entregado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_trabajador_id_fkey';
            columns: ['trabajador_id'];
            isOneToOne: false;
            referencedRelation: 'trabajadores';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_zona_id_fkey';
            columns: ['zona_id'];
            isOneToOne: false;
            referencedRelation: 'zonas';
            referencedColumns: ['id'];
          },
        ];
      };
      boletas_herramientas: {
        Row: {
          activo_id: number;
          boleta_id: number;
          dias_prestamo: number;
          id: number;
          solicitante_con_vencido: boolean;
        };
        Insert: {
          activo_id: number;
          boleta_id: number;
          dias_prestamo: number;
          id?: never;
          solicitante_con_vencido?: boolean;
        };
        Update: {
          activo_id?: number;
          boleta_id?: number;
          dias_prestamo?: number;
          id?: never;
          solicitante_con_vencido?: boolean;
        };
        Relationships: [
          {
            foreignKeyName: 'boletas_herramientas_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'activos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_herramientas_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'vista_seguimiento_prestamos';
            referencedColumns: ['activo_id'];
          },
          {
            foreignKeyName: 'boletas_herramientas_boleta_id_fkey';
            columns: ['boleta_id'];
            isOneToOne: false;
            referencedRelation: 'boletas';
            referencedColumns: ['id'];
          },
        ];
      };
      boletas_materiales: {
        Row: {
          boleta_id: number;
          cantidad: number;
          cantidad_base: number;
          comentario: string | null;
          excede_limite: boolean;
          excede_periodicidad: boolean;
          id: number;
          motivo_excepcion: string | null;
          presentacion_id: number | null;
          producto_id: number;
        };
        Insert: {
          boleta_id: number;
          cantidad: number;
          cantidad_base: number;
          comentario?: string | null;
          excede_limite?: boolean;
          excede_periodicidad?: boolean;
          id?: never;
          motivo_excepcion?: string | null;
          presentacion_id?: number | null;
          producto_id: number;
        };
        Update: {
          boleta_id?: number;
          cantidad?: number;
          cantidad_base?: number;
          comentario?: string | null;
          excede_limite?: boolean;
          excede_periodicidad?: boolean;
          id?: never;
          motivo_excepcion?: string | null;
          presentacion_id?: number | null;
          producto_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'boletas_materiales_boleta_id_fkey';
            columns: ['boleta_id'];
            isOneToOne: false;
            referencedRelation: 'boletas';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_materiales_presentacion_id_fkey';
            columns: ['presentacion_id'];
            isOneToOne: false;
            referencedRelation: 'presentaciones_producto';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_materiales_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
        ];
      };
      campus: {
        Row: {
          activo: boolean;
          clave: string;
          id: number;
          nombre: string;
          unidad_id: number;
        };
        Insert: {
          activo?: boolean;
          clave: string;
          id?: never;
          nombre: string;
          unidad_id: number;
        };
        Update: {
          activo?: boolean;
          clave?: string;
          id?: never;
          nombre?: string;
          unidad_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'campus_unidad_id_fkey';
            columns: ['unidad_id'];
            isOneToOne: false;
            referencedRelation: 'unidades';
            referencedColumns: ['id'];
          },
        ];
      };
      categorias: {
        Row: {
          activo: boolean;
          id: number;
          nombre: string;
        };
        Insert: {
          activo?: boolean;
          id?: never;
          nombre: string;
        };
        Update: {
          activo?: boolean;
          id?: never;
          nombre?: string;
        };
        Relationships: [];
      };
      devoluciones: {
        Row: {
          condicion: string;
          creado_por: string;
          descripcion_dano: string | null;
          devuelto_en: string;
          dias_retraso: number;
          firma_entrega_path: string;
          firma_recibe_path: string;
          folio: string;
          id: number;
          observaciones: string | null;
          prestamo_id: number;
        };
        Insert: {
          condicion: string;
          creado_por?: string;
          descripcion_dano?: string | null;
          devuelto_en?: string;
          dias_retraso: number;
          firma_entrega_path: string;
          firma_recibe_path: string;
          folio: string;
          id?: never;
          observaciones?: string | null;
          prestamo_id: number;
        };
        Update: {
          condicion?: string;
          creado_por?: string;
          descripcion_dano?: string | null;
          devuelto_en?: string;
          dias_retraso?: number;
          firma_entrega_path?: string;
          firma_recibe_path?: string;
          folio?: string;
          id?: never;
          observaciones?: string | null;
          prestamo_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'devoluciones_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'devoluciones_prestamo_id_fkey';
            columns: ['prestamo_id'];
            isOneToOne: true;
            referencedRelation: 'prestamos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'devoluciones_prestamo_id_fkey';
            columns: ['prestamo_id'];
            isOneToOne: true;
            referencedRelation: 'vista_seguimiento_prestamos';
            referencedColumns: ['prestamo_id'];
          },
        ];
      };
      entradas: {
        Row: {
          boleta_material_id: number | null;
          cantidad: number;
          cantidad_base: number;
          creado_en: string;
          creado_por: string;
          folio: string;
          id: number;
          motivo: string;
          numero_factura: string | null;
          numero_partida: string | null;
          observaciones: string | null;
          origen_campus_id: number | null;
          origen_detalle: string | null;
          origen_unidad_id: number | null;
          presentacion_id: number | null;
          producto_id: number;
          proveedor_id: number | null;
          tipo_origen: string | null;
          ubicacion_id: number;
        };
        Insert: {
          boleta_material_id?: number | null;
          cantidad: number;
          cantidad_base: number;
          creado_en?: string;
          creado_por?: string;
          folio: string;
          id?: never;
          motivo: string;
          numero_factura?: string | null;
          numero_partida?: string | null;
          observaciones?: string | null;
          origen_campus_id?: number | null;
          origen_detalle?: string | null;
          origen_unidad_id?: number | null;
          presentacion_id?: number | null;
          producto_id: number;
          proveedor_id?: number | null;
          tipo_origen?: string | null;
          ubicacion_id: number;
        };
        Update: {
          boleta_material_id?: number | null;
          cantidad?: number;
          cantidad_base?: number;
          creado_en?: string;
          creado_por?: string;
          folio?: string;
          id?: never;
          motivo?: string;
          numero_factura?: string | null;
          numero_partida?: string | null;
          observaciones?: string | null;
          origen_campus_id?: number | null;
          origen_detalle?: string | null;
          origen_unidad_id?: number | null;
          presentacion_id?: number | null;
          producto_id?: number;
          proveedor_id?: number | null;
          tipo_origen?: string | null;
          ubicacion_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'entradas_boleta_material_id_fkey';
            columns: ['boleta_material_id'];
            isOneToOne: false;
            referencedRelation: 'boletas_materiales';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_origen_campus_id_fkey';
            columns: ['origen_campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_origen_unidad_id_fkey';
            columns: ['origen_unidad_id'];
            isOneToOne: false;
            referencedRelation: 'unidades';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_presentacion_id_fkey';
            columns: ['presentacion_id'];
            isOneToOne: false;
            referencedRelation: 'presentaciones_producto';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_proveedor_id_fkey';
            columns: ['proveedor_id'];
            isOneToOne: false;
            referencedRelation: 'proveedores';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'ubicaciones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'entradas_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['ubicacion_id'];
          },
        ];
      };
      existencias: {
        Row: {
          actualizado_en: string;
          cantidad: number;
          producto_id: number;
          ubicacion_id: number;
        };
        Insert: {
          actualizado_en?: string;
          cantidad?: number;
          producto_id: number;
          ubicacion_id: number;
        };
        Update: {
          actualizado_en?: string;
          cantidad?: number;
          producto_id?: number;
          ubicacion_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'existencias_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'existencias_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'ubicaciones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'existencias_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['ubicacion_id'];
          },
        ];
      };
      folios_consecutivos: {
        Row: {
          anio: number;
          tipo: string;
          ultimo: number;
        };
        Insert: {
          anio: number;
          tipo: string;
          ultimo: number;
        };
        Update: {
          anio?: number;
          tipo?: string;
          ultimo?: number;
        };
        Relationships: [];
      };
      historial_estados_activo: {
        Row: {
          activo_id: number;
          creado_en: string;
          creado_por: string | null;
          estado_anterior: string | null;
          estado_nuevo: string;
          folio: string | null;
          id: number;
          motivo: string;
        };
        Insert: {
          activo_id: number;
          creado_en?: string;
          creado_por?: string | null;
          estado_anterior?: string | null;
          estado_nuevo: string;
          folio?: string | null;
          id?: never;
          motivo: string;
        };
        Update: {
          activo_id?: number;
          creado_en?: string;
          creado_por?: string | null;
          estado_anterior?: string | null;
          estado_nuevo?: string;
          folio?: string | null;
          id?: never;
          motivo?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'historial_estados_activo_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'activos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'historial_estados_activo_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'vista_seguimiento_prestamos';
            referencedColumns: ['activo_id'];
          },
          {
            foreignKeyName: 'historial_estados_activo_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      limites_material_zona: {
        Row: {
          cada_dias: number;
          cantidad_max: number;
          producto_id: number;
          zona_id: number;
        };
        Insert: {
          cada_dias: number;
          cantidad_max: number;
          producto_id: number;
          zona_id: number;
        };
        Update: {
          cada_dias?: number;
          cantidad_max?: number;
          producto_id?: number;
          zona_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'limites_material_zona_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'limites_material_zona_zona_id_fkey';
            columns: ['zona_id'];
            isOneToOne: false;
            referencedRelation: 'zonas';
            referencedColumns: ['id'];
          },
        ];
      };
      movimientos_inventario: {
        Row: {
          ajuste_id: number | null;
          boleta_material_id: number | null;
          cantidad: number;
          creado_en: string;
          creado_por: string;
          entrada_id: number | null;
          existencia_resultante: number;
          folio: string;
          id: number;
          producto_id: number;
          tipo: string;
          ubicacion_id: number;
        };
        Insert: {
          ajuste_id?: number | null;
          boleta_material_id?: number | null;
          cantidad: number;
          creado_en?: string;
          creado_por?: string;
          entrada_id?: number | null;
          existencia_resultante: number;
          folio: string;
          id?: never;
          producto_id: number;
          tipo: string;
          ubicacion_id: number;
        };
        Update: {
          ajuste_id?: number | null;
          boleta_material_id?: number | null;
          cantidad?: number;
          creado_en?: string;
          creado_por?: string;
          entrada_id?: number | null;
          existencia_resultante?: number;
          folio?: string;
          id?: never;
          producto_id?: number;
          tipo?: string;
          ubicacion_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'movimientos_inventario_ajuste_id_fkey';
            columns: ['ajuste_id'];
            isOneToOne: false;
            referencedRelation: 'ajustes_inventario';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_boleta_material_id_fkey';
            columns: ['boleta_material_id'];
            isOneToOne: false;
            referencedRelation: 'boletas_materiales';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_entrada_id_fkey';
            columns: ['entrada_id'];
            isOneToOne: false;
            referencedRelation: 'entradas';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'ubicaciones';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'movimientos_inventario_ubicacion_id_fkey';
            columns: ['ubicacion_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['ubicacion_id'];
          },
        ];
      };
      notificaciones: {
        Row: {
          creado_en: string;
          fecha_aviso: string;
          id: number;
          leida_en: string | null;
          mensaje: string;
          referencia_id: number;
          referencia_tipo: string;
          tipo: string;
          titulo: string;
          usuario_id: string;
        };
        Insert: {
          creado_en?: string;
          fecha_aviso: string;
          id?: never;
          leida_en?: string | null;
          mensaje: string;
          referencia_id: number;
          referencia_tipo: string;
          tipo: string;
          titulo: string;
          usuario_id: string;
        };
        Update: {
          creado_en?: string;
          fecha_aviso?: string;
          id?: never;
          leida_en?: string | null;
          mensaje?: string;
          referencia_id?: number;
          referencia_tipo?: string;
          tipo?: string;
          titulo?: string;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'notificaciones_usuario_id_fkey';
            columns: ['usuario_id'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      presentaciones_producto: {
        Row: {
          activo: boolean;
          factor_a_base: number;
          id: number;
          nombre: string;
          producto_id: number;
        };
        Insert: {
          activo?: boolean;
          factor_a_base: number;
          id?: never;
          nombre: string;
          producto_id: number;
        };
        Update: {
          activo?: boolean;
          factor_a_base?: number;
          id?: never;
          nombre?: string;
          producto_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'presentaciones_producto_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
        ];
      };
      prestamos: {
        Row: {
          activo_id: number;
          boleta_herramienta_id: number;
          creado_por: string;
          dias_prestamo: number;
          estado: string;
          fecha_prevista: string;
          folio: string;
          id: number;
          prestado_en: string;
        };
        Insert: {
          activo_id: number;
          boleta_herramienta_id: number;
          creado_por?: string;
          dias_prestamo: number;
          estado?: string;
          fecha_prevista: string;
          folio: string;
          id?: never;
          prestado_en?: string;
        };
        Update: {
          activo_id?: number;
          boleta_herramienta_id?: number;
          creado_por?: string;
          dias_prestamo?: number;
          estado?: string;
          fecha_prevista?: string;
          folio?: string;
          id?: never;
          prestado_en?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'prestamos_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'activos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'prestamos_activo_id_fkey';
            columns: ['activo_id'];
            isOneToOne: false;
            referencedRelation: 'vista_seguimiento_prestamos';
            referencedColumns: ['activo_id'];
          },
          {
            foreignKeyName: 'prestamos_boleta_herramienta_id_fkey';
            columns: ['boleta_herramienta_id'];
            isOneToOne: true;
            referencedRelation: 'boletas_herramientas';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'prestamos_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      productos: {
        Row: {
          activo: boolean;
          actualizado_en: string | null;
          actualizado_por: string | null;
          alias: string | null;
          categoria_id: number;
          codigo: string;
          creado_en: string;
          creado_por: string;
          id: number;
          imagen_path: string | null;
          manejo_seguro: string | null;
          mas_comunes: boolean;
          nombre_estandar: string;
          tipo: string;
          unidad_base_id: number;
        };
        Insert: {
          activo?: boolean;
          actualizado_en?: string | null;
          actualizado_por?: string | null;
          alias?: string | null;
          categoria_id: number;
          codigo: string;
          creado_en?: string;
          creado_por?: string;
          id?: never;
          imagen_path?: string | null;
          manejo_seguro?: string | null;
          mas_comunes?: boolean;
          nombre_estandar: string;
          tipo: string;
          unidad_base_id: number;
        };
        Update: {
          activo?: boolean;
          actualizado_en?: string | null;
          actualizado_por?: string | null;
          alias?: string | null;
          categoria_id?: number;
          codigo?: string;
          creado_en?: string;
          creado_por?: string;
          id?: never;
          imagen_path?: string | null;
          manejo_seguro?: string | null;
          mas_comunes?: boolean;
          nombre_estandar?: string;
          tipo?: string;
          unidad_base_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'productos_actualizado_por_fkey';
            columns: ['actualizado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'productos_categoria_id_fkey';
            columns: ['categoria_id'];
            isOneToOne: false;
            referencedRelation: 'categorias';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'productos_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'productos_unidad_base_id_fkey';
            columns: ['unidad_base_id'];
            isOneToOne: false;
            referencedRelation: 'unidades_medida';
            referencedColumns: ['id'];
          },
        ];
      };
      proveedores: {
        Row: {
          activo: boolean;
          creado_en: string;
          id: number;
          nombre: string;
        };
        Insert: {
          activo?: boolean;
          creado_en?: string;
          id?: never;
          nombre: string;
        };
        Update: {
          activo?: boolean;
          creado_en?: string;
          id?: never;
          nombre?: string;
        };
        Relationships: [];
      };
      reportes_robo_extravio: {
        Row: {
          creado_por: string;
          declaracion: string;
          folio: string;
          id: number;
          prestamo_id: number;
          reportado_en: string;
        };
        Insert: {
          creado_por?: string;
          declaracion: string;
          folio: string;
          id?: never;
          prestamo_id: number;
          reportado_en?: string;
        };
        Update: {
          creado_por?: string;
          declaracion?: string;
          folio?: string;
          id?: never;
          prestamo_id?: number;
          reportado_en?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'reportes_robo_extravio_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'reportes_robo_extravio_prestamo_id_fkey';
            columns: ['prestamo_id'];
            isOneToOne: true;
            referencedRelation: 'prestamos';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'reportes_robo_extravio_prestamo_id_fkey';
            columns: ['prestamo_id'];
            isOneToOne: true;
            referencedRelation: 'vista_seguimiento_prestamos';
            referencedColumns: ['prestamo_id'];
          },
        ];
      };
      trabajadores: {
        Row: {
          activo: boolean;
          campus_id: number;
          compania: string | null;
          creado_en: string;
          creado_por: string | null;
          dependencia: string;
          id: number;
          nombre: string;
          puesto: string | null;
          tipo: string;
        };
        Insert: {
          activo?: boolean;
          campus_id: number;
          compania?: string | null;
          creado_en?: string;
          creado_por?: string | null;
          dependencia: string;
          id?: never;
          nombre: string;
          puesto?: string | null;
          tipo: string;
        };
        Update: {
          activo?: boolean;
          campus_id?: number;
          compania?: string | null;
          creado_en?: string;
          creado_por?: string | null;
          dependencia?: string;
          id?: never;
          nombre?: string;
          puesto?: string | null;
          tipo?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'trabajadores_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'trabajadores_creado_por_fkey';
            columns: ['creado_por'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      trabajadores_zonas: {
        Row: {
          trabajador_id: number;
          zona_id: number;
        };
        Insert: {
          trabajador_id: number;
          zona_id: number;
        };
        Update: {
          trabajador_id?: number;
          zona_id?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'trabajadores_zonas_trabajador_id_fkey';
            columns: ['trabajador_id'];
            isOneToOne: false;
            referencedRelation: 'trabajadores';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'trabajadores_zonas_zona_id_fkey';
            columns: ['zona_id'];
            isOneToOne: false;
            referencedRelation: 'zonas';
            referencedColumns: ['id'];
          },
        ];
      };
      ubicaciones: {
        Row: {
          almacen_id: number;
          descripcion: string | null;
          id: number;
        };
        Insert: {
          almacen_id: number;
          descripcion?: string | null;
          id?: never;
        };
        Update: {
          almacen_id?: number;
          descripcion?: string | null;
          id?: never;
        };
        Relationships: [
          {
            foreignKeyName: 'ubicaciones_almacen_id_fkey';
            columns: ['almacen_id'];
            isOneToOne: false;
            referencedRelation: 'almacenes';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'ubicaciones_almacen_id_fkey';
            columns: ['almacen_id'];
            isOneToOne: false;
            referencedRelation: 'vista_existencias_por_ubicacion';
            referencedColumns: ['almacen_id'];
          },
        ];
      };
      unidades: {
        Row: {
          activo: boolean;
          id: number;
          nombre: string;
        };
        Insert: {
          activo?: boolean;
          id?: never;
          nombre: string;
        };
        Update: {
          activo?: boolean;
          id?: never;
          nombre?: string;
        };
        Relationships: [];
      };
      unidades_medida: {
        Row: {
          activo: boolean;
          clave: string;
          id: number;
          nombre: string;
        };
        Insert: {
          activo?: boolean;
          clave: string;
          id?: never;
          nombre: string;
        };
        Update: {
          activo?: boolean;
          clave?: string;
          id?: never;
          nombre?: string;
        };
        Relationships: [];
      };
      usuarios: {
        Row: {
          activo: boolean;
          campus_id: number;
          creado_en: string;
          id: string;
          nombre: string;
          rol: string;
        };
        Insert: {
          activo?: boolean;
          campus_id: number;
          creado_en?: string;
          id: string;
          nombre: string;
          rol: string;
        };
        Update: {
          activo?: boolean;
          campus_id?: number;
          creado_en?: string;
          id?: string;
          nombre?: string;
          rol?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'usuarios_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
        ];
      };
      usuarios_campus_adicionales: {
        Row: {
          campus_id: number;
          usuario_id: string;
        };
        Insert: {
          campus_id: number;
          usuario_id: string;
        };
        Update: {
          campus_id?: number;
          usuario_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'usuarios_campus_adicionales_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'usuarios_campus_adicionales_usuario_id_fkey';
            columns: ['usuario_id'];
            isOneToOne: false;
            referencedRelation: 'usuarios';
            referencedColumns: ['id'];
          },
        ];
      };
      zonas: {
        Row: {
          activa: boolean;
          campus_id: number;
          edificio: string | null;
          id: number;
          nombre: string;
          num_aulas: number | null;
          num_banos: number | null;
          num_cubiculos: number | null;
          num_laboratorios: number | null;
          piso: string | null;
        };
        Insert: {
          activa?: boolean;
          campus_id: number;
          edificio?: string | null;
          id?: never;
          nombre: string;
          num_aulas?: number | null;
          num_banos?: number | null;
          num_cubiculos?: number | null;
          num_laboratorios?: number | null;
          piso?: string | null;
        };
        Update: {
          activa?: boolean;
          campus_id?: number;
          edificio?: string | null;
          id?: never;
          nombre?: string;
          num_aulas?: number | null;
          num_banos?: number | null;
          num_cubiculos?: number | null;
          num_laboratorios?: number | null;
          piso?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'zonas_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
        ];
      };
    };
    Views: {
      vista_existencias_por_ubicacion: {
        Row: {
          actualizado_en: string | null;
          almacen: string | null;
          almacen_id: number | null;
          campus_id: number | null;
          cantidad: number | null;
          producto_id: number | null;
          ubicacion: string | null;
          ubicacion_id: number | null;
        };
        Relationships: [
          {
            foreignKeyName: 'almacenes_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'existencias_producto_id_fkey';
            columns: ['producto_id'];
            isOneToOne: false;
            referencedRelation: 'productos';
            referencedColumns: ['id'];
          },
        ];
      };
      vista_historial_movimientos: {
        Row: {
          alias: string | null;
          almacen: string | null;
          campus_id: number | null;
          cantidad: number | null;
          codigo: string | null;
          creado_en: string | null;
          existencia_resultante: number | null;
          folio: string | null;
          id: number | null;
          motivo_ajuste: string | null;
          motivo_entrada: string | null;
          nombre_estandar: string | null;
          registrado_por: string | null;
          tipo: string | null;
          ubicacion: string | null;
          unidad: string | null;
        };
        Relationships: [
          {
            foreignKeyName: 'almacenes_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
        ];
      };
      vista_seguimiento_prestamos: {
        Row: {
          activo_id: number | null;
          boleta_folio: string | null;
          campus_id: number | null;
          codigo: string | null;
          condicion: string | null;
          custodio: string | null;
          devuelto_en: string | null;
          dias_prestamo: number | null;
          dias_restantes: number | null;
          dias_retraso: number | null;
          estado: string | null;
          fecha_prevista: string | null;
          folio: string | null;
          herramienta: string | null;
          modelo: string | null;
          numero_serie: string | null;
          numero_solicitud: string | null;
          prestado_en: string | null;
          prestamo_id: number | null;
          seguimiento: string | null;
          trabajador_id: number | null;
        };
        Relationships: [
          {
            foreignKeyName: 'almacenes_campus_id_fkey';
            columns: ['campus_id'];
            isOneToOne: false;
            referencedRelation: 'campus';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'boletas_trabajador_id_fkey';
            columns: ['trabajador_id'];
            isOneToOne: false;
            referencedRelation: 'trabajadores';
            referencedColumns: ['id'];
          },
        ];
      };
    };
    Functions: {
      aplicar_movimiento_inventario: {
        Args: {
          p_ajuste_id?: number;
          p_boleta_material_id?: number;
          p_cantidad: number;
          p_entrada_id?: number;
          p_folio: string;
          p_producto_id: number;
          p_tipo: string;
          p_ubicacion_id: number;
        };
        Returns: number;
      };
      buscar_productos: {
        Args: {
          p_almacen_id?: number;
          p_categoria_id?: number;
          p_desplazar?: number;
          p_limite?: number;
          p_texto?: string;
          p_tipo?: string;
          p_unidad_id?: number;
        };
        Returns: {
          alias: string;
          categoria: string;
          codigo: string;
          existencia: number;
          mas_comunes: boolean;
          nombre_estandar: string;
          producto_id: number;
          tipo: string;
          ultima_entrada: string;
          ultima_salida: string;
          unidad: string;
        }[];
      };
      cambiar_estado_activo: {
        Args: { p_activo_id: number; p_estado: string; p_motivo: string };
        Returns: string;
      };
      confirmar_entrega: {
        Args: {
          p_boleta_id: number;
          p_firma_entrega: string;
          p_firma_recibe: string;
        };
        Returns: string;
      };
      convertir_a_unidad_base: {
        Args: {
          p_cantidad: number;
          p_presentacion_id: number;
          p_producto_id: number;
        };
        Returns: number;
      };
      crear_boleta: {
        Args: {
          p_autorizo_nombre?: string;
          p_campus_id?: number;
          p_firma_entrega?: string;
          p_firma_recibe?: string;
          p_herramientas?: Json;
          p_materiales?: Json;
          p_numero_solicitud?: string;
          p_solicitante_nombre?: string;
          p_solicitante_unidad?: string;
          p_supervisor_id?: string;
          p_trabajador_id?: number;
          p_zona_id?: number;
        };
        Returns: {
          alertas: Json;
          boleta_id: number;
          estado: string;
          folio: string;
        }[];
      };
      obtener_notificaciones: {
        Args: never;
        Returns: {
          creado_en: string;
          fecha_aviso: string;
          id: number;
          leida_en: string | null;
          mensaje: string;
          referencia_id: number;
          referencia_tipo: string;
          tipo: string;
          titulo: string;
          usuario_id: string;
        }[];
        SetofOptions: {
          from: '*';
          to: 'notificaciones';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      obtener_o_crear_ubicacion: {
        Args: { p_almacen_id: number; p_descripcion: string };
        Returns: number;
      };
      registrar_activo: {
        Args: {
          p_almacen_id: number;
          p_codigo: string;
          p_marca?: string;
          p_modelo: string;
          p_nombre: string;
          p_numero_serie: string;
          p_ubicacion?: string;
          p_valor?: number;
        };
        Returns: {
          activo_id: number;
          codigo: string;
          estado: string;
        }[];
      };
      registrar_ajuste: {
        Args: {
          p_almacen_id: number;
          p_cantidad_nueva: number;
          p_motivo: string;
          p_producto_id: number;
          p_ubicacion?: string;
        };
        Returns: {
          ajuste_id: number;
          diferencia: number;
          folio: string;
        }[];
      };
      registrar_devolucion: {
        Args: {
          p_condicion: string;
          p_descripcion_dano?: string;
          p_firma_entrega: string;
          p_firma_recibe: string;
          p_observaciones?: string;
          p_prestamo_id: number;
        };
        Returns: {
          devolucion_id: number;
          dias_retraso: number;
          estado_activo: string;
          folio: string;
        }[];
      };
      registrar_entrada: {
        Args: {
          p_almacen_id: number;
          p_cantidad: number;
          p_motivo: string;
          p_numero_factura?: string;
          p_numero_partida?: string;
          p_observaciones?: string;
          p_origen_campus_id?: number;
          p_origen_detalle?: string;
          p_origen_unidad_id?: number;
          p_presentacion_id?: number;
          p_producto_id: number;
          p_proveedor_id?: number;
          p_proveedor_nuevo?: string;
          p_tipo_origen?: string;
          p_ubicacion?: string;
        };
        Returns: {
          entrada_id: number;
          existencia_ubicacion: number;
          folio: string;
        }[];
      };
      registrar_reingreso: {
        Args: {
          p_almacen_id: number;
          p_boleta_material_id: number;
          p_cantidad: number;
          p_observaciones?: string;
          p_presentacion_id?: number;
          p_ubicacion?: string;
        };
        Returns: {
          entrada_id: number;
          existencia_ubicacion: number;
          folio: string;
        }[];
      };
      reportar_robo_extravio: {
        Args: { p_declaracion: string; p_prestamo_id: number };
        Returns: string;
      };
      resolver_autorizacion: {
        Args: {
          p_autorizar: boolean;
          p_boleta_id: number;
          p_comentario?: string;
        };
        Returns: string;
      };
      siguiente_folio: { Args: { p_tipo: string }; Returns: string };
      validar_activo: {
        Args: { p_codigo: string; p_trabajador_id?: number };
        Returns: {
          activo_id: number;
          codigo: string;
          custodio_actual: string;
          estado: string;
          fecha_prevista: string;
          modelo: string;
          nombre: string;
          numero_serie: string;
          solicitante_con_vencido: boolean;
        }[];
      };
      validar_almacen: { Args: { p_almacen_id: number }; Returns: number };
      validar_material: {
        Args: {
          p_campus_id?: number;
          p_cantidad: number;
          p_presentacion_id?: number;
          p_producto_id: number;
          p_trabajador_id?: number;
          p_zona_id?: number;
        };
        Returns: {
          dias_faltantes: number;
          disponible: number;
          entregado_periodo: number;
          excede_limite: boolean;
          excede_periodicidad: boolean;
          limite_cada_dias: number;
          limite_cantidad: number;
          proxima_entrega: string;
          stock_suficiente: boolean;
          ultima_entrega: string;
        }[];
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {},
  },
} as const;
