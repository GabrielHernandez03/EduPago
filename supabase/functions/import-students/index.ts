// supabase/functions/import-students/index.ts
//
// Despliega con:
//   supabase functions deploy import-students --no-verify-jwt
//
// Body recibido:
//   {
//     colegio_id: string,
//     rows: StudentRow[]
//   }
//
// Cada StudentRow:
//   {
//     cedula_estudiante:    string   (obligatorio)
//     nombres_estudiante:   string   (obligatorio)
//     apellidos_estudiante: string   (obligatorio)
//     fecha_nacimiento?:    string   (ISO yyyy-mm-dd)
//     grado_seccion?:       string
//     representantes?:      RepData[]  ← N representantes, sin límite
//   }
//
// RepData:
//   {
//     cedula:       string  (obligatorio)
//     nombres:      string  (obligatorio)
//     apellidos:    string  (obligatorio)
//     telefono?:    string
//     email?:       string
//     parentesco?:  string
//     es_financiero?: string | boolean
//   }
//
// Respuesta:
//   {
//     exitosos: number,
//     errores:  RowError[],
//     total:    number
//   }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface RepData {
  cedula:        string;
  nombres:       string;
  apellidos:     string;
  telefono?:     string;
  email?:        string;
  parentesco?:   string;
  es_financiero?: string | boolean;
}

interface StudentRow {
  cedula_estudiante:    string;
  nombres_estudiante:   string;
  apellidos_estudiante: string;
  fecha_nacimiento?:    string;
  grado_seccion?:       string;
  representantes?:      RepData[];
}

interface RowError {
  fila:   number;
  cedula: string;
  motivo: string;
}

interface ImportResponse {
  exitosos: number;
  errores:  RowError[];
  total:    number;
}

// ---------------------------------------------------------------------------
// Constantes de validación
// ---------------------------------------------------------------------------

const MAX_REPS_PER_STUDENT = 10; // límite razonable; evita abusos

const PARENTESCOS_VALIDOS = new Set([
  "madre", "padre", "tutor", "tutora", "abuelo", "abuela",
  "tío", "tía", "hermano", "hermana", "familiar", "otro",
]);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function clean(v: string | undefined | null): string {
  return (v ?? "").trim();
}

/** Acepta booleano nativo o string "si/no/true/false/1/0/…" */
function parseBool(v: string | boolean | undefined | null): boolean {
  if (typeof v === "boolean") return v;
  const s = clean(v as string).toLowerCase();
  // Vacío → true (si no se especifica, asumimos responsable financiero)
  if (s === "") return true;
  return !["no", "n", "false", "0", "inactivo"].includes(s);
}

function isValidDate(s: string): boolean {
  // Acepta yyyy-mm-dd
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return false;
  const d = new Date(s);
  return !isNaN(d.getTime()) && d.getFullYear() > 1980 && d <= new Date();
}

/** Valida un objeto RepData y devuelve un array de mensajes de error (vacío = OK). */
function validateRep(rep: RepData, idx: number): string[] {
  const errs: string[] = [];
  const tag = `representante[${idx + 1}]`;

  if (!clean(rep.cedula))    errs.push(`${tag}: cedula es obligatoria.`);
  if (!clean(rep.nombres))   errs.push(`${tag}: nombres es obligatorio.`);
  if (!clean(rep.apellidos)) errs.push(`${tag}: apellidos es obligatorio.`);

  if (rep.parentesco) {
    const p = clean(rep.parentesco).toLowerCase();
    if (!PARENTESCOS_VALIDOS.has(p)) {
      errs.push(
        `${tag}: parentesco "${rep.parentesco}" no es válido. ` +
        `Usa: ${[...PARENTESCOS_VALIDOS].join(", ")}.`
      );
    }
  }

  return errs;
}

// ---------------------------------------------------------------------------
// Función que procesa UN estudiante y TODOS sus representantes.
// Devuelve un array de errores (vacío = éxito).
// ---------------------------------------------------------------------------

