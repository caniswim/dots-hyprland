#!/home/brunno/.config/quickshell/ii/scripts/.venv/bin/python3
"""
Sincroniza fotos de um álbum do iCloud para cache local.

Uso:
    # Primeira autenticação (requer 2FA)
    ./icloud_sync.py --auth --email "seu@email.com"

    # Listar álbuns
    ./icloud_sync.py --list

    # Sincronizar álbum
    ./icloud_sync.py --album "Noiva" --max 200

    # Gerar metadados para fotos existentes
    ./icloud_sync.py --metadata
"""

import sys
import argparse
import re
import hashlib
import json
import time
from pathlib import Path
from datetime import datetime

try:
    from pyicloud import PyiCloudService
except ImportError:
    print("ERRO: pyicloud não instalado.")
    sys.exit(1)

try:
    from PIL import Image
    from PIL.ExifTags import TAGS, GPSTAGS
    PILLOW_AVAILABLE = True
except ImportError:
    PILLOW_AVAILABLE = False

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# Extensões de vídeo para ignorar
VIDEO_EXTENSIONS = {'.mov', '.mp4', '.avi', '.mkv', '.m4v', '.3gp'}

# Extensões de imagem suportadas
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'}

# Meses em português
MONTHS_PT = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
             'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']


def format_date_pt(date_str: str) -> str:
    """Formata data no estilo Apple em português.

    Mostra o ano apenas quando diferente do ano atual.
    Ex: "27 de dezembro" ou "27 de dezembro de 2023"
    """
    try:
        if ' ' in date_str:
            dt = datetime.strptime(date_str, "%Y:%m:%d %H:%M:%S")
        else:
            dt = datetime.strptime(date_str, "%Y-%m-%d")

        current_year = datetime.now().year

        if dt.year == current_year:
            return f"{dt.day} de {MONTHS_PT[dt.month - 1]}"
        else:
            return f"{dt.day} de {MONTHS_PT[dt.month - 1]} de {dt.year}"
    except Exception:
        return ""


def gps_to_decimal(coords, ref) -> float | None:
    """Converte GPS DMS (graus, minutos, segundos) para decimal."""
    if not coords:
        return None
    try:
        d, m, s = coords
        # Handle IFDRational objects
        if hasattr(d, 'numerator'):
            d = float(d.numerator) / float(d.denominator) if d.denominator else 0
        if hasattr(m, 'numerator'):
            m = float(m.numerator) / float(m.denominator) if m.denominator else 0
        if hasattr(s, 'numerator'):
            s = float(s.numerator) / float(s.denominator) if s.denominator else 0

        decimal = float(d) + float(m)/60 + float(s)/3600
        if ref in ['S', 'W']:
            decimal = -decimal
        return decimal
    except Exception:
        return None


def extract_exif_metadata(filepath: Path) -> dict | None:
    """Extrai data e GPS do EXIF da foto."""
    if not PILLOW_AVAILABLE:
        return None

    try:
        img = Image.open(filepath)
        exif = img._getexif()
        if not exif:
            return None

        metadata = {}

        # Extrai data
        for tag_id, value in exif.items():
            tag = TAGS.get(tag_id)
            if tag == 'DateTimeOriginal':
                metadata['date'] = value  # "2025:10:11 18:32:39"
                metadata['date_formatted'] = format_date_pt(value)
                break

        # Extrai GPS (tag 34853 é GPSInfo)
        gps_info = exif.get(34853)
        if gps_info:
            lat = gps_to_decimal(gps_info.get(2), gps_info.get(1))
            lon = gps_to_decimal(gps_info.get(4), gps_info.get(3))
            if lat is not None and lon is not None:
                metadata['lat'] = lat
                metadata['lon'] = lon

        return metadata if metadata else None
    except Exception as e:
        return None


def load_geocode_cache(cache_file: Path) -> dict:
    """Carrega cache de geocoding."""
    if cache_file.exists():
        try:
            return json.loads(cache_file.read_text())
        except Exception:
            pass
    return {}


def save_geocode_cache(cache_file: Path, cache: dict):
    """Salva cache de geocoding."""
    try:
        cache_file.write_text(json.dumps(cache, indent=2, ensure_ascii=False))
    except Exception:
        pass


def reverse_geocode(lat: float, lon: float) -> tuple[str | None, str | None]:
    """Converte coordenadas em nome da cidade usando Nominatim."""
    if not REQUESTS_AVAILABLE:
        return None, None

    try:
        url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json&accept-language=pt-BR"
        headers = {'User-Agent': 'QuickshellPhotoWidget/1.0'}
        response = requests.get(url, headers=headers, timeout=10)
        data = response.json()

        address = data.get('address', {})
        city = (address.get('city') or
                address.get('town') or
                address.get('village') or
                address.get('municipality'))
        state = address.get('state')

        return city, state
    except Exception:
        return None, None


