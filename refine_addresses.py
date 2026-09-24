import time
import requests
import unicodedata
from difflib import SequenceMatcher

SUPABASE_URL = "https://vsieeihstajlrdvpuooh.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4"

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Accept-Profile": "carnavalapp",
    "Content-Profile": "carnavalapp"
}

# IMPORTANTE: Forzar español y User-Agent descriptivo
NOMINATIM_HEADERS = {
    'User-Agent': 'VentIQ-AddressRefiner/1.0 (contacto@ventiq.app)',
    'Accept-Language': 'es'
}

def normalizar_texto(texto):
    if not texto:
        return ""
    # Quitar tildes, mayúsculas y caracteres extraños
    texto = ''.join(
        c for c in unicodedata.normalize('NFD', str(texto))
        if unicodedata.category(c) != 'Mn'
    ).lower().strip()
    
    # Quitar palabras comunes que ensucian el matching (ruido)
    ruido = ['calle', 'avenida', 'avda', 'plaza', 'paseo', 'ronda', 'carretera', 
             'cv', 'c.', 'c/', 'de', 'la', 'el', 'en', 'los', 'las', 'san', 'santa']
    for word in ruido:
        texto = texto.replace(f" {word} ", " ").replace(f"{word} ", "")
        
    return ' '.join(texto.split()) # Normalizar espacios dobles

def obtener_datos_db():
    # Obtener provincias
    resp_p = requests.get(f"{SUPABASE_URL}/rest/v1/Provincias?select=id,nombre", headers=HEADERS)
    provincias = {normalizar_texto(p['nombre']): p['id'] for p in resp_p.json()}
    
    # Obtener municipios
    resp_m = requests.get(f"{SUPABASE_URL}/rest/v1/municipios?select=id,municipio,provincia", headers=HEADERS)
    municipios = []
    for m in resp_m.json():
        municipios.append({
            'id': m['id'],
            'nombre_norm': normalizar_texto(m['municipio']),
            'provincia_id': m['provincia']
        })
    return provincias, municipios

provincias_map, municipios_map = obtener_datos_db()

def fuzzy_match(target, candidates, threshold=0.75):
    """Busca la mejor coincidencia difusa (tolera pequeños errores)"""
    best_match = None
    best_ratio = 0
    target_norm = normalizar_texto(target)
    if not target_norm:
        return None, None
        
    for cand in candidates:
        # Calcular similitud
        ratio = SequenceMatcher(None, target_norm, cand['nombre_norm']).ratio()
        
        # Bonus si uno contiene al otro
        if target_norm in cand['nombre_norm'] or cand['nombre_norm'] in target_norm:
            ratio = max(ratio, 0.90)
            
        if ratio > best_ratio and ratio >= threshold:
            best_ratio = ratio
            best_match = cand
            
    return best_match, best_ratio

def matchear_ubicacion(state_api, city_api):
    prov_id = None
    mun_id = None
    
    # 1. Intentar matchear Provincia
    state_norm = normalizar_texto(state_api)
    for p_nombre, p_id in provincias_map.items():
        if p_nombre in state_norm or state_norm in p_nombre:
            prov_id = p_id
            break
            
    # 2. Intentar matchear Municipio
    # Filtramos por provincia si ya la encontramos para evitar que "Toledo" se confunda con "Toledo (Ohio)"
    mun_candidatos = [m for m in municipios_map if prov_id is None or m['provincia_id'] == prov_id]
    
    # Fuzzy matching para el municipio
    mun_match, ratio = fuzzy_match(city_api, mun_candidatos)
    if mun_match:
        mun_id = mun_match['id']
        prov_id = mun_match['provincia_id'] # Asegurar consistencia con la BD
    else:
        # Si falla, intentamos buscar en toda la base de datos (por si la provincia vino mal)
        mun_match_global, ratio_global = fuzzy_match(city_api, municipios_map, threshold=0.85)
        if mun_match_global:
            mun_id = mun_match_global['id']
            prov_id = mun_match_global['provincia_id']
                
    return prov_id, mun_id