async function processStudent(
  supabase: ReturnType<typeof createClient>,
  row: StudentRow,
  fila: number,
  colegio_id: string,
): Promise<RowError[]> {
  const errores: RowError[] = [];
  const cedEst    = clean(row.cedula_estudiante);
  const nombres   = clean(row.nombres_estudiante);
  const apellidos = clean(row.apellidos_estudiante);

  // ── Validaciones del estudiante ────────────────────────────────────────
  if (!cedEst || !nombres || !apellidos) {
    errores.push({
      fila,
      cedula: cedEst || "—",
      motivo: "cedula_estudiante, nombres_estudiante y apellidos_estudiante son obligatorios.",
    });
    return errores; // sin estudiante no tiene sentido seguir
  }

  const fechaNac = clean(row.fecha_nacimiento) || null;
  if (fechaNac && !isValidDate(fechaNac)) {
    errores.push({
      fila,
      cedula: cedEst,
      motivo: `fecha_nacimiento "${fechaNac}" no es válida. Usa formato yyyy-mm-dd.`,
    });
    return errores;
  }

  // ── Validaciones de representantes ────────────────────────────────────
  const reps: RepData[] = Array.isArray(row.representantes) ? row.representantes : [];

  if (reps.length > MAX_REPS_PER_STUDENT) {
    errores.push({
      fila,
      cedula: cedEst,
      motivo: `Se enviaron ${reps.length} representantes; el máximo permitido es ${MAX_REPS_PER_STUDENT}.`,
    });
    return errores;
  }

  // Detectar cédulas duplicadas dentro de la misma fila
  const cedsSeen = new Set<string>();
  for (let ri = 0; ri < reps.length; ri++) {
    const rep = reps[ri];
    const repErrors = validateRep(rep, ri);
    if (repErrors.length > 0) {
      repErrors.forEach((m) => errores.push({ fila, cedula: cedEst, motivo: m }));
    }
    const cedNorm = clean(rep.cedula).toLowerCase();
    if (cedNorm && cedsSeen.has(cedNorm)) {
      errores.push({
        fila,
        cedula: cedEst,
        motivo: `representante[${ri + 1}]: la cédula "${rep.cedula}" aparece más de una vez en esta fila.`,
      });
    }
    cedsSeen.add(cedNorm);
  }

  if (errores.length > 0) return errores; // no escribir nada si hay errores de validación

  // ── 1. Upsert del estudiante ───────────────────────────────────────────
// ── 1. Upsert del estudiante ───────────────────────────────────────────
  const { data: estData, error: estError } = await supabase
    .from("estudiantes")
    .upsert(
      {
        colegio_id,
        cedula:             cedEst,
        nombres,
        apellidos,
        fecha_nacimiento:   fechaNac,
        grado_seccion:      clean(row.grado_seccion) || null,
        activo:             true,
      },
      { onConflict: "colegio_id,cedula", ignoreDuplicates: false }
    )
    .select("id")
    .single();

  if (estError || !estData) {
    errores.push({
      fila,
      cedula: cedEst,
      motivo: `Error al guardar estudiante: ${estError?.message ?? "respuesta vacía"}`,
    });
    return errores;
  }

  const estudianteId: string = estData.id;

  // ── 2. Upsert de cada representante + vínculo ─────────────────────────
  for (let ri = 0; ri < reps.length; ri++) {
    const rep     = reps[ri];
    const tag     = `representante[${ri + 1}]`;
    const cedRep  = clean(rep.cedula);
    const nomRep  = clean(rep.nombres);
    const apRep   = clean(rep.apellidos);

const { data: repData, error: repError } = await supabase
      .from("representantes")
      .upsert(
        {
          colegio_id,
          cedula:            cedRep,
          nombres:           nomRep,
          apellidos:         apRep,
          telefono_whatsapp: clean(rep.telefono) || null,
          email:             clean(rep.email)    || null,
        },
        { onConflict: "colegio_id,cedula", ignoreDuplicates: false }
      )
      .select("id")
      .single();

    if (repError || !repData) {
      errores.push({
        fila,
        cedula: cedEst,
        motivo: `${tag} (${cedRep}): error al guardar representante — ${repError?.message ?? "respuesta vacía"}`,
      });
      continue; // intentar con el siguiente representante
    }

    const representanteId: string = repData.id;

    const parentesco = clean(rep.parentesco) || "Familiar";

    const { error: vinculoError } = await supabase
      .from("representante_estudiante")
      .upsert(
        {
          estudiante_id:    estudianteId,
          representante_id: representanteId,
          parentesco,
          es_responsable_financiero:    parseBool(rep.es_financiero),
        },
        {
          onConflict:       "estudiante_id,representante_id",
          ignoreDuplicates: false,
        }
      );

    if (vinculoError) {
      errores.push({
        fila,
        cedula: cedEst,
        motivo: `${tag} (${cedRep}): error al vincular — ${vinculoError.message}`,
      });
    }
  }

  return errores;
}

// ---------------------------------------------------------------------------
// Handler HTTP
// ---------------------------------------------------------------------------

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonRes({ error: "Método no permitido." }, 405);
  }

  // ── Autenticación ────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonRes({ error: "No autorizado." }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")              ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")      ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return jsonRes({ error: "Sesión inválida." }, 401);
  }

  // ── Body ─────────────────────────────────────────────────────────────────
  let body: { colegio_id: string; rows: StudentRow[] };
  try {
    body = await req.json();
  } catch {
    return jsonRes({ error: "Cuerpo JSON inválido." }, 400);
  }

  const { colegio_id, rows } = body;

  if (!colegio_id) {
    return jsonRes({ error: "colegio_id es obligatorio." }, 400);
  }
  if (!Array.isArray(rows) || rows.length === 0) {
    return jsonRes({ error: "rows debe ser un array no vacío." }, 400);
  }
  if (rows.length > 5000) {
    return jsonRes(
      { error: `Se enviaron ${rows.length} filas; el máximo por llamada es 5000. Divide el archivo.` },
      400
    );
  }

  // ── Verificar que el usuario pertenece a este colegio ───────────────────
  const { data: perfil } = await supabase
    .from("perfiles")
    .select("colegio_id")
    .eq("id", user.id)
    .maybeSingle();

  if (!perfil || perfil.colegio_id !== colegio_id) {
    return jsonRes({ error: "No tienes permiso sobre este colegio." }, 403);
  }

  // ── Procesar filas ────────────────────────────────────────────────────────
  const todosLosErrores: RowError[] = [];
  let exitosos = 0;

  for (let i = 0; i < rows.length; i++) {
    const fila   = i + 2; // fila 1 = encabezado en Excel
    const rowErr = await processStudent(supabase, rows[i], fila, colegio_id);

    if (rowErr.length === 0) {
      exitosos++;
    } else {
      todosLosErrores.push(...rowErr);
    }
  }

  const response: ImportResponse = {
    exitosos,
    errores: todosLosErrores,
    total:   rows.length,
  };

  return jsonRes(response, 200);
});

function jsonRes(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type":                "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}