def get_city_cached(lat: float, lon: float, cache: dict, cache_file: Path) -> dict:
    """Obtém cidade do cache ou faz geocoding."""
    # Arredonda para ~100m de precisão para cache
    key = f"{round(lat, 3)},{round(lon, 3)}"

    if key in cache:
        return cache[key]

    city, state = reverse_geocode(lat, lon)
    result = {"city": city, "state": state}
    cache[key] = result
    save_geocode_cache(cache_file, cache)

    # Rate limiting para Nominatim (1 req/sec)
    time.sleep(1)

    return result


def generate_metadata(output_dir: Path):
    """Gera metadata.json para todas as fotos existentes."""
    if not PILLOW_AVAILABLE:
        print("ERRO: Pillow não instalado. Execute:")
        print("  pip install Pillow")
        sys.exit(1)

    metadata_file = output_dir / "metadata.json"
    geocode_cache_file = output_dir / ".geocode_cache.json"

    # Carrega metadados existentes
    existing_metadata = {}
    if metadata_file.exists():
        try:
            existing_metadata = json.loads(metadata_file.read_text())
        except Exception:
            pass

    # Carrega cache de geocoding
    geocode_cache = load_geocode_cache(geocode_cache_file)

    # Lista arquivos de imagem
    image_files = []
    for ext in IMAGE_EXTENSIONS:
        image_files.extend(output_dir.glob(f"*{ext}"))
        image_files.extend(output_dir.glob(f"*{ext.upper()}"))

    print(f"Processando {len(image_files)} imagens...")
    print("-" * 50)

    processed = 0
    skipped = 0
    errors = 0
    geocoded = 0

    for filepath in image_files:
        filename = filepath.name

        # Pula se já tem metadados completos
        if filename in existing_metadata:
            meta = existing_metadata[filename]
            if meta.get('date_formatted') and (meta.get('city') or not meta.get('lat')):
                skipped += 1
                continue

        print(f"Processando: {filename}...", end=" ", flush=True)

        exif_data = extract_exif_metadata(filepath)

        if not exif_data:
            print("sem EXIF")
            errors += 1
            continue

        # Geocoding se tiver GPS
        if 'lat' in exif_data and 'lon' in exif_data:
            geo = get_city_cached(exif_data['lat'], exif_data['lon'],
                                  geocode_cache, geocode_cache_file)
            if geo.get('city'):
                exif_data['city'] = geo['city']
                geocoded += 1
            if geo.get('state'):
                exif_data['state'] = geo['state']

        existing_metadata[filename] = exif_data
        processed += 1

        info_parts = []
        if exif_data.get('date_formatted'):
            info_parts.append(exif_data['date_formatted'])
        if exif_data.get('city'):
            info_parts.append(exif_data['city'])

        print(" | ".join(info_parts) if info_parts else "processado")

    # Salva metadados
    metadata_file.write_text(json.dumps(existing_metadata, indent=2, ensure_ascii=False))

    print("-" * 50)
    print(f"Processados: {processed}")
    print(f"Já existiam: {skipped}")
    print(f"Sem EXIF: {errors}")
    print(f"Geolocalizados: {geocoded}")
    print(f"Total no metadata.json: {len(existing_metadata)}")


def get_2fa_code_gui() -> str | None:
    """Abre janela GTK para pedir código 2FA."""
    import subprocess
    try:
        result = subprocess.run([
            'zenity', '--entry',
            '--title=iCloud 2FA',
            '--text=Digite o código 2FA enviado para seus dispositivos Apple:',
            '--width=300'
        ], capture_output=True, text=True, timeout=300)
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception:
        return None


def get_api(email: str = None, password: str = None, code_2fa: str = None):
    """Retorna API autenticada do iCloud."""
    try:
        if email and password:
            api = PyiCloudService(email, password)
        elif email:
            api = PyiCloudService(email)
        else:
            api = PyiCloudService()
    except Exception as e:
        print(f"ERRO ao conectar: {e}")
        sys.exit(1)

    if api.requires_2fa:
        if code_2fa:
            code = code_2fa
        elif sys.stdin.isatty():
            # Terminal interativo - pede no terminal
            print("=" * 50)
            print("AUTENTICAÇÃO 2FA NECESSÁRIA!")
            print("Código enviado para seus dispositivos Apple.")
            print("=" * 50)
            code = input("Digite o código 2FA: ").strip()
        else:
            # Sem terminal - abre janela GTK
            print("2FA necessário, abrindo janela...")
            code = get_2fa_code_gui()
            if not code:
                print("ERRO: 2FA cancelado ou timeout!")
                sys.exit(1)

        if not api.validate_2fa_code(code):
            print("ERRO: Código inválido!")
            sys.exit(1)

        print("2FA validado!")
        if not api.is_trusted_session:
            api.trust_session()

    return api


def list_albums(api):
    """Lista álbuns disponíveis."""
    print("\nÁlbuns disponíveis:")
    print("-" * 40)
    for album in api.photos.albums:
        print(f"  - {album.title}")
    print("-" * 40)