def procesar_direcciones():
    # 🔥 CAMBIO CLAVE: order=id.desc&limit=100
    url_get = f"{SUPABASE_URL}/rest/v1/Direcciones?provincia=eq.1&municipio=eq.4&select=id,address,coordenadas,pueblo&order=id.desc&limit=100"
    resp = requests.get(url_get, headers=HEADERS)
    if resp.status_code != 200:
        print(f"Error al obtener direcciones: {resp.text}")
        return
        
    direcciones = resp.json()
    print(f"📥 Procesando {len(direcciones)} direcciones (Lote más reciente por ID).")
    
    if not direcciones:
        print("✅ No hay direcciones pendientes con provincia=1 y municipio=4.")
        return
    
    # Mostrar el rango de IDs que estamos tocando
    ids = [d['id'] for d in direcciones]
    print(f"🆔 Rango de IDs: {min(ids)} al {max(ids)}")
    
    actualizadas = 0
    for i, dir_row in enumerate(direcciones, 1):
        lat, lon = None, None
        coord = dir_row.get('coordenadas')
        
        if coord and ',' in coord:
            try:
                parts = coord.split(',')
                lat, lon = float(parts[0].strip()), float(parts[1].strip())
            except ValueError:
                pass
                
        state_found, city_found = "", ""
        
        if lat and lon:
            # CORRECCIONES CLAVE:
            # zoom=18 (nivel calle), addressdetails=1 (desglose completo), accept-language=es (nombres en español)
            url_nom = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&zoom=18&addressdetails=1&accept-language=es"
            try:
                r_nom = requests.get(url_nom, headers=NOMINATIM_HEADERS, timeout=10)
                if r_nom.status_code == 200:
                    data = r_nom.json().get('address', {})
                    
                    # En España: 'state' = CCAA, 'province'/'county' = Provincia
                    state_found = data.get('province', '') or data.get('county', '') or data.get('state_district', '') or data.get('state', '')
                    
                    # Jerarquía de poblaciones en Nominatim
                    city_found = (data.get('city', '') or 
                                  data.get('town', '') or 
                                  data.get('municipality', '') or 
                                  data.get('village', '') or 
                                  data.get('hamlet', ''))
                    
                time.sleep(1.2) # Respetar rate limit estricto de Nominatim
            except Exception as e:
                print(f"⚠️ Error Nominatim ID {dir_row['id']}: {e}")
        
        # Fallback: Si no hay coordenadas o Nominatim falló
        if not city_found:
            # Priorizamos 'pueblo' sobre 'address' porque 'address' tiene ruido (Calle Falsa 123...)
            if dir_row.get('pueblo'):
                city_found = dir_row.get('pueblo')
            else:
                city_found = dir_row.get('address', '')

        prov_id, mun_id = matchear_ubicacion(state_found, city_found)
        
        # Actualizar si encontramos algo distinto a los valores por defecto (1 y 4)
        if prov_id is not None and mun_id is not None and (prov_id != 1 or mun_id != 4):
            url_patch = f"{SUPABASE_URL}/rest/v1/Direcciones?id=eq.{dir_row['id']}"
            r_patch = requests.patch(url_patch, headers=HEADERS, json={
                'provincia': prov_id,
                'municipio': mun_id
            })
            if r_patch.status_code in (200, 204):
                print(f"✅ [{i}/{len(direcciones)}] ID {dir_row['id']} -> Prov {prov_id}, Mun {mun_id} | API: '{city_found}'")
                actualizadas += 1
            else:
                print(f"❌ [{i}/{len(direcciones)}] Error ID {dir_row['id']}: {r_patch.text}")
        else:
            # Debug: Ver por qué no se actualizó
            print(f"🔍 [{i}/{len(direcciones)}] ID {dir_row['id']} sin match. API: state='{state_found}', city='{city_found}'")

    print(f"\n🎉 Proceso finalizado. Actualizadas: {actualizadas} de {len(direcciones)}")

if __name__ == '__main__':
    procesar_direcciones()