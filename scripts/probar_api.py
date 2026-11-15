"""Pruebas HTTP con la API iniciada. --actualizar prueba tambien RSS y las 4 fases."""
import argparse
import json
import time
import urllib.error
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url', default='http://127.0.0.1:8000')
parser.add_argument('--actualizar', action='store_true')
args = parser.parse_args()

def call(path, body=None, headers=None, expected=200):
    req = urllib.request.Request(args.url + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type': 'application/json', **(headers or {})})
    try:
        response = urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as err:
        response = err
    assert response.status == expected, (path, response.status, response.read().decode())
    return json.loads(response.read())

assert call('/api/health')['ok']
snapshot = call('/api/snapshot')
articles = snapshot['articles']
assert len(articles) == snapshot['meta']['total']
assert all(isinstance(a[k], list) for a in articles for k in ('tokens','teams','topics','competitions'))
assert not any(a['topic'] in ('FALSE','TRUE') for a in articles)
answer = call('/api/chat', {'question': 'Cuantas noticias hay?'})
assert answer['scopeCount'] == len(articles)
team = next((a['teams'][0] for a in articles if a['teams']), None)
if team:
    selected = [a for a in articles if team in a['teams']]
    answer = call('/api/chat', {'question': 'Ultimas noticias', 'filters': {'team': team}})
    assert answer['scopeCount'] == len(selected)
    assert set(answer['articles']) <= {a['id'] for a in selected}
assert call('/api/chat', {'question': 'Ultimas noticias', 'filters': {'ids': []}})['scopeCount'] == 0
call('/api/chat', {'question': ''}, expected=400)
call('/api/chat', {'question': ['incorrecta']}, expected=400)
call('/api/chat', {'question': 'noticias', 'filters': {'from': 'incorrecta'}}, expected=400)
call('/api/settings', {'automatic': 'si'}, expected=400)
call('/api/settings', {'automatic': False}, {'Origin': 'https://example.org'}, expected=403)
status = call('/api/status')
assert isinstance(status['running'], bool) and isinstance(status['automatic'], bool)
assert call('/api/settings', {'automatic': not status['automatic']})['automatic'] != status['automatic']
call('/api/settings', {'automatic': status['automatic']})
assert len(call('/api/logs')) == 4
html = urllib.request.urlopen(args.url, timeout=30).read().decode()
assert 'FootDataAI' in html and '/assets/' in html
print(f'HTTP: endpoints, validacion, origen, chat y contexto correctos. {len(articles)} noticias.', flush=True)

if args.actualizar:
    started = call('/api/update', {})
    if not started['started']:
        print(started['message'], flush=True)
        if started['status']['cooldownSeconds'] > 0:
            print('Intervalo RSS verificado. No se fuerza una segunda consulta.', flush=True)
    else:
        assert not call('/api/update', {})['started'], 'Se permitieron dos procesos simultaneos'
        limit = time.monotonic() + 240
        last_phase = None
        while time.monotonic() < limit:
            state = call('/api/status')
            # La API debe continuar sirviendo una instantanea completa durante el trabajo.
            assert len(call('/api/snapshot')['articles']) >= len(articles)
            if state['phase'] != last_phase:
                print('Fase:', state['phase'], flush=True)
                last_phase = state['phase']
            if not state['running']:
                assert state['state'] == 'COMPLETADO', state
                fresh = call('/api/snapshot')
                assert fresh['meta']['total'] >= len(articles)
                assert call('/api/chat', {'question': 'Cuantas noticias hay?'})['scopeCount'] == fresh['meta']['total']
                assert not call('/api/update', {})['started']
                print(f'RSS + SQLite + tokens + mineria + chatbot verificados. {fresh["meta"]["total"]} noticias.', flush=True)
                break
            time.sleep(3)
        else:
            raise TimeoutError('La actualizacion no termino en 4 minutos.')