def sync_albums(api, album_names: list, output_dir: Path, max_photos: int = 100):
    """Sincroniza fotos de múltiplos álbuns."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Encontra todos os álbuns
    albums = []
    available_albums = {a.title: a for a in api.photos.albums}

    for album_name in album_names:
        if album_name in available_albums:
            albums.append(available_albums[album_name])
            print(f"✓ Álbum encontrado: {album_name}")
        else:
            print(f"✗ Álbum não encontrado: {album_name}")

    if not albums:
        print("\nERRO: Nenhum álbum válido encontrado.")
        list_albums(api)
        sys.exit(1)

    print(f"\nDestino: {output_dir}")

    # Lista arquivos existentes
    existing = set()
    for f in output_dir.iterdir():
        if f.is_file() and not f.name.startswith('.'):
            existing.add(f.stem.split('_', 1)[0])

    print(f"Já existem {len(existing)} fotos no cache")
    print("-" * 50)

    downloaded = 0
    skipped_existing = 0
    skipped_video = 0
    skipped_format = 0
    skipped_duplicate = 0
    errors = 0
    seen_hashes = set()  # Evita duplicatas entre álbuns

    for album in albums:
        if downloaded >= max_photos:
            break

        print(f"\n📁 Processando: {album.title}")

        for photo in album:
            if downloaded >= max_photos:
                print(f"\nLimite de {max_photos} fotos atingido.")
                break

            filename = photo.filename
            ext = Path(filename).suffix.lower()

            # Ignora vídeos
            if ext in VIDEO_EXTENSIONS:
                skipped_video += 1
                continue

            # Ignora formatos não suportados (DNG, etc.)
            if ext not in IMAGE_EXTENSIONS:
                skipped_format += 1
                continue

            # ID único baseado no hash
            photo_hash = hashlib.md5(filename.encode()).hexdigest()[:12]

            # Verifica duplicata entre álbuns (mesma foto em Noiva e Favorites)
            if photo_hash in seen_hashes:
                skipped_duplicate += 1
                continue
            seen_hashes.add(photo_hash)

            if photo_hash in existing:
                skipped_existing += 1
                continue

            # Nome seguro
            safe_name = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
            filepath = output_dir / f"{photo_hash}_{safe_name}"

            try:
                print(f"Baixando: {filename}...", end=" ", flush=True)
                download = photo.download('medium')

                if download is None:
                    # Tenta versão original se medium não disponível
                    download = photo.download('original')

                if download is None:
                    print("ERRO: download retornou None")
                    errors += 1
                    continue

                # Escreve o arquivo
                with open(filepath, 'wb') as f:
                    if hasattr(download, 'iter_content'):
                        for chunk in download.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                    elif hasattr(download, 'content'):
                        f.write(download.content)
                    elif hasattr(download, 'raw'):
                        f.write(download.raw.read())
                    elif isinstance(download, bytes):
                        f.write(download)
                    else:
                        f.write(bytes(download))

                print("OK")
                downloaded += 1
                existing.add(photo_hash)

            except Exception as e:
                print(f"ERRO: {e}")
                errors += 1
                if filepath.exists():
                    filepath.unlink()

    print("\n" + "=" * 50)
    print(f"📊 RESUMO:")
    print(f"  Baixadas: {downloaded}")
    print(f"  Já existiam: {skipped_existing}")
    print(f"  Duplicatas entre álbuns: {skipped_duplicate}")
    print(f"  Vídeos ignorados: {skipped_video}")
    print(f"  Formatos ignorados: {skipped_format}")
    print(f"  Erros: {errors}")
    print(f"  Total no cache: {len(list(output_dir.glob('*')))}")

    # Metadados
    (output_dir / ".last_sync").write_text(f"{downloaded} novas fotos")


def main():
    parser = argparse.ArgumentParser(description='Sincroniza fotos do iCloud')
    parser.add_argument('--auth', action='store_true', help='Autenticação interativa')
    parser.add_argument('--email', type=str, help='Email do iCloud')
    parser.add_argument('--password', type=str, help='Senha (opcional)')
    parser.add_argument('--list', action='store_true', help='Lista álbuns')
    parser.add_argument('--album', type=str,
                        help='Nome do(s) álbum(ns), separados por vírgula. Ex: "Noiva,Favorites"')
    parser.add_argument('--output', type=str,
                        default='~/.cache/quickshell/icloud-photos',
                        help='Diretório de saída')
    parser.add_argument('--max', type=int, default=200, help='Máximo de fotos')
    parser.add_argument('--metadata', action='store_true',
                        help='Gera metadata.json com data/cidade das fotos')
    parser.add_argument('--2fa', type=str, dest='code_2fa',
                        help='Código 2FA (para autenticação não-interativa)')

    args = parser.parse_args()
    output_dir = Path(args.output).expanduser()

    if args.metadata:
        generate_metadata(output_dir)
        return

    if args.auth:
        if not args.email:
            print("ERRO: --email é obrigatório com --auth")
            sys.exit(1)
        api = get_api(args.email, args.password)
        print("\nAutenticação concluída!")
        list_albums(api)
        return

    api = get_api(args.email, args.password)

    if args.list:
        list_albums(api)
        return

    if args.album:
        # Suporta múltiplos álbuns separados por vírgula
        album_names = [name.strip() for name in args.album.split(',')]
        sync_albums(api, album_names, output_dir, args.max)
        return

    parser.print_help()


if __name__ == '__main__':
    main()
