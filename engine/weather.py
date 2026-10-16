"""Tempo de agora para os shaders, pelo Open-Meteo (sem chave).

O shader recebe `iWeather`, um vec4 de 0 a 1:

    x  nebulosidade          (cloud_cover / 100; neblina conta como 1)
    y  chuva                 (pela precipitação e pelo código do tempo)
    z  trovoada              (1 com trovoada, 0 sem)
    w  vento                 (velocidade a 10 m, 50 km/h ou mais é 1)

Nada aqui toca em GTK; o renderer chama fetch() e geocode() fora da thread
principal. Só a latitude e a longitude da cidade saem da máquina.
"""

import json
import os
import urllib.parse
import urllib.request

from . import packages

FORECAST_URL = 'https://api.open-meteo.com/v1/forecast'
GEOCODE_URL = 'https://geocoding-api.open-meteo.com/v1/search'
CACHE_FILE = os.path.join(os.path.dirname(packages.THUMB_DIR), 'weather.json')
TIMEOUT = 20
CLEAR = (0.0, 0.0, 0.0, 0.0)

# Chuva mínima por código WMO, para garoa e pancadas que ainda não somaram
# precipitação no intervalo.
RAIN_BY_CODE = {
    51: 0.20, 53: 0.30, 55: 0.40,           # garoa
    56: 0.30, 57: 0.45,                      # garoa congelante
    61: 0.40, 63: 0.65, 65: 0.90,           # chuva
    66: 0.45, 67: 0.80,                      # chuva congelante
    80: 0.45, 81: 0.70, 82: 0.95,           # pancadas
    95: 0.80, 96: 0.90, 99: 1.00,           # trovoada
}


class WeatherError(Exception):
    pass


def _get(url, params):
    query = urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(f'{url}?{query}', timeout=TIMEOUT) as r:
            return json.loads(r.read(256 * 1024))
    except (OSError, ValueError) as e:
        raise WeatherError(f'Não foi possível consultar o tempo: {e}') from e


def _clamp(v):
    return max(0.0, min(1.0, float(v)))


def from_current(current):
    """Converte o bloco `current` do Open-Meteo no vec4 do shader."""
    code = int(current.get('weather_code') or 0)
    clouds = _clamp((current.get('cloud_cover') or 0) / 100)
    if code in (45, 48):                     # neblina
        clouds = 1.0
    rain = max(_clamp((current.get('precipitation') or 0) / 4.0),
               RAIN_BY_CODE.get(code, 0.0))
    if rain > 0:
        clouds = max(clouds, 0.55 + 0.45 * rain)
    thunder = 1.0 if code >= 95 else 0.0
    wind = _clamp((current.get('wind_speed_10m') or 0) / 50)
    return (clouds, rain, thunder, wind)


def fetch(latitude, longitude):
    data = _get(FORECAST_URL, {
        'latitude': f'{latitude:.4f}', 'longitude': f'{longitude:.4f}',
        'current': 'cloud_cover,precipitation,weather_code,wind_speed_10m',
        'wind_speed_unit': 'kmh',
    })
    current = data.get('current')
    if not isinstance(current, dict):
        raise WeatherError('Resposta do Open-Meteo sem o tempo atual')
    return from_current(current), current


def geocode(name):
    """Cidades que batem com o nome: [(rótulo, latitude, longitude)]."""
    data = _get(GEOCODE_URL, {'name': name, 'count': 8, 'language': 'pt',
                              'format': 'json'})
    found = []
    for r in data.get('results') or []:
        parts = [r.get('name'), r.get('admin1'), r.get('country_code')]
        label = ', '.join(p for p in parts if p)
        found.append((label, float(r['latitude']), float(r['longitude'])))
    return found


def load_cache():
    try:
        with open(CACHE_FILE) as f:
            data = json.load(f)
        return tuple(_clamp(v) for v in data['value'][:4]), data
    except (OSError, ValueError, KeyError, TypeError):
        return None, None


def save_cache(value, current, latitude, longitude, fetched_at):
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    tmp = CACHE_FILE + '.tmp'
    with open(tmp, 'w') as f:
        json.dump({'value': list(value), 'current': current,
                   'latitude': latitude, 'longitude': longitude,
                   'fetched_at': fetched_at}, f)
    os.replace(tmp, CACHE_FILE)
