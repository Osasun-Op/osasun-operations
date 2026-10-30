#!/usr/bin/env python3
"""Compara las funciones que rehace una migración con su versión anterior (Tarea 19).

Uso:  python3 scripts/comparar_funciones.py supabase/migrations/AAAAMMDDHHMMSS_nombre.sql

Por cada `create [or replace] function` de la migración busca su última versión
en las migraciones anteriores de supabase/migrations/ (mismo nombre y mismos
tipos de argumentos) y enseña las líneas que tenía antes y ya no tiene. Las
líneas que solo cambian de sangría no cuentan. Solo lee archivos.

Sale con 1 si alguna función pierde líneas (para mirarlas una a una) y con 0 si no.
"""

import difflib
import re
import sys
from pathlib import Path

CABECERA = re.compile(r"create\s+(?:or\s+replace\s+)?function\s+([\w.]+)\s*\(", re.IGNORECASE)
DOLAR = re.compile(r"\$[A-Za-z_]*\$")


def argumentos(texto, inicio):
    """Texto entre el paréntesis que abre en `inicio - 1` y su pareja."""
    nivel, i = 1, inicio
    while nivel:
        nivel += {"(": 1, ")": -1}.get(texto[i], 0)
        i += 1
    return texto[inicio:i - 1], i


def tipos(args):
    """Clave de la firma: los tipos, sin nombres ni valores por defecto."""
    partes = []
    for a in re.split(r",(?![^(]*\))", args):
        a = re.split(r"\s+default\s+|=", a.strip(), flags=re.IGNORECASE)[0].strip().lower()
        if not a:
            continue
        palabras = a.split()
        if palabras[0] in ("in", "out", "inout", "variadic"):
            palabras = palabras[1:]
        # Sin nombre si la primera palabra ya es un tipo (p. ej. «uuid», «public.tareas»).
        tipo = " ".join(palabras[1:]) if len(palabras) > 1 and palabras[0] not in SINONIMOS else " ".join(palabras)
        partes.append(SINONIMOS.get(tipo, tipo))
    return ",".join(partes)


# Un mismo tipo escrito de dos formas.
SINONIMOS = {"timestamp with time zone": "timestamptz", "int": "integer", "int4": "integer", "bool": "boolean",
             "character varying": "varchar", "timestamp": "timestamp", "timestamp without time zone": "timestamp"}


def funciones(ruta):
    """{(nombre, tipos): (línea de inicio, texto)} de un archivo de migración."""
    texto = ruta.read_text(encoding="utf-8")
    encontradas = {}
    for m in CABECERA.finditer(texto):
        args, despues = argumentos(texto, m.end())
        apertura = DOLAR.search(texto, despues)
        if not apertura:
            continue
        cierre = texto.find(apertura.group(), apertura.end())
        fin = texto.find(";", cierre + len(apertura.group()))
        nombre = m.group(1).lower()
        if "." not in nombre:
            nombre = "public." + nombre
        linea = texto.count("\n", 0, m.start()) + 1
        encontradas[(nombre, tipos(args))] = (linea, texto[m.start():fin + 1])
    return encontradas


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    nueva = Path(sys.argv[1])
    carpeta = nueva.parent
    anteriores = sorted(p for p in carpeta.glob("*.sql") if p.name < nueva.name)
    pierden = 0
    for clave, (_, texto) in sorted(funciones(nueva).items()):
        previa = None
        for p in anteriores:
            f = funciones(p).get(clave)
            if f:
                previa = (p, *f)
        firma = f"{clave[0]}({clave[1]})"
        if not previa:
            print(f"· {firma}: nueva")
            continue
        archivo, linea, antes = previa
        quitadas = [l for l in difflib.ndiff([x.strip() for x in antes.splitlines()],
                                             [x.strip() for x in texto.splitlines()])
                    if l.startswith("- ") and l[2:].strip()]
        if not quitadas:
            print(f"✔ {firma}: no pierde nada (antes en {archivo.name}:{linea})")
            continue
        pierden += 1
        print(f"✘ {firma}: pierde {len(quitadas)} líneas frente a {archivo.name}:{linea}")
        for l in quitadas:
            print(f"    - {l[2:]}")
    return 1 if pierden else 0


if __name__ == "__main__":
    sys.exit(main())
