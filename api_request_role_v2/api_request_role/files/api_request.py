#!/usr/bin/env python3
import os
import sys
import json
import logging
import requests
import urllib3

try:
    from requests_ntlm import HttpNtlmAuth
except ImportError:
    print("HATA: 'requests_ntlm' modülü eksik. Kurulum: pip install requests requests-ntlm")
    sys.exit(1)

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# 🔹 Logging yapılandırması (DEBUG seviyesi)
logging.basicConfig(
    level=logging.DEBUG,
    format='[%(levelname)s] %(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def get_env_var(name, required=True, default=None):
    """Environment değişkenini al, boşsa hata ver veya varsayılanı döndür."""
    value = os.getenv(name)
    if required and (value is None or value.strip() == ""):
        logger.error(f"Gerekli environment değişkeni eksik veya boş: {name}")
        sys.exit(1)
    return value.strip() if value else default


def make_api_request():
    # 🔹 Temel değişkenler
    url = get_env_var("API_URL")
    method = get_env_var("API_METHOD", required=False, default="GET").upper()
    auth_type = get_env_var("API_AUTH_TYPE", required=True).lower()
    username = get_env_var("API_USERNAME")
    password = get_env_var("API_PASSWORD")

    # 🔹 Opsiyonel değişkenler
    domain = get_env_var("API_DOMAIN", required=False)
    headers_json = get_env_var("API_HEADERS", required=False)
    data_json = get_env_var("API_DATA", required=False)
    
    # 🔹 Timeout (connection, read) - ENV'den veya varsayılan
    timeout_str = get_env_var("API_TIMEOUT", required=False, default="10,30")
    try:
        if "," in timeout_str:
            connect_timeout, read_timeout = map(int, timeout_str.split(","))
        else:
            connect_timeout = read_timeout = int(timeout_str)
    except ValueError:
        logger.error(f"API_TIMEOUT geçersiz format: '{timeout_str}' (örnek: '10,30' veya '20')")
        sys.exit(1)
    
    verify_ssl = get_env_var("API_VERIFY_SSL", required=False, default="true").lower() == "true"

    # 🔹 SSL uyarılarını sustur
    if not verify_ssl:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        logger.warning("SSL doğrulama devre dışı - InsecureRequestWarning susturuldu")

    # 🔹 Auth tipi kontrol
    if auth_type not in ["basic", "ntlm"]:
        logger.error("API_AUTH_TYPE 'basic' veya 'ntlm' olmalı")
        sys.exit(1)

    if auth_type == "ntlm" and not domain:
        logger.error("NTLM için API_DOMAIN gerekli")
        sys.exit(1)

    # 🔹 Headers / Data JSON parse
    headers = {}
    if headers_json:
        try:
            headers = json.loads(headers_json)
            logger.debug(f"Headers: {headers}")
        except json.JSONDecodeError as e:
            logger.error(f"API_HEADERS geçersiz JSON: {e}")
            sys.exit(1)

    data = None
    if data_json:
        try:
            data = json.loads(data_json)
            logger.debug(f"Request Body: {json.dumps(data, indent=2)}")
        except json.JSONDecodeError as e:
            logger.error(f"API_DATA geçersiz JSON: {e}")
            sys.exit(1)

    # 🔹 GET / DELETE için body gönderilmez
    if method in ["GET", "DELETE"] and data is not None:
        logger.warning(f"{method} isteği için body gönderilmeyecek (API_DATA yok sayılıyor)")
        data = None

    # 🔹 Retry stratejisi (3 deneme, backoff, belirli HTTP kodları)
    retry_strategy = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["HEAD", "GET", "PUT", "DELETE", "OPTIONS", "TRACE", "POST"]
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)

    # 🔹 Session oluştur
    session = requests.Session()
    session.mount("http://", adapter)
    session.mount("https://", adapter)

    if auth_type == "basic":
        session.auth = (username, password)
        logger.debug(f"Auth: Basic ({username})")
    elif auth_type == "ntlm":
        session.auth = HttpNtlmAuth(f"{domain}\\{username}".replace('\\\\', '\\'), password)
        logger.debug(f"Auth: NTLM ({domain}\\{username})")

    logger.info(f"Request: {method} {url} (timeout: {connect_timeout}s connect, {read_timeout}s read, verify_ssl={verify_ssl})")

    # 🔹 API isteği gönder
    try:
        response = session.request(
            method=method,
            url=url,
            headers=headers,
            json=data,
            timeout=(connect_timeout, read_timeout),
            verify=verify_ssl
        )

        logger.info(f"Response: {response.status_code} {response.reason} ({response.elapsed.total_seconds():.2f}s)")

        # 🔹 Encoding düzeltme
        if response.encoding is None or response.encoding == 'ISO-8859-1':
            response.encoding = response.apparent_encoding
            logger.debug(f"Encoding düzeltildi: {response.encoding}")

        # 🔹 Yanıtı JSON olarak döndürmeye çalış
        try:
            response_data = response.json()
        except Exception:
            response_data = {"text": response.text}
            logger.debug("Yanıt JSON değil, text olarak döndürülüyor")

        result = {
            "status_code": response.status_code,
            "ok": response.ok,
            "headers": dict(response.headers),
            "body": response_data,
            "elapsed_seconds": response.elapsed.total_seconds()
        }

        # stdout'a JSON olarak bastır (Ansible from_json ile parse edebilir)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        logger.debug("Sonuç JSON olarak stdout'a yazıldı")
        sys.exit(0)

    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout hatası: {e}")
        error_result = {"error": f"Timeout: {str(e)}"}
        print(json.dumps(error_result, indent=2, ensure_ascii=False))
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        logger.error(f"Request hatası: {e}")
        error_result = {"error": str(e)}
        print(json.dumps(error_result, indent=2, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    make_api_request()
