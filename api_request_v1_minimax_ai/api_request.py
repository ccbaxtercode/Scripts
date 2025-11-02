#!/usr/bin/env python3
import os
import sys
import json
import time
import requests
import urllib3
from typing import Optional, Dict, Any

try:
    from requests_ntlm import HttpNtlmAuth
except ImportError:
    print("HATA: 'requests_ntlm' modülü eksik. Kurulum: pip install requests requests-ntlm")
    sys.exit(1)

# Suppress HTTPS warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def get_env_var(name: str, required: bool = True, default: Optional[str] = None) -> Optional[str]:
    """
    Environment değişkenini al, boşsa hata ver veya varsayılanı döndür.
    
    Args:
        name: Environment değişken adı
        required: Zorunlu değişken olup olmadığı
        default: Varsayılan değer
        
    Returns:
        Environment değişken değeri veya varsayılan değer
    """
    value = os.getenv(name)
    if required and (value is None or value.strip() == ""):
        print(f"HATA: Gerekli environment değişkeni eksik veya boş: {name}")
        sys.exit(1)
    return value.strip() if value else default


def make_api_request() -> None:
    """
    Ana API isteği fonksiyonu - retry mekanizması ile birlikte.
    """
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
    
    # 🔹 Retry ayarları
    max_retries = int(get_env_var("API_MAX_RETRIES", required=False, default="3"))
    retry_delay = int(get_env_var("API_RETRY_DELAY", required=False, default="5"))  # saniye
    retry_backoff = get_env_var("API_RETRY_BACKOFF", required=False, default="true").lower() == "true"
    
    # 🔹 Timeout ve SSL ayarları
    try:
        timeout = int(get_env_var("API_TIMEOUT", required=False, default="30"))
    except ValueError:
        print("HATA: API_TIMEOUT sayısal olmalı")
        sys.exit(1)
    
    verify_ssl = get_env_var("API_VERIFY_SSL", required=False, default="true").lower() == "true"

    # 🔹 Auth tipi kontrol
    if auth_type not in ["basic", "ntlm"]:
        print("HATA: API_AUTH_TYPE 'basic' veya 'ntlm' olmalı.")
        sys.exit(1)

    if auth_type == "ntlm" and not domain:
        print("HATA: NTLM için API_DOMAIN gerekli.")
        sys.exit(1)

    # 🔹 Headers / Data JSON parse
    headers = {}
    if headers_json:
        try:
            headers = json.loads(headers_json)
        except json.JSONDecodeError as e:
            print(f"HATA: API_HEADERS geçersiz JSON: {e}")
            sys.exit(1)

    data = None
    if data_json:
        try:
            data = json.loads(data_json)
        except json.JSONDecodeError as e:
            print(f"HATA: API_DATA geçersiz JSON: {e}")
            sys.exit(1)

    # 🔹 GET / DELETE için body gönderilmez
    if method in ["GET", "DELETE"] and data is not None:
        print(f"[UYARI] {method} isteği için body gönderilmeyecek (API_DATA yok sayılıyor).")
        data = None

    # 🔹 Session oluştur
    session = requests.Session()

    if auth_type == "basic":
        session.auth = (username, password)
    elif auth_type == "ntlm":
        session.auth = HttpNtlmAuth(f"{domain}\\{username}", password)

    # 🔹 Session konfigürasyonu
    session.verify = verify_ssl
    session.headers.update({
        'User-Agent': 'Ansible-API-Client/1.0',
        'Accept': 'application/json'
    })

    print(f"[INFO] {method} {url}")
    print(f"[INFO] Auth: {auth_type.upper()}, Timeout: {timeout}s, Max Retries: {max_retries}")
    print(f"[INFO] Verify SSL: {verify_ssl}, Retry Delay: {retry_delay}s")

    # 🔹 Retry mekanizması ile API isteği gönder
    last_exception = None
    
    for attempt in range(1, max_retries + 1):
        try:
            print(f"\n[DENEME {attempt}/{max_retries}] API isteği gönderiliyor...")
            
            response = session.request(
                method=method,
                url=url,
                headers=headers,
                json=data,
                timeout=timeout
            )

            # 🔹 Yanıtı JSON olarak döndürmeye çalış
            try:
                response_data = response.json()
            except Exception:
                response_data = {"text": response.text}

            result = {
                "status_code": response.status_code,
                "ok": response.ok,
                "headers": dict(response.headers),
                "body": response_data,
                "attempt": attempt,
                "url": url,
                "method": method
            }

            # Başarılı response
            if response.ok:
                print(f"[BAŞARILI] HTTP {response.status_code} - Deneme {attempt}")
                print(json.dumps(result, indent=2, ensure_ascii=False))
                sys.exit(0)
            else:
                # HTTP hata kodları (4xx, 5xx)
                error_msg = f"HTTP {response.status_code} - {response.reason}"
                print(f"[HATA] {error_msg}")
                
                if attempt < max_retries:
                    print(f"[YENIDEN DENEME] {retry_delay} saniye bekleniyor...")
                    if retry_backoff:
                        # Exponential backoff: 1s, 2s, 4s gibi artar
                        delay = retry_delay * (2 ** (attempt - 1))
                        print(f"[BACKOFF] Artan bekleme süresi: {delay}s")
                        time.sleep(delay)
                    else:
                        time.sleep(retry_delay)
                    continue
                else:
                    # Son deneme başarısız
                    print(f"[BAŞARISIZ] Tüm denemeler başarısız - HTTP {response.status_code}")
                    error_result = {
                        "error": f"HTTP {response.status_code} - {response.reason}",
                        "status_code": response.status_code,
                        "body": response_data,
                        "attempts": attempt,
                        "final": True
                    }
                    print(json.dumps(error_result, indent=2, ensure_ascii=False))
                    sys.exit(1)

        except requests.exceptions.Timeout as e:
            last_exception = e
            print(f"[TIMEOUT] Deneme {attempt}: {str(e)}")
            
        except requests.exceptions.ConnectionError as e:
            last_exception = e
            print(f"[BAĞLANTI HATASI] Deneme {attempt}: {str(e)}")
            
        except requests.exceptions.RequestException as e:
            last_exception = e
            print(f"[NETWORK HATASI] Deneme {attempt}: {str(e)}")
            
        except Exception as e:
            last_exception = e
            print(f"[BEKLENMEYEN HATA] Deneme {attempt}: {str(e)}")

        # Retry için bekle
        if attempt < max_retries:
            print(f"[YENIDEN DENEME] {retry_delay} saniye bekleniyor...")
            if retry_backoff:
                # Exponential backoff
                delay = retry_delay * (2 ** (attempt - 1))
                print(f"[BACKOFF] Artan bekleme süresi: {delay}s")
                time.sleep(delay)
            else:
                time.sleep(retry_delay)

    # 🔹 Tüm denemeler başarısız
    error_result = {
        "error": f"Tüm {max_retries} deneme başarısız - Son hata: {str(last_exception)}",
        "attempts": max_retries,
        "final": True
    }
    print(json.dumps(error_result, indent=2, ensure_ascii=False))
    sys.exit(1)


if __name__ == "__main__":
    make_api_request